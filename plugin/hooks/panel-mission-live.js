// Mission Control's live tabs (mods_4_vbw.md §3.3): Now (the workflow as phase
// columns of agent cards), Timeline (agent lanes on the run clock, past steps as
// a sparkline against the R58 median) and Costs (cost per run, "about"). Pure:
// the run model in, plain models out, trees built with h(); never throws.

import { estimate, MIN_STEPS } from './panel-estimate.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const num = (x) => typeof x === 'number' && Number.isFinite(x)
const str = (x) => (typeof x === 'string' ? x : '')
const safe = (fn) => (input) => {
  try {
    return fn(isObj(input) ? input : {})
  } catch {
    return null
  }
}

export const ROLE_COLORS = { architect: 'magenta', lead: 'blue', dev: 'green', qa: 'yellow', scout: 'cyan', debugger: 'red', docs: '#ff87d7', agent: 'white' }
const FRAMES = { done: 'green', working: 'yellow', failed: 'red', quiet: 'gray', cut: 'gray' }
// A run kind and the step kind its finished leases are recorded under (steps.json).
const STEP_KIND = { planning: 'plan', building: 'build', verifying: 'qa', fixing: 'fix', mapping: 'map' }
const BARS = '▁▂▃▄▅▆▇█'
const ACTIVITY_MAX = 40

const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s)
const roleOf = (a) => (ROLE_COLORS[a.role] ? a.role : 'agent')
const titleOf = (a) => [str(a.role) || 'agent', str(a.label)].filter(Boolean).join(' ')
const agentsOf = (run) =>
  run.agents.filter((a) => isObj(a) && typeof a.id === 'string')
    .map((a, i) => ({ a, i })).sort((x, y) => (num(x.a.startedAt) ? x.a.startedAt : 0) - (num(y.a.startedAt) ? y.a.startedAt : 0) || x.i - y.i)
    .map((x) => x.a)
const validRun = (run) => isObj(run) && Array.isArray(run.agents)

// 45 s, 3 min 12 s, 10 min.
export function duration(ms) {
  const s = Math.max(0, Math.round((num(ms) ? ms : 0) / 1000))
  if (s < 60) return s + ' s'
  const m = Math.floor(s / 60)
  return s % 60 ? m + ' min ' + (s % 60) + ' s' : m + ' min'
}

function tokens(n) {
  if (!num(n) || n < 0) return null
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M tokens'
  if (n >= 1000) return Math.round(n / 1000) + 'k tokens'
  return n + ' tokens'
}

// The state an agent shows: what was still going when the run stopped is cut off.
function stateOf(a, run) {
  const s = FRAMES[a.state] ? a.state : 'quiet'
  return run.status === 'stopped' && (s === 'working' || s === 'quiet') ? 'cut' : s
}

// The column an agent belongs to: its workflow phase, else the phase in its label (P55.1 -> P55).
function phaseOf(a) {
  if (str(a.phase)) return a.phase
  const m = /^(P\d+)/.exec(str(a.label))
  return m ? m[1] : 'Agents'
}

const phaseName = (p) => (typeof p === 'string' ? p : isObj(p) ? str(p.title) || str(p.name) : '')

export const nowModel = safe(({ run, now, selected }) => {
  if (!validRun(run)) return null
  const t = num(now) ? now : Date.now()
  const agents = agentsOf(run)
  const order = (Array.isArray(run.phases) ? run.phases : []).map(phaseName).filter(Boolean)
  for (const a of agents) if (!order.includes(phaseOf(a))) order.push(phaseOf(a))
  const card = (a) => {
    const state = stateOf(a, run)
    return {
      id: a.id, title: titleOf(a), role: roleOf(a), roleColor: ROLE_COLORS[roleOf(a)], state, frame: FRAMES[state],
      activity: isObj(a.activity) && str(a.activity.text) ? clip(a.activity.text, ACTIVITY_MAX) : null,
      tokens: tokens(a.tokens), selected: a.id === selected, action: { select: a.id },
    }
  }
  const columns = order
    .map((title) => ({ title, cards: agents.filter((a) => phaseOf(a) === title).map(card) }))
    .filter((c) => c.cards.length)
  const sel = agents.find((a) => a.id === selected)
  const detail = sel ? {
    id: sel.id, label: titleOf(sel), role: roleOf(sel), model: str(sel.model) || null,
    activity: isObj(sel.activity) && str(sel.activity.text) ? sel.activity.text : null,
    result: str(sel.result) || null,
    elapsed: num(sel.startedAt) ? duration((num(sel.endedAt) ? sel.endedAt : t) - sel.startedAt) : null,
  } : null
  const end = num(run.endedAt) ? run.endedAt : t
  const header = { kind: str(run.kind) || 'run', status: str(run.status) || 'running', elapsed: num(run.startedAt) ? duration(end - run.startedAt) : null }
  return { header, columns, detail }
})

// Past steps of this run's kind as bars, the median (R58, via estimate) and the bar nearest it.
function sparkOf(steps, kind, now) {
  const secs = steps.filter((s) => isObj(s) && s.kind === kind && num(s.seconds) && s.seconds > 0).slice(-20).map((s) => s.seconds)
  if (!secs.length) return null
  const lo = Math.min(...secs)
  const hi = Math.max(...secs)
  const bars = secs.map((s) => BARS[hi === lo ? 3 : Math.round(((s - lo) / (hi - lo)) * 7)]).join('')
  let median = null
  let mark = null
  if (secs.length >= MIN_STEPS) {
    const e = estimate({ steps, lease: { kind, started_at: new Date(now).toISOString() }, now })
    median = e.step && e.step.state === 'approx' ? e.step.seconds : null
  }
  if (median !== null) {
    mark = 0
    secs.forEach((s, i) => { if (Math.abs(s - median) < Math.abs(secs[mark] - median)) mark = i })
  }
  return { bars, median, mark, kind }
}

function leftOf(run, steps, kind, now) {
  if (num(run.endedAt) || !num(run.startedAt)) return null
  const e = estimate({ steps, lease: { kind, started_at: new Date(run.startedAt).toISOString() }, now })
  if (!e.step || e.step.state === 'none') return null
  return e.step.state === 'longer' ? 'taking longer than usual' : 'about ' + Math.max(1, Math.round(e.step.seconds / 60)) + ' min left'
}

export const timelineModel = safe(({ run, now, steps, width }) => {
  if (!validRun(run)) return null
  const t = num(now) ? now : Date.now()
  const w = num(width) ? Math.max(10, Math.floor(width)) : 40
  const start = num(run.startedAt) ? run.startedAt : t
  const end = num(run.endedAt) ? run.endedAt : t
  const span = Math.max(1, end - start)
  const col = (ms) => Math.min(w, Math.max(0, ((ms - start) / span) * w))
  const lanes = agentsOf(run).map((a) => {
    const a0 = num(a.startedAt) ? a.startedAt : start
    const a1 = num(a.endedAt) ? a.endedAt : end
    const from = Math.min(w - 1, Math.floor(col(a0)))
    return {
      id: a.id, name: titleOf(a), role: roleOf(a), color: ROLE_COLORS[roleOf(a)], state: stateOf(a, run),
      from, to: Math.max(from + 1, Math.ceil(col(a1))), seconds: Math.max(0, Math.round((a1 - a0) / 1000)), slow: false,
    }
  })
  if (lanes.length > 3) {
    const slow = new Set(lanes.slice().sort((x, y) => y.seconds - x.seconds).slice(0, 3).map((l) => l.id))
    for (const l of lanes) l.slow = slow.has(l.id)
  }
  const history = Array.isArray(steps) ? steps : []
  const kind = STEP_KIND[run.kind] || str(run.kind)
  return { width: w, lanes, spark: sparkOf(history, kind, t), left: leftOf(run, history, kind, t) }
})

const cents = (x) => Math.round(x * 1e4) / 1e4
const usd = (x) => '$' + x.toFixed(2)

// runs: [{kind, startedAt, costStart, costEnd}]; a run still open costs up to the session cost now.
export const costsModel = safe(({ runs, sessionCost, width }) => {
  const w = num(width) ? Math.max(1, Math.floor(width)) : 30
  const session = num(sessionCost) ? sessionCost : null
  const seen = {}
  const rows = (Array.isArray(runs) ? runs : []).flatMap((r) => {
    if (!isObj(r) || !str(r.kind) || !num(r.costStart)) return []
    const endCost = num(r.costEnd) ? r.costEnd : session
    if (endCost === null || endCost < r.costStart) return []
    seen[r.kind] = (seen[r.kind] || 0) + 1
    const cost = cents(endCost - r.costStart)
    return [{ kind: r.kind, name: r.kind + ' ' + seen[r.kind], startedAt: num(r.startedAt) ? r.startedAt : null, cost, text: 'about ' + usd(cost), bar: 0 }]
  })
  const max = Math.max(0, ...rows.map((r) => r.cost))
  for (const r of rows) r.bar = max > 0 && r.cost > 0 ? Math.max(1, Math.round((r.cost / max) * w)) : 0
  const kinds = []
  for (const r of rows) {
    let k = kinds.find((x) => x.kind === r.kind)
    if (!k) kinds.push((k = { kind: r.kind, runs: 0, cost: 0, text: '' }))
    k.runs++
    k.cost = cents(k.cost + r.cost)
    k.text = 'about ' + usd(k.cost)
  }
  kinds.sort((x, y) => y.cost - x.cost)
  return { runs: rows, kinds, session: session === null ? 'The session cost is not available.' : 'This session: ' + usd(session), width: w }
})

// ---- Renders: ui = $.ui.resolve(e); `act` receives a card's action when it is pressed.

const NO_RUN = 'No VBW workflow runs in this session right now.'
const empty = (ui, text) => h(ui.Box, { flexDirection: 'column' }, h(ui.Text, { dimColor: true }, text))

export function renderNow(ui, model, act) {
  if (!isObj(model) || !Array.isArray(model.columns)) return empty(ui, NO_RUN)
  const hd = model.header || {}
  const header = [hd.kind, hd.status, hd.elapsed].filter(Boolean).join(' · ')
  const card = (c) =>
    h(ui.Box, { key: 'card-box:' + c.id, flexDirection: 'column', borderStyle: 'round', borderColor: c.frame, paddingX: 1 },
      h(ui.Button, { key: 'card:' + c.id, label: c.title, plain: true, onPress: () => { if (typeof act === 'function') act(c.action) } }),
      c.activity ? h(ui.Text, { dimColor: true }, c.activity) : null,
      c.tokens ? h(ui.Text, { dimColor: true }, c.tokens) : null)
  const columns = model.columns.map((col) =>
    h(ui.Box, { key: 'col:' + col.title, flexDirection: 'column', marginRight: 1 },
      h(ui.Text, { bold: true }, col.title), ...col.cards.map(card)))
  const d = model.detail
  const detail = isObj(d)
    ? h(ui.Box, { flexDirection: 'column', marginTop: 1 },
      h(ui.Text, { bold: true, color: ROLE_COLORS[d.role] }, d.label),
      h(ui.Text, null, 'Model: ' + (d.model || 'not known')),
      d.elapsed ? h(ui.Text, null, 'Elapsed: ' + d.elapsed) : null,
      d.activity ? h(ui.Text, null, 'Doing: ' + d.activity) : null,
      d.result ? h(ui.Text, null, 'Result: ' + d.result) : null)
    : null
  return h(ui.Box, { flexDirection: 'column' },
    h(ui.Text, { bold: true }, header),
    columns.length ? h(ui.Box, { key: 'columns', flexDirection: 'row', flexWrap: 'wrap' }, ...columns) : h(ui.Text, { dimColor: true }, 'No agents have started yet.'),
    detail)
}

export function renderTimeline(ui, model) {
  if (!isObj(model) || !Array.isArray(model.lanes)) return empty(ui, NO_RUN)
  const nameW = Math.min(16, Math.max(4, ...model.lanes.map((l) => l.name.length)))
  const lane = (l) =>
    h(ui.Box, { key: 'lane:' + l.id, flexDirection: 'row' },
      h(ui.Text, { color: l.color }, l.name.slice(0, nameW).padEnd(nameW + 1)),
      h(ui.Text, { color: l.slow ? 'red' : l.color, bold: l.slow }, ' '.repeat(l.from) + '█'.repeat(l.to - l.from)),
      h(ui.Text, { dimColor: !l.slow }, ' ' + duration(l.seconds * 1000)))
  const sp = model.spark
  const spark = isObj(sp)
    ? h(ui.Box, { flexDirection: 'column', marginTop: 1 },
      h(ui.Text, null, sp.bars),
      sp.mark !== null ? h(ui.Text, { dimColor: true }, ' '.repeat(sp.mark) + '▲ median ' + duration(sp.median * 1000)) : null,
      h(ui.Text, { dimColor: true }, 'past ' + sp.kind + ' steps'))
    : null
  return h(ui.Box, { flexDirection: 'column' },
    ...(model.lanes.length ? model.lanes.map(lane) : [h(ui.Text, { dimColor: true }, 'No agents have started yet.')]),
    spark,
    model.left ? h(ui.Text, null, model.left) : null)
}

export function renderCosts(ui, model) {
  if (!isObj(model) || !Array.isArray(model.runs)) return empty(ui, 'No cost to show yet.')
  const nameW = Math.max(4, ...model.runs.map((r) => r.name.length))
  return h(ui.Box, { flexDirection: 'column' },
    ...(model.runs.length
      ? model.runs.map((r, i) => h(ui.Box, { key: 'cost:' + i },
        h(ui.Text, null, r.name.padEnd(nameW + 1)), h(ui.Text, { color: 'cyan' }, '█'.repeat(r.bar)), h(ui.Text, { dimColor: true }, ' ' + r.text)))
      : [h(ui.Text, { dimColor: true }, 'No VBW run has finished in this session yet.')]),
    ...model.kinds.map((k) => h(ui.Text, null, k.kind + ' (' + k.runs + (k.runs === 1 ? ' run' : ' runs') + '): ' + k.text)),
    h(ui.Text, { bold: true }, model.session))
}
