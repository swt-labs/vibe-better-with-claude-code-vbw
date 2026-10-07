// The VBW panel (R51, R53, R55; mods_4_vbw.md): a Claude Code mod that shows what
// VBW is doing. It reads the record, the last `vbw next`, the autonomous run, the
// clone's finished steps, the session's usage and this session's workflow files,
// all on one timer; it writes nothing itself (/vbw-todo hands its text to the
// kernel), and does nothing at all where it cannot run: Claude Code older than
// 2.1.287, or a folder that is not a VBW 2 project. Every hook is wrapped: an error
// here must never reach the user's session. Every function that takes `$` lives in
// this file (Claude Code follows `$` into this file's functions only); what is drawn
// is worked out by the pure modules: panel-stage.js (the band), panel-sites.js (the
// one-line sites and rows), panel-pane.js (Mission Control), panel-view.js, and
// panel-candy.js (motion, sprites, celebrations), whose frames this file blits.
import { panelView, supports, BAND_MIN_VERSION } from './panel-view.js'
import { SOUNDS } from './panel-sounds.js'
import { gatherRun, findRun } from './panel-feed.js'
import { stageModel, renderStage } from './panel-stage.js'
import { statusText, whyText, todoArgs } from './panel-commands.js'
import { renderPane } from './panel-pane.js'
import { stateColor } from './panel-palette.js'
import { SITES, turnPending } from './panel-sites.js'
import { motionOf, spriteFrame, encodeCells, confettiFrames, sweepFrames, wrappedModel, celebration } from './panel-candy.js'

const PANE = 'vbw-panel'
const TICK_MS = 2000
// The user's choice lives in Claude Code's per-user store, never in the project.
// A project holding .vbw/runtime/test-mode is a VBW test session (R64): it plays no
// audio and keeps its choices under test.* keys, never the user's.
const TEST_MARK = '/.vbw/runtime/test-mode'
const keys = (test) => ({ closed: (test ? 'test.' : '') + 'vbw-panel.closed', sound: (test ? 'test.' : '') + 'vbw-panel.sound' })
// One of the plugin's shipped sounds (assets/audio/<character>/), picked at random
// for each request for the user; with none shipped, the panel is silent.
const pick = () => (SOUNDS.length ? { asset: SOUNDS[Math.floor(Math.random() * SOUNDS.length)] } : null)
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
// VBW's workflows, as /vbw:vibe launches them (Workflow name 'vbw:<kind>').
const KINDS = ['planning', 'building', 'fixing', 'verifying', 'mapping', 'researching', 'investigating', 'tooling']
const kindOf = (name) => {
  const k = typeof name === 'string' ? name.replace(/^vbw[:-]/, '') : ''
  return KINDS.includes(k) ? k : null
}

// The motion level (mods_4_vbw.md §3.7, panel-candy.js): a test session is always
// still; else the record's `settings.motion`; else the interview level. The level
// is the one `vbw next` read (private or kept in the project) once the interview is
// done (before that, next fills a neutral level, which says nothing about the
// person), else the project's kept answers; unknown, calm.
const levelOf = (st) => {
  const p = isObj(st.next) && isObj(st.next.profile) ? st.next.profile : null
  if (p && p.interviewed === true) return p.level
  const pr = isObj(st.record) && isObj(st.record.project) ? st.record.project : null
  return pr && isObj(pr.interview) ? pr.interview.level : null
}
const motion = (st) => motionOf({ setting: isObj(st.record) && isObj(st.record.settings) ? st.record.settings.motion : null, level: levelOf(st), testMode: st.silent })
const FRAME_MS = 100 // 10 frames a second, while something moves
const AFTER_MS = 5000 // a celebration never drawn in this long is let go
const CHEER_MS = 60000
// A sprite's cells, encoded once per role, pose and frame (every pose has 2 or 3).
const SPRITES = new Map()
const spriteCells = (role, pose, n) => {
  const k = role + ':' + pose + ':' + (n % 6)
  if (!SPRITES.has(k)) SPRITES.set(k, encodeCells(spriteFrame({ role, pose, frame: n })))
  return SPRITES.get(k)
}
// A celebration: its frames are made for the width of the site that first draws
// it, encoded once; the first is drawn, the rest are blitted.
const effect = (key, at, make) => ({ key, at, make, frames: null, i: 0, site: null })
const drawn = (fx, columns, site) => {
  if (!fx.frames) {
    const f = fx.make(Math.min(512, Math.floor(columns)))
    if (!f.length) return null
    Object.assign(fx, { cols: f[0].cols, rows: f[0].rows, frames: f.map(encodeCells) })
  }
  fx.site = site
  return fx.frames[Math.min(fx.i, fx.frames.length - 1)]
}

// Parse a project file; null when it is not a JSON object (half written, invalid).
function parse(text) {
  try {
    const v = JSON.parse(text)
    return isObj(v) ? v : null
  } catch {
    return null
  }
}

// What the panel knows: the last good state of its files, the live run, what is drawn, what is asked.
function fresh() {
  return {
    live: false, born: {}, timer: null, busy: false, question: null, sound: true, keys: keys(false), silent: false, wouldPlay: 0, alerted: null,
    record: null, next: null, history: null, cost: null, health: null, auto: null, stepsPath: null, steps: null, shown: '', seen: {}, sized: false,
    root: null, sessionId: null, sessionDir: null, runRef: null, run: null, feed: {}, finder: {}, toolRuns: {}, leases: [],
    tab: 'now', phase: null, check: null, agent: null, collapsed: null, suggested: null, before: null, memo: {}, notice: null,
    lastRec: null, crews: {}, anim: null, animBusy: false, frameNo: 0, bandId: null,
    sprites: null, burst: null, sweep: null, cheer: null, wrapped: null,
  }
}

const view = (st, now) => panelView({ record: st.record, next: st.next, question: st.question, now, cost: st.cost, steps: st.steps })

// The session cost moved while the open lease ran; null without both figures.
const openLease = (st) => {
  const l = st.leases[st.leases.length - 1]
  return l && l.costEnd === undefined ? l : null
}
const runCost = (st) => {
  const l = openLease(st)
  return l && num(l.costStart) && num(st.cost) ? st.cost - l.costStart : null
}

// The band's model, for any width: what band() draws and the redraw check compares.
const stage = (st, now, props) => stageModel({
  run: st.run, next: st.next, now, health: st.health, cost: runCost(st), motion: motion(st),
  born: st.born, columns: isObj(props) ? props.bodyColumns : undefined, maxRows: isObj(props) ? props.maxRows : undefined,
})

// Read a file only when its size or time changed; keep the old state when it cannot be used,
// or drop it when `gone` and the file is gone.
async function refresh($, st, path, key, gone) {
  let sig
  try {
    const f = await $.fs.stat(path)
    sig = f.size + ':' + f.mtimeMs
  } catch {
    if (gone) st[key] = null
    delete st.seen[path]
    return
  }
  if (st.seen[path] === sig) return
  st.seen[path] = sig
  let text
  try {
    text = await $.fs.read(path)
  } catch {
    return
  }
  const v = parse(text)
  if (v) st[key] = v
}

// Where this clone keeps steps.json: its git directory, also from a linked worktree
// (whose .git file names a directory with a `commondir` pointer). Null when unknown.
const norm = (p) => {
  const out = []
  for (const s of p.split('/')) {
    if (s === '..') out.pop()
    else if (s !== '' && s !== '.') out.push(s)
  }
  return '/' + out.join('/')
}
const place = (base, p) => norm(p.startsWith('/') ? p : base + '/' + p)

async function stepsPath($, root) {
  try {
    const dot = root + '/.git'
    if ((await $.fs.stat(dot)).kind === 'dir') return dot + '/vbw/steps.json'
    const m = /^gitdir:\s*(.+?)\s*$/m.exec(await $.fs.read(dot))
    if (!m) return null
    const dir = place(root, m[1])
    let common = dir
    try {
      const c = (await $.fs.read(dir + '/commondir')).trim()
      if (c) common = place(dir, c)
    } catch {
      // not a linked worktree: this is the git directory
    }
    return common + '/vbw/steps.json'
  } catch {
    return null
  }
}

// This session's folder, where Claude Code writes its workflow runs: the Claude
// config folder (as tools/resolve-claude-dir.sh finds it), the project's folder
// (its path, every other character a dash) and the session id. Null when unknown.
async function sessionDir($, root, id) {
  try {
    if (typeof id !== 'string' || !/^[A-Za-z0-9_-]+$/.test(id)) return null
    let dir = await $.env.get('CLAUDE_CONFIG_DIR')
    if (!dir) {
      const home = await $.env.get('HOME')
      if (!home) return null
      dir = (await $.fs.exists(home + '/.config/claude-code')) ? home + '/.config/claude-code' : home + '/.claude'
    }
    return dir.replace(/\/+$/, '') + '/projects/' + root.replace(/[^A-Za-z0-9]/g, '-') + '/' + id
  } catch {
    return null
  }
}

// The session cost so far, the context fill and the weekly limit: numbers, or null
// when they cannot be read (never a guess).
async function readUsage($, st) {
  try {
    const u = await $.session.usage()
    const usd = isObj(u) && isObj(u.cost) ? u.cost.usd : null
    st.cost = num(usd) ? usd : null
    const ctx = isObj(u) && isObj(u.context) ? u.context.percent : null
    const week = isObj(u) && Array.isArray(u.rateLimits) ? u.rateLimits.find((r) => isObj(r) && r.kind === 'seven_day') : null
    st.health = num(ctx) || (week && num(week.percentUsed)) ? { contextPct: num(ctx) ? ctx : null, weekPct: week && num(week.percentUsed) ? week.percentUsed : null } : null
  } catch {
    st.cost = null
    st.health = null
  }
}

// Each lease (one VBW run) with the session cost when it opened and when it closed.
function trackLeases(st) {
  const l = isObj(st.record) && isObj(st.record.lease) ? st.record.lease : null
  const key = l ? String(l.run ?? '') + '@' + String(l.started_at ?? '') : null
  const open = openLease(st)
  if (open && open.key !== key) open.costEnd = st.cost
  if (key && (!open || open.key !== key)) {
    const at = Date.parse(l.started_at)
    st.leases.push({ key, kind: String(l.kind || 'run'), startedAt: Number.isFinite(at) ? at : null, costStart: st.cost })
  }
}

// The reads panel-feed.js makes (list, stat, read and the clock), spelled here:
// Claude Code follows `$` into this file's functions only.
function reads($) {
  return {
    fs: { read: (p) => $.fs.read(p), list: (p) => $.fs.list(p), stat: (p) => $.fs.stat(p) },
    clock: { now: () => $.clock.now() },
  }
}

// The live run: the one this session launched, else (after a reload, while a lease
// is open) the newest VBW run still going in this session's folder.
async function feed($, st) {
  if (!st.sessionDir) return
  const io = reads($)
  const ended = !st.run || st.run.status !== 'running'
  if ((!st.runRef || ended) && isObj(st.record) && isObj(st.record.lease)) {
    const found = await findRun(io, st.finder, st.sessionDir)
    const kind = found && kindOf(found.kind)
    if (kind && (!st.runRef || found.runId !== st.runRef.runId)) st.runRef = { runId: found.runId, kind }
  }
  if (st.runRef) st.run = await gatherRun(io, st.feed, { sessionDir: st.sessionDir, ...st.runRef })
  // Each crew this session saw, for Wrapped's agent count.
  if (isObj(st.run) && typeof st.run.runId === 'string' && Array.isArray(st.run.agents)) {
    st.crews[st.run.runId] = { startedAt: st.run.startedAt, agents: st.run.agents.map((a) => (isObj(a) ? a.id : null)) }
  }
}

// The runs this session saw, for Wrapped: each lease with what it cost (an open one
// up to now), each workflow crew with its agents.
const runsSeen = (st) => [
  ...st.leases.map((l) => {
    const end = l.costEnd === undefined ? st.cost : l.costEnd
    return { startedAt: l.startedAt, cost: num(l.costStart) && num(end) ? end - l.costStart : null }
  }),
  ...Object.values(st.crews),
]

// What a change of the record earns (panel-candy.js): a phase passing QA, confetti
// in the band (full motion); all checks green, the sweep over Proof (full) and a
// line in the band (full and calm); a ship, the pane on VBW Wrapped (any motion:
// it is information). The first snapshot is not news.
async function celebrate($, st, now) {
  const before = st.lastRec
  if (before === st.record) return
  st.lastRec = st.record
  const c = celebration({ before, after: st.record })
  const m = motion(st)
  if (c === 'qa-pass' && m === 'full') st.burst = effect('vbw-confetti', now, (w) => confettiFrames({ cols: w, rows: 3, seed: now }))
  if (c === 'all-green' && m !== 'off') st.cheer = { text: '✓ All checks pass', until: now + CHEER_MS }
  if (c === 'all-green' && m === 'full') st.sweep = effect('vbw-sweep', now, (w) => sweepFrames({ cols: w }))
  if (c === 'shipped') {
    st.wrapped = wrappedModel({ record: st.record, runs: runsSeen(st), steps: st.steps })
    if (st.wrapped) {
      st.tab = 'wrapped'
      await open($)
    }
  }
}

// Repaint by blit (no redraw): the crew's sprites while the run works and the band
// shows them, and a celebration's frames once drawn; the loop stops when nothing moves.
async function paint($, requestId, key, cells) {
  try {
    const r = await $.ui.blit({ requestId, key, cells })
    return !(isObj(r) && r.deny)
  } catch {
    return false
  }
}

function still(st) {
  if (st.anim && st.anim.cancel) st.anim.cancel()
  st.anim = null
}

function animate($, st) {
  if (!st.anim) st.anim = $.clock.every(FRAME_MS, () => frame($, st))
}

async function frame($, st) {
  if (st.animBusy) return
  st.animBusy = true
  try {
    const n = ++st.frameNo
    if (st.sprites && !(motion(st) === 'full' && isObj(st.run) && st.run.status === 'running')) st.sprites = null
    for (const s of st.sprites || []) {
      if (!(await paint($, st.bandId, s.key, spriteCells(s.role, s.pose, n)))) {
        st.sprites = null
        break
      }
    }
    for (const k of ['burst', 'sweep']) {
      const fx = st[k]
      if (!fx || !fx.site) continue
      fx.i++
      if (fx.i >= fx.frames.length || !(await paint($, fx.site, fx.key, fx.frames[fx.i]))) {
        st[k] = null
        $.ui.invalidate('ui.render')
      }
    }
    if (!st.sprites && !(st.burst && st.burst.site) && !(st.sweep && st.sweep.site)) still(st)
  } catch {
    still(st)
  } finally {
    st.animBusy = false
  }
}

// Everything the panel shows, read afresh: each file only when it changed, never written.
async function gather($, st) {
  const root = st.root
  await refresh($, st, root + '/.vbw/record.json', 'record')
  await refresh($, st, root + '/.vbw/runtime/next.json', 'next')
  if (st.sessionId) await refresh($, st, root + '/.vbw/runtime/auto.' + st.sessionId + '.json', 'auto', true)
  if (st.stepsPath) {
    await refresh($, st, st.stepsPath, 'history')
    st.steps = isObj(st.history) && Array.isArray(st.history.steps) ? st.history.steps : null
  }
  await readUsage($, st)
  trackLeases(st)
  await feed($, st)
}

// Play the sound once when a need appears; the same need never plays it again.
// A missing file or player is silent.
async function alert($, st, need) {
  const key = need ? need.key : null
  if (key === st.alerted) return
  st.alerted = key
  const clip = key && st.sound ? pick() : null
  if (!clip) return
  if (st.silent) {
    st.wouldPlay++
    return
  }
  try {
    await $.audio.play(clip)
  } catch {
    // no file or no player: nothing to say
  }
}

// An approve gate puts /vbw:approve in the prompt's suggestion, once; the person sends it.
async function suggest($, st) {
  const nx = st.next
  const key = isObj(nx) && nx.gate === true && nx.action === 'approve' && !(isObj(st.record) && isObj(st.record.lease)) ? 'approve' : null
  if (key === st.suggested) return
  st.suggested = key
  if (!key) return
  try {
    await $.prompt.suggest({ text: '/vbw:approve' })
  } catch {
    // no prompt box: nothing to suggest into
  }
}

const cheering = (st, now) => (st.cheer && st.cheer.until > now ? st.cheer.text : null)
const signature = (st, v, now) => JSON.stringify([v, st.sound, stage(st, now), st.run, st.auto, st.leases.length, st.tab, st.phase, st.check, st.agent, st.collapsed,
  cheering(st, now), !!st.burst, !!st.sweep])

// Remember when each agent first showed; at full motion a new row flashes for a
// second, and one short timer redraws the band when the flash is over.
async function noteBorn($, st, now) {
  const fresh = (isObj(st.run) && Array.isArray(st.run.agents) ? st.run.agents : []).filter((a) => isObj(a) && typeof a.id === 'string' && a.id && !(a.id in st.born))
  for (const a of fresh) st.born[a.id] = now
  if (fresh.length && motion(st) === 'full') $.clock.after(1050, () => redrawIfChanged($, st).catch(() => {}))
}

async function redrawIfChanged($, st, force) {
  const now = await $.clock.now()
  await noteBorn($, st, now)
  const v = view(st, now)
  await alert($, st, v.need)
  await suggest($, st)
  // A card put off with Later stays off only while that gate stands.
  if (st.collapsed) {
    const m = stage(st, now)
    if (!m || m.key !== st.collapsed) st.collapsed = null
  }
  const sig = signature(st, v, now)
  if (sig === st.shown && !force) return
  st.shown = sig
  $.ui.invalidate('ui.render') // Claude Code drops a redraw that names nothing
}

async function tick($, st) {
  if (st.busy) return
  st.busy = true
  try {
    await gather($, st)
    const now = await $.clock.now()
    await celebrate($, st, now)
    for (const k of ['burst', 'sweep']) if (st[k] && !st[k].site && now - st[k].at > AFTER_MS) st[k] = null
    await redrawIfChanged($, st)
  } catch {
    // keep the last good state
  } finally {
    st.busy = false
  }
}

// Switch the sound and keep the choice in the user's store; the panel redraws.
async function setSound($, st, on) {
  st.sound = on
  try {
    await $.store.set(st.keys.sound, on)
  } catch {
    // the choice holds for this session
  }
  try {
    await redrawIfChanged($, st)
  } catch {
    // the next tick draws it
  }
}

// A quarter of the terminal, never under 40 columns (R82).
const quarter = (terminal) => Math.max(40, Math.round(terminal / 4))
const cols = (n) => typeof n === 'number' && Number.isFinite(n) && n > 0

// Once a session, on the first drawing as a dock, ask for a quarter of the terminal
// unless the pane already has it. The terminal is the conversation beside the pane
// plus the pane plus 1 (Claude Code 2.1.291). A width the user dragged is kept by
// Claude Code, which ignores this request; it is never asked again nor stored.
async function size($, st, e) {
  if (st.sized || !isObj(e.props) || e.props.placement !== 'dock') return
  const beside = isObj(e.viewport) ? e.viewport.columns : null
  const pane = e.props.bodyColumns
  if (!cols(beside) || !cols(pane)) return
  st.sized = true
  const want = quarter(beside + pane + 1)
  if (pane !== want) await open($, { columns: want })
}

async function open($, extra) {
  try {
    await $.ui.open({ id: PANE, title: 'VBW', ...extra })
  } catch {
    // where Claude Code keeps the pane closed, it stays closed
  }
}

// The person opened it: remembered, so later sessions open it by themselves.
async function openByPerson($, st, extra) {
  try {
    await $.store.set(st.keys.closed, false)
  } catch {
    // the panel still opens
  }
  await open($, extra)
}

// What a press asks for (panel-stage.js and the Mission Control views): fill the
// prompt (never send it, decision Q1), open Mission Control on a tab, collapse the
// gate card, or choose what a tab shows. Anything else is ignored.
async function act($, st, a) {
  try {
    if (!isObj(a)) return
    if (typeof a.fill === 'string') {
      await $.prompt.fill({ text: a.fill })
      return
    }
    if (a.collapse === true) {
      const m = stage(st, await $.clock.now())
      st.collapsed = m && m.key ? m.key : null
    } else if (a.open === 'mission') {
      st.tab = typeof a.tab === 'string' ? a.tab : 'now'
      if (typeof a.agent === 'string') st.agent = a.agent
      await openByPerson($, st, { focus: true })
    } else if (typeof a.select === 'string') st.agent = st.agent === a.select ? null : a.select
    else if (a.tab === 'plan' && typeof a.phase === 'string') st.phase = a.phase
    else if (typeof a.check === 'string') st.check = st.check === a.check ? null : a.check
    else if (typeof a.show === 'string') st.tab = a.show
    else return
    await redrawIfChanged($, st, true)
  } catch {
    // the press does nothing
  }
}

// /vbw-todo: the text (or the selection) parked by the kernel's `vbw todo add`.
async function todo($, st, args) {
  let selection = null
  if (!String(args ?? '').trim()) {
    try {
      selection = await $.ui.selection()
    } catch {
      // no selection to take
    }
  }
  const t = todoArgs({ args, selection })
  if (!t.argv) return t.message
  try {
    const r = await $.process.run([$.plugin.root + '/bin/vbw', ...t.argv], { cwd: st.root })
    const out = String((r.exitCode === 0 ? r.stdout : r.stderr || r.stdout) || '').trim()
    return out || (r.exitCode === 0 ? 'Parked.' : 'vbw todo failed (exit ' + r.exitCode + ').')
  } catch {
    return 'VBW could not run vbw todo here.'
  }
}

// What the instant commands read: the gathered state, never a fresh turn.
async function facts($, st) {
  let now = Date.now()
  try {
    now = await $.clock.now()
  } catch {
    // the machine's clock will do
  }
  return { record: st.record, next: st.next, now, sessionId: st.sessionId }
}

const COMMANDS = [
  ['vbw-panel', 'Open the VBW panel'],
  ['vbw-sound', "Turn the 'needs you' sound on or off"],
  ['vbw-status', 'VBW status, at once and free'],
  ['vbw-why', 'Who holds the VBW run, since when, and what blocks it'],
  ['vbw-todo', 'Park an idea for later (vbw todo)'],
]

// Answer a drawing from what a site says (panel-sites.js): null draws the engine's;
// { props } the engine's, rewritten; { tree } that tree; { text, dim } one line in
// the row's place; { line, below } one VBW line above (or below) the engine's own,
// which stays in the tree exactly once.
async function answer($, e, next, out) {
  if (!isObj(out)) return next(e)
  if (out.props) return next({ ...e, props: { ...e.props, ...out.props } })
  if (out.tree) return out.tree
  let ui
  try {
    ui = $.ui.resolve(e)
  } catch {
    return next(e)
  }
  if (out.text) return h(ui.Text, { dimColor: out.dim, wrap: 'truncate-end' }, out.text)
  const line = h(ui.Text, { key: 'vbw-line', dimColor: true, wrap: 'truncate-end' }, out.line)
  const engine = await next(e)
  return h(ui.Box, { flexDirection: 'column' }, ...(out.below ? [engine, line] : [line, engine]))
}

// A site's drawing: nothing of VBW outside a VBW project or on any error.
async function draw($, st, e, next) {
  if (!st.live) return next(e)
  let out = null
  try {
    if (e.component === 'AbovePrompt') out = st.band ? await band($, st, e) : null
    else {
      if (e.component === 'TurnDuration' && turnPending(st, e)) await refresh($, st, st.root + '/.vbw/record.json', 'record')
      out = SITES[e.component](st, e, await $.clock.now())
    }
  } catch {
    out = null
  }
  return answer($, e, next, out)
}

// The Stage (panel-stage.js): the crew while a run works, the gate card when VBW
// needs the person; yields to a survey and to a card the person put off (Later).
// Above it, a celebration: the all-green line and the confetti burst. The sprites
// and the confetti drawn here are what the frame loop blits.
async function band($, st, e) {
  const p = isObj(e.props) ? e.props : {}
  st.sprites = null
  if (p.hasSurvey) return null
  const now = await $.clock.now()
  const ui = $.ui.resolve(e)
  const m = stage(st, now, p)
  const tree = m && !(m.key && m.key === st.collapsed) ? renderStage(ui, m, (a) => act($, st, a)) : null
  st.bandId = e.requestId
  if (tree && m.sprites && ui.Raster) st.sprites = m.rows.map((r) => ({ key: 'vbw-sprite-' + r.id, role: r.role, pose: r.pose }))
  const top = []
  const cheer = cheering(st, now)
  if (cheer) top.push(h(ui.Text, { key: 'vbw-cheer', color: stateColor('done'), wrap: 'truncate-end' }, cheer))
  const fx = st.burst
  const cells = fx && ui.Raster ? drawn(fx, cols(p.bodyColumns) ? p.bodyColumns : 80, e.requestId) : null
  if (cells) top.push(h(ui.Raster, { key: fx.key, columns: fx.cols, rows: fx.rows, cells }))
  if (st.sprites || cells) animate($, st)
  if (!top.length) return tree ? { tree } : null
  return { tree: h(ui.Box, { flexDirection: 'column' }, ...top, ...(tree ? [tree] : [])) }
}

// Start the panel once the session's folder is a VBW project: at session start,
// and again on a prompt, a question or a workflow while it is not (a first
// session's /vbw:vibe sets the project up mid-session). No timer before that.
async function begin($, st) {
  if (st.live || st.unsupported === true) return
  if (st.unsupported !== false) {
    const ver = await $.session.version()
    const v = isObj(ver) ? ver.version : ver
    st.unsupported = !supports(v)
    if (st.unsupported) return
    st.band = supports(v, BAND_MIN_VERSION)
  }
  const root = await $.session.root()
  if (typeof root !== 'string' || !(await $.fs.exists(root + '/.vbw/record.json'))) return
  st.live = true
  st.root = root
  st.silent = await $.fs.exists(root + TEST_MARK)
  st.keys = keys(st.silent)
  st.stepsPath = await stepsPath($, root)
  try {
    st.sessionId = await $.session.id()
  } catch {
    st.sessionId = null
  }
  st.sessionDir = await sessionDir($, root, st.sessionId)
  await gather($, st)
  st.lastRec = st.record
  st.sound = (await $.store.get(st.keys.sound)) !== false
  const now = await $.clock.now()
  const v0 = view(st, now)
  st.alerted = v0.need ? v0.need.key : null // a need already standing at start is not announced
  await suggest($, st)
  st.shown = signature(st, v0, now)
  if (st.timer && st.timer.cancel) st.timer.cancel()
  st.timer = $.clock.every(TICK_MS, () => tick($, st))
  for (const [name, description] of COMMANDS) $.command.register({ name, description, immediate: true })
  if ((await $.store.get(st.keys.closed)) !== true) await open($)
}
async function wake($, st) {
  try {
    await begin($, st)
  } catch {
    // the panel stays out of the way
  }
}

export function register(on) {
  const st = fresh()

  on('session.start', async ($, e, next) => {
    const out = await next(e)
    await wake($, st)
    return out
  })

  on('command.run', { command: 'vbw-panel' }, async ($, e, next) => {
    if (!st.live) return next(e)
    const w = isObj(e) && isObj(e.presentation) ? e.presentation.columns : null
    await openByPerson($, st, cols(w) ? { columns: quarter(w), focus: true } : { focus: true })
    return { text: 'The VBW panel is open.' }
  })

  on('command.run', { command: 'vbw-sound' }, async ($, e, next) => {
    if (!st.live) return next(e)
    const word = String(e.args ?? '').trim().toLowerCase()
    if (word === '' || word === 'on' || word === 'off') await setSound($, st, word === '' ? !st.sound : word === 'on')
    return { text: "The 'needs you' sound is " + (st.sound ? 'on' : 'off') + '.' }
  })

  on('command.run', { command: 'vbw-status' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: statusText(await facts($, st)) }
  })

  on('command.run', { command: 'vbw-why' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: whyText(await facts($, st)) }
  })

  on('command.run', { command: 'vbw-todo' }, async ($, e, next) => {
    if (!st.live) return next(e)
    return { text: await todo($, st, e.args) }
  })

  // Remember a close made by the user only; every close is passed on.
  on('ui.close', async ($, e, next) => {
    if (st.live && isObj(e) && e.id === PANE && isObj(e.origin) && e.origin.kind === 'person') {
      try {
        await $.store.set(st.keys.closed, true)
      } catch {
        // the close still goes through
      }
    }
    return next(e)
  })

  // A question to the user is a need while it is open.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (!st.live) await wake($, st)
    if (!st.live) return next(e)
    st.question = { id: String(Date.now()) + Math.random() }
    try {
      await redrawIfChanged($, st)
    } catch {
      // the next tick draws it
    }
    try {
      return await next(e)
    } finally {
      st.question = null
      try {
        await redrawIfChanged($, st)
      } catch {
        // nothing to redraw
      }
    }
  })

  // A VBW workflow launched by this session (main loop): its run id and folder
  // come back in the launch's result; the timer reads the run from there.
  on('tool.call', { tool: 'Workflow' }, async ($, e, next) => {
    if (!st.live) await wake($, st)
    const out = await next(e)
    try {
      const r = isObj(out) && isObj(out.result) ? out.result : null
      const kind = kindOf(e.name)
      if (!st.live || e.agentId || !r || !kind || typeof r.runId !== 'string' || !/^wf_[A-Za-z0-9_-]+$/.test(r.runId)) return out
      const m = typeof r.transcriptDir === 'string' ? /^(\/.+)\/subagents\/workflows\/[^/]+\/?$/.exec(r.transcriptDir) : null
      if (m) st.sessionDir = m[1]
      st.runRef = { runId: r.runId, kind }
      st.run = null
      if (typeof e.tool_use_id === 'string') st.toolRuns[e.tool_use_id] = r.runId
    } catch {
      // the run is found by its lease instead
    }
    return out
  })

  // The record as a turn found it: the turn receipt says what moved.
  on('prompt.submit', async ($, e, next) => {
    if (!st.live) await wake($, st)
    if (st.live) st.before = st.record
    return next(e)
  })

  // Mission Control: drawn as Claude Code's own pane example does, from $.ui.resolve(e)
  // and h(). Only this pane's drawings reach here.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (!st.live) return next(e)
    try {
      await size($, st, e)
    } catch {
      // the width stays as Claude Code placed it
    }
    try {
      const now = await $.clock.now()
      const v = view(st, now)
      const width = isObj(e.props) && cols(e.props.bodyColumns) ? e.props.bodyColumns : 50
      const ui = $.ui.resolve(e)
      const cells = st.sweep && st.tab === 'proof' && ui.Raster ? drawn(st.sweep, width, PANE) : null
      if (cells) animate($, st)
      const sweep = cells ? { cols: st.sweep.cols, cells } : null
      return renderPane(ui, { st, v, now, width, sweep, wrapped: st.wrapped, scroll: isObj(e.props) ? e.props.scroll : null, portrait: $.plugin.root + '/assets/portrait.png' }, {
        act: (a) => act($, st, a),
        sound: () => setSound($, st, !st.sound),
      })
    } catch {
      return next(e)
    }
  })

  // Every other place VBW draws, each hook matched to its site (render from memory).
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'Spinner' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'InfoNotice' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Workflow' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'ToolUse', props: { tool: 'Bash' } }, async ($, e, next) => draw($, st, e, next))
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, async ($, e, next) => draw($, st, e, next))
}
