// The VBW Stage (mods_4_vbw.md §3.1, §3.2, §3.8): what the band above the prompt
// shows. While a VBW workflow runs, the crew: one row per agent. When `vbw next`
// stops at a human gate, the gate card: a plain sentence and buttons that only
// fill the prompt, open Mission Control or collapse the card; the person sends.
// Otherwise nothing: the hint line already says what comes next, and the band
// takes room only when there is work to watch or a decision to make.
// With full motion and room for them, the crew theme: each agent is a 3-row
// pixel sprite posed by what it does (panel-candy.js); panel.js animates them.
// Pure: data in, a model out (stageModel), a tree out (renderStage). No `$`,
// never changes its input, never throws.
import { poseOf, spriteFrame, encodeCells } from './panel-candy.js'
import { roleColor as colorOfRole, stateColor, STATE_MARKS, NEED, ACCENT } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
const str = (x) => (typeof x === 'string' ? x : '')
const len = (s) => [...s].length

// Cut a line to `n` cells, marking the cut with an ellipsis.
const cut = (s, n) => (len(s) <= n ? s : n <= 0 ? '' : [...s].slice(0, n - 1).join('') + '…')
const pad = (s, n) => s + ' '.repeat(Math.max(0, n - len(s)))
const padStart = (s, n) => ' '.repeat(Math.max(0, n - len(s))) + s

const QUIET_MS = 45000
const DONE_MS = 60000
const FLASH_MS = 1000 // a new row shows inverted this long (full motion only)
const SPIN = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
// A workflow follows these steps of `vbw next`: the moment health nudges matter.
const RUNS = new Set(['plan', 'build', 'qa', 'fix'])
const STARTS_RUN = new Set(['approve', 'escalate', 'unblock', ...RUNS])

// 604 s -> 10m04s; an hour or more -> 1h02m.
function clock(ms) {
  const s = Math.max(0, Math.floor((num(ms) ? ms : 0) / 1000))
  const two = (n) => String(n).padStart(2, '0')
  if (s >= 3600) return Math.floor(s / 3600) + 'h' + two(Math.floor((s % 3600) / 60)) + 'm'
  return Math.floor(s / 60) + 'm' + two(s % 60) + 's'
}

const tokens = (t) => {
  if (!num(t) || t < 0) return ''
  if (t >= 1e6) return (t / 1e6).toFixed(1) + 'M'
  return t >= 1000 ? Math.round(t / 1000) + 'k' : String(Math.round(t))
}

// At most three names, then how many more.
const names = (a) => {
  const xs = (Array.isArray(a) ? a : []).filter((x) => typeof x === 'string' && x)
  return xs.slice(0, 3).join(', ') + (xs.length > 3 ? ' +' + (xs.length - 3) + ' more' : '')
}

// --- the gate card -----------------------------------------------------------

const DISCUSS = ['Discuss', { fill: '/vbw:discuss' }]
const open = (tab) => ({ open: 'mission', tab })
const vibe = { fill: '/vbw:vibe' }

// Each human gate: the sentence after "VBW needs you ·" and its choices, Later last.
function gateOf(nx) {
  const d = isObj(nx.detail) ? nx.detail : {}
  switch (nx.action) {
    case 'approve': {
      const f = names(d.files)
      return [f ? 'test files changed since your approval: ' + f : 'the plan is ready: review it, then approve it to build',
        [['Review plan', open('plan')], ['Approve…', { fill: '/vbw:approve' }], DISCUSS], f]
    }
    case 'accept': {
      const r = names(d.requirements)
      return ['check by hand what only you can judge' + (r ? ': ' + r : ''), [['Verify…', { fill: '/vbw:verify' }], ['Review proof', open('proof')], DISCUSS], r]
    }
    case 'ship': return ['the milestone is proven and accepted: ready to ship', [['Review proof', open('proof')], ['Ship…', vibe], DISCUSS], '']
    case 'milestone': return ['the milestone is shipped: choose what comes next', [['Next milestone…', vibe], DISCUSS], '']
    case 'spec': return ['say what to build: the requirements', [['Write requirements…', vibe], DISCUSS], '']
    case 'escalate': {
      const f = names(d.fixes)
      return ['the fix limit was reached' + (f ? ' for ' + f : '') + ': decide how to go on', [['Review fixes', open('proof')], ['Decide…', vibe], DISCUSS], f]
    }
    case 'unblock': {
      const p = names(d.plans)
      return ['blocked' + (p ? ': ' + p : '') + ', VBW needs your help to go on', [['Review plan', open('plan')], ['Resolve…', vibe], DISCUSS], p]
    }
    case 'scope': return ['commits changed files outside their plans: review them', [['Review proof', open('proof')], ['Resolve…', vibe], DISCUSS], '']
    case 'convert': return ['a VBW 1 plan is here: bring it into VBW 2, or start fresh', [['Convert…', { fill: '/vbw:convert' }], DISCUSS], '']
    default: return [str(nx.instruction) || 'a decision is needed', [['Continue…', vibe]], '']
  }
}

// The weekly-limit line and the /compact offer, only when a workflow is next.
function health(hl, action) {
  const out = { lines: [], compact: false }
  if (!isObj(hl) || !STARTS_RUN.has(action)) return out
  if (num(hl.weekPct) && hl.weekPct >= 80) {
    const w = Math.round(hl.weekPct)
    const per = num(hl.weekPerRun) && hl.weekPerRun > 0 ? 'a run like this used about ' + Math.round(hl.weekPerRun) + '% last time' : 'a long run may reach it'
    out.lines.push({ text: 'Weekly limit ' + w + '%: ' + per + '.', color: hl.weekPct >= 90 ? stateColor('failed') : NEED })
  }
  out.compact = num(hl.contextPct) && hl.contextPct >= 85
  return out
}

function card(kind, key, title, choices, hp, columns) {
  const buttons = [...choices, ['Later', { collapse: true }]].map(([label, action], i) => ({ key: String(i + 1), label, action }))
  if (hp.compact) buttons.push({ key: 'c', label: '/compact first', action: { fill: '/compact' } })
  return { kind, key, title: cut(title, columns), lines: hp.lines.map((l) => ({ ...l, text: cut(l.text, columns) })), buttons }
}

// --- the crew ----------------------------------------------------------------

// One agent as the band shows it, or null when it is not drawn (done long ago).
function rowOf(a, now, motion, ended, born) {
  const role = str(a.role) || 'agent'
  const roleColor = colorOfRole(role)
  const start = num(a.startedAt) ? a.startedAt : now
  const end = num(a.endedAt) ? a.endedAt : null
  const base = { id: str(a.id), role, roleColor, label: str(a.label), elapsed: clock((end ?? now) - start), tokens: tokens(a.tokens), spin: '', button: null }
  if (a.state === 'done') {
    if ((end ?? ended ?? now) + DONE_MS <= now) return null
    return { ...base, glyph: STATE_MARKS.done, glyphColor: stateColor('done'), activity: 'done' + (str(a.result) ? ' · ' + a.result : ''), activityColor: stateColor('done') }
  }
  if (a.state === 'failed') {
    return { ...base, glyph: STATE_MARKS.failed, glyphColor: stateColor('failed'), activity: str(a.result) || 'failed', activityColor: stateColor('failed'),
      button: { label: 'details', action: { open: 'mission', tab: 'now', agent: str(a.id) } } }
  }
  const age = isObj(born) && num(born[base.id]) ? now - born[base.id] : -1
  const row = { ...base, glyph: STATE_MARKS.running, glyphColor: roleColor, ...(motion === 'full' && age >= 0 && age < FLASH_MS ? { flash: true } : {}) }
  const seen = num(a.lastSeenAt) ? a.lastSeenAt : start
  if (a.state === 'quiet' || now - seen >= QUIET_MS) return { ...row, quiet: true, activity: 'quiet ' + clock(now - seen), activityColor: stateColor('quiet') }
  const act = isObj(a.activity) ? a.activity : null
  const said = act && str(act.text) && act.kind === 'text'
  const text = act && str(act.text) ? (said ? '"' + act.text + '"' : act.text) : 'working'
  const step = motion === 'off' ? 0 : Math.floor(now / (motion === 'calm' ? 1000 : 250))
  return { ...row, activity: text, activityColor: undefined, intent: !said, spin: motion === 'off' ? '·' : SPIN[step % SPIN.length] }
}

const ROLE_W = 9
const LABEL_W = 10

// Fit each row to the columns: the activity takes what the fixed cells leave;
// when too narrow, elapsed and tokens go first, then the label shrinks.
function fit(rows, columns, full) {
  const lw = Math.min(LABEL_W, Math.max(0, ...rows.map((r) => len(r.label))))
  return rows.map((r) => {
    const fixed = 2 + ROLE_W + 1 + 2 + (r.spin ? 2 : 0) + (r.button ? len(r.button.label) + 6 : 0)
    let tail = full ? '  ' + padStart(r.elapsed, 6) + '  ' + padStart(r.tokens, 4) : ''
    if (columns - fixed - lw - len(tail) < 8) tail = ''
    const w = Math.max(0, Math.min(lw, columns - fixed - 8))
    const room = Math.max(0, columns - fixed - w - len(tail))
    return { ...r, label: pad(cut(r.label, w), w), activity: cut(r.activity, room), elapsed: tail ? r.elapsed : '', tokens: tail ? r.tokens : '', tail }
  })
}

function crewOf(rn, now, columns, maxRows, motion, cost, born) {
  const ended = num(rn.endedAt) ? rn.endedAt : null
  const agents = rn.agents.filter((a) => isObj(a) && typeof a.id === 'string' && a.id)
  let rows = agents.map((a) => rowOf(a, now, motion, ended, born)).filter(Boolean)
  const doneAll = agents.filter((a) => a.state === 'done').length
  const doneShown = rows.filter((r) => r.glyph === STATE_MARKS.done).length
  const tally = doneAll > doneShown ? doneAll - doneShown + ' done' : null
  let failedKey = false
  rows = rows.map((r) => {
    if (!r.button) return r
    const b = { ...r.button, ...(failedKey ? {} : { key: 'd' }) }
    failedKey = true
    return { ...r, button: { key: b.key, label: b.label, action: b.action } }
  })
  const kind = str(rn.kind) || 'run'
  const time = clock((ended ?? now) - (num(rn.startedAt) ? rn.startedAt : now))
  const status = rn.status === 'running' || !str(rn.status) ? '' : rn.status
  const button = { key: 'p', label: 'Mission Control', action: { open: 'mission' } }
  const room = columns - len(button.label) - 6
  if (maxRows < 4) {
    const working = agents.filter((a) => a.state === 'working' || a.state === 'quiet').length
    const parts = ['VBW ▸ ' + kind, status, working ? working + ' working' : '', doneAll ? doneAll + ' done' : '', time].filter(Boolean)
    return { kind: 'crew', mode: 'line', header: { text: cut(parts.join(' · '), room), button }, rows: [], tally: null, more: 0 }
  }
  const full = maxRows >= 8
  // Sprites: 3 rows an agent, all of them shown, while the run works.
  const sprites = motion === 'full' && full && rn.status === 'running' && 1 + 3 * rows.length + (tally ? 1 : 0) <= maxRows
  if (sprites) {
    const byId = new Map(agents.map((a) => [a.id, a]))
    rows = rows.map((r) => {
      const a = byId.get(r.id)
      return { ...r, spin: '', pose: r.glyph !== STATE_MARKS.running ? a.state : r.quiet ? 'quiet' : poseOf(a.activity, 'working') }
    })
  }
  const parts = ['VBW ▸ ' + kind, status, str(rn.phase), time]
  const price = full && num(cost) && cost >= 0 ? '≈$' + cost.toFixed(2) + ' this run' : ''
  if (price) parts.push(price)
  const room2 = maxRows - 1 - (tally ? 1 : 0)
  let more = 0
  if (rows.length > room2) {
    more = rows.length - (room2 - 1)
    rows = rows.slice(0, room2 - 1)
  }
  // A sprite takes 4 more columns than the dot, and is the row's only motion.
  const model = { kind: 'crew', mode: full ? 'full' : 'compact', header: { text: cut(parts.filter(Boolean).join(' · '), room), ...(price ? { cost: price } : {}), button }, rows: fit(rows, sprites ? columns - 4 : columns, full), tally, more }
  return sprites ? { ...model, sprites: true } : model
}

// --- the model ---------------------------------------------------------------

// What the band shows, in this order: a running crew (while the kernel holds the
// run, a gate in next.json is stale); a human gate; a crew that ended under a
// minute ago; a health nudge before a workflow; else null.
export function stageModel(input) {
  try {
    if (!isObj(input)) return null
    const { run: rn, next: nx, health: hl, cost, motion, born } = input
    const now = num(input.now) ? input.now : Date.now()
    const columns = num(input.columns) && input.columns > 0 ? Math.floor(input.columns) : 80
    const maxRows = num(input.maxRows) && input.maxRows > 0 ? Math.floor(input.maxRows) : 8
    const crew = isObj(rn) && Array.isArray(rn.agents) && rn.agents.some((a) => isObj(a) && typeof a.id === 'string' && a.id)
    if (crew && rn.status === 'running') return crewOf(rn, now, columns, maxRows, motion, cost, born)
    const action = isObj(nx) && typeof nx.action === 'string' ? nx.action : ''
    if (isObj(nx) && nx.gate === true) {
      const [sentence, choices, about] = gateOf(nx)
      return card('gate', 'gate:' + action + ':' + about, '⚑ VBW needs you · ' + sentence, choices, health(hl, action), columns)
    }
    if (crew && num(rn.endedAt) && now - rn.endedAt < DONE_MS) return crewOf(rn, now, columns, maxRows, motion, cost, born)
    if (isObj(nx) && RUNS.has(action)) {
      const hp = health(hl, action)
      if (hp.lines.length || hp.compact) return card('nudge', 'nudge:' + action, 'VBW · before the ' + action + ' run', [], hp, columns)
    }
    return null
  } catch {
    return null
  }
}

// --- the tree ----------------------------------------------------------------

// Draw the model with the elements of $.ui.resolve(e). `onAction(action)` is
// called on a press; without it, Buttons carry no onPress (the plugin's
// ui.press hook answers them by key).
export function renderStage(ui, model, onAction) {
  try {
    if (!isObj(ui) || !isObj(model)) return null
    const { Box, Text, Button } = ui
    const button = (b, id) => h(Button, {
      key: 'vbw-stage-' + id, label: b.label, hotkey: b.key,
      ...(typeof onAction === 'function' ? { onPress: () => onAction(b.action) } : {}),
    })
    if (model.kind === 'gate' || model.kind === 'nudge') {
      if (!Array.isArray(model.buttons)) return null
      return h(Box, { flexDirection: 'column' },
        h(Text, { key: 'title', color: NEED, bold: model.kind === 'gate', wrap: 'truncate-end' }, String(model.title)),
        ...(model.lines || []).map((l, i) => h(Text, { key: 'line-' + i, color: l.color, wrap: 'truncate-end' }, String(l.text))),
        h(Box, { key: 'buttons', flexDirection: 'row', flexWrap: 'wrap', columnGap: 2 }, ...model.buttons.map((b, i) => button(b, 'b' + i + '-' + b.label))))
    }
    if (model.kind !== 'crew' || !isObj(model.header) || !Array.isArray(model.rows)) return null
    const head = String(model.header.text)
    const price = typeof model.header.cost === 'string' && model.header.cost && head.endsWith(model.header.cost) ? model.header.cost : ''
    const header = h(Box, { key: 'header', flexDirection: 'row', justifyContent: 'space-between' },
      h(Box, { flexDirection: 'row' },
        h(Text, { bold: true, wrap: 'truncate-end' }, price ? head.slice(0, head.length - price.length) : head),
        ...(price ? [h(Text, { bold: true, color: ACCENT, wrap: 'truncate-end' }, price)] : [])),
      button(model.header.button, 'mission'))
    // A tool call is its verb (role colour) and its object (dim), cut as one phrase.
    const intent = (r) => {
      const at = r.intent ? r.activity.search(/\s/) : -1
      if (at < 0) return [h(Text, { color: r.intent ? r.roleColor : r.activityColor, wrap: 'truncate-end' }, r.activity)]
      return [h(Text, { color: r.roleColor }, r.activity.slice(0, at)), h(Text, { dimColor: true, wrap: 'truncate-end' }, r.activity.slice(at))]
    }
    const sprite = model.sprites === true && ui.Raster ? (r) => h(ui.Raster, {
      key: 'vbw-sprite-' + r.id, columns: 5, rows: 3, cells: encodeCells(spriteFrame({ role: r.role, pose: r.pose, frame: 0 })),
    }) : null
    const rows = model.rows.map((r) => h(Box, { key: 'agent-' + r.id, flexDirection: 'row' },
      sprite ? sprite(r) : h(Text, { color: r.glyphColor }, r.glyph),
      h(Text, { color: r.roleColor, ...(r.flash ? { inverse: true } : {}) }, ' ' + pad(r.role, ROLE_W) + ' '),
      h(Text, { color: r.roleColor, ...(r.flash ? { inverse: true } : {}) }, r.label + '  '),
      ...(r.spin ? [h(Text, { color: r.roleColor }, r.spin + ' ')] : []),
      ...intent(r),
      ...(r.tail ? [h(Text, { dimColor: true }, r.tail)] : []),
      ...(r.button ? [h(Text, null, '  '), button(r.button, 'details-' + r.id)] : [])))
    const dim = (key, text) => h(Box, { key, flexDirection: 'row' }, h(Text, { dimColor: true }, text))
    return h(Box, { flexDirection: 'column' }, header, ...rows,
      ...(model.more ? [dim('more', '+' + model.more + ' more')] : []), ...(model.tally ? [dim('tally', model.tally)] : []))
  } catch {
    return null
  }
}
