// Mission Control's record tabs (mods_4_vbw.md §3.3): Plan, Proof, Decisions
// and Team. Each tab is a pure `xxxModel(input)` over the project record and a
// `renderXxx(ui, model, act)` drawn with the global h(); `act(action)` receives
// what a press asks for ({tab, phase}, {check}, {ask}, {fill}). Never throws:
// odd input gives an empty model. No `$` here.

import { roleColor, stateColor } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const arr = (x) => (Array.isArray(x) ? x.filter(isObj) : [])
const str = (x) => (typeof x === 'string' && x !== '' ? x : null)
const recOf = (input) => (isObj(input) && isObj(input.record) ? input.record : {})
const msId = (rec) => (isObj(rec.milestone) ? str(rec.milestone.id) : null)

// An argv as a shell would read it: words with anything unusual single-quoted.
export function argvText(argv) {
  if (!Array.isArray(argv)) return ''
  return argv.map((a) => {
    const s = String(a)
    return /^[\w@%+=:,./-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'"
  }).join(' ')
}

function scope(rec) {
  const id = msId(rec)
  const reqs = arr(rec.requirements).filter((r) => id && r.milestone === id)
  const reqIds = new Set(reqs.map((r) => r.id))
  return {
    id,
    reqs,
    phases: arr(rec.phases).filter((p) => id && p.milestone === id && str(p.id)),
    checks: arr(rec.checks).filter((c) => str(c.id) && reqIds.has(c.req)),
  }
}
const reqText = (rec, id) => {
  const r = arr(rec.requirements).find((x) => x.id === id)
  return r && str(r.text) ? id + ': ' + r.text : String(id ?? '')
}

// ---- Plan -------------------------------------------------------------------

export function planModel(input) {
  const rec = recOf(input)
  const want = isObj(input) ? input.phase : null
  const { phases } = scope(rec)
  const plans = arr(rec.plans)
  const pick = phases.find((p) => p.id === want)
    || phases.find((p) => !(isObj(p.qa) && p.qa.result === 'pass'))
    || phases[phases.length - 1] || null
  const tabs = phases.map((p) => ({
    id: p.id, title: str(p.title) || '', active: !!pick && p.id === pick.id, press: { tab: 'plan', phase: p.id },
  }))
  let selected = null
  if (pick) {
    const reqs = new Set(Array.isArray(pick.reqs) ? pick.reqs : [])
    selected = {
      id: pick.id,
      title: str(pick.title) || '',
      goal: str(pick.goal),
      plans: plans.filter((p) => p.phase === pick.id).map((p) => ({
        id: String(p.id ?? ''), title: str(p.title) || '', status: str(p.status) || 'planned',
        files: Array.isArray(p.files) ? p.files.filter((f) => typeof f === 'string') : [],
      })),
      checks: arr(rec.checks).filter((c) => str(c.id) && reqs.has(c.req))
        .map((c) => ({ id: c.id, req: c.req, command: argvText(c.run) })),
    }
  }
  return { milestone: scope(rec).id, tabs, selected, ask: { ask: true, placeholder: 'Ask about this plan' } }
}

// ---- Proof ------------------------------------------------------------------

const TAIL_LINES = 20
const CELL = {
  passed: stateColor('done'), failing: stateColor('failed'), running: stateColor('running'), none: stateColor('quiet'),
}

export function checkDetail(record, id) {
  const rec = isObj(record) ? record : {}
  const c = arr(rec.checks).find((x) => x.id === id && str(x.id))
  if (!c) return null
  const ev = isObj(rec.evidence) && isObj(rec.evidence.checks) && isObj(rec.evidence.checks[id]) ? rec.evidence.checks[id] : {}
  const tail = typeof ev.tail === 'string' ? ev.tail.replace(/\n+$/, '').split('\n').slice(-TAIL_LINES).join('\n') : ''
  return {
    id,
    command: argvText(c.run),
    requirement: reqText(rec, c.req),
    status: str(ev.status),
    exit: Number.isInteger(ev.exit) ? ev.exit : null,
    seconds: Number.isFinite(ev.seconds) ? ev.seconds : null,
    at: isObj(rec.evidence) ? str(rec.evidence.at) : null,
    output: tail,
  }
}

export function proofModel(input) {
  const rec = recOf(input)
  const running = new Set(isObj(input) && Array.isArray(input.running) ? input.running : [])
  const { checks, reqs } = scope(rec)
  const proven = new Set(reqs.filter((r) => r.status === 'proven').map((r) => r.id))
  // With no evidence at all, a proven requirement still says its checks passed;
  // a check the last proof did not run is not run.
  const evc = isObj(rec.evidence) && isObj(rec.evidence.checks) ? rec.evidence.checks : null
  if (evc) proven.clear()
  const counts = { passed: 0, failing: 0, running: 0, none: 0 }
  const cells = checks.map((c) => {
    const st = evc && isObj(evc[c.id]) ? evc[c.id].status : null
    const state = running.has(c.id) ? 'running'
      : st === 'pass' ? 'passed'
      : st === 'fail' || st === 'timeout' ? 'failing'
      : !st && proven.has(c.req) ? 'passed' : 'none'
    counts[state]++
    return { id: c.id, state, color: CELL[state], hover: c.id + ' · ' + reqText(rec, c.req), press: { check: c.id } }
  })
  const sel = isObj(input) ? input.selected : null
  return { cells, counts, detail: sel ? checkDetail(rec, sel) : null }
}

// ---- Decisions ----------------------------------------------------------------

// Decisions carry no milestone: the current milestone's are those made after
// the previous milestone shipped (and, once it shipped, not after its own ship).
export function decisionsModel(input) {
  const rec = recOf(input)
  const id = msId(rec)
  const shipped = arr(rec.shipped).filter((s) => str(s.at))
  const own = shipped.find((s) => s.id === id)
  const before = shipped.filter((s) => s.id !== id).map((s) => s.at).sort()
  const from = before.length ? before[before.length - 1] : null
  const to = own ? own.at : null
  const items = !id ? [] : arr(rec.decisions)
    .filter((d) => str(d.text) && str(d.at) && (!from || d.at > from) && (!to || d.at <= to))
    .map((d, i) => {
      const q = /^(.+?\?)\s+(\S[\s\S]*)$/.exec(d.text)
      return {
        id: String(d.id ?? ''), question: q ? q[1] : null, answer: q ? q[2] : d.text,
        why: str(d.why), at: d.at, n: i,
      }
    })
    .sort((a, b) => (a.at === b.at ? b.n - a.n : a.at < b.at ? 1 : -1))
    .map(({ n, ...d }) => d)
  return { milestone: id, items }
}

// ---- Team -------------------------------------------------------------------

export const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
// plugin/lib/profiles.json (a test holds the two equal).
const S = 'sonnet'
const PROFILES = {
  quality: { architect: 'opus', lead: 'opus', dev: 'opus', qa: S, scout: S, debugger: 'opus', docs: S },
  balanced: { architect: S, lead: S, dev: S, qa: S, scout: S, debugger: S, docs: S },
  budget: { architect: S, lead: S, dev: S, qa: S, scout: 'haiku', debugger: S, docs: S },
}
const RENAMED = { planner: 'lead', critic: 'qa', builder: 'dev' }
const pickOf = (v, ok, dflt) => (ok.includes(v) ? v : dflt)

export function teamModel(input) {
  const rec = recOf(input)
  const cfg = isObj(input) && isObj(input.config) ? input.config : {}
  const set = { ...(isObj(rec.settings) ? rec.settings : {}), ...cfg }
  const profile = pickOf(set.profile, Object.keys(PROFILES), 'balanced')
  const over = {}
  for (const [k, v] of Object.entries(isObj(set.models) ? set.models : {})) {
    const role = RENAMED[k] || k
    if (ROLES.includes(role) && str(v) && (!(k in RENAMED) || !over[role])) over[role] = v
  }
  const rows = ROLES.map((role) => {
    let model = over[role] || PROFILES[profile][role]
    if (role === 'qa' && /haiku/i.test(model)) model = S
    return { role, model, override: !!over[role] && model === over[role], color: roleColor(role) }
  })
  return {
    profile,
    autonomy: pickOf(set.autonomy, ['guided', 'balanced', 'hands-off'], 'balanced'),
    rigor: pickOf(set.rigor, ['auto', 'express', 'standard', 'deep'], 'auto'),
    cap: Number.isInteger(set.autonomy_cap) ? set.autonomy_cap : 25,
    rows,
    buttons: [{ label: 'Models', fill: '/vbw:config' }, { label: 'Autonomy', fill: '/vbw:profile' }],
  }
}

// ---- Rendering ----------------------------------------------------------------

const call = (act, a) => () => { if (typeof act === 'function') act(a) }
const els = (ui) => (isObj(ui) ? ui : {})
const T = (ui, props, ...s) => h(els(ui).Text, props, ...s)
const col = (ui, props, ...kids) => h(els(ui).Box, { flexDirection: 'column', ...props }, ...kids)
const row = (ui, props, ...kids) => h(els(ui).Box, { flexDirection: 'row', ...props }, ...kids)
const btn = (ui, key, label, act, a, extra) => h(els(ui).Button, { key, label, onPress: call(act, a), ...extra })
const empty = (ui, text) => col(ui, null, T(ui, { dimColor: true }, text))
// Code or Markdown when the surface has them, else the same words as Text.
const code = (ui, source, language) => (els(ui).Code ? h(ui.Code, { source, ...(language ? { language } : {}), wrap: 'truncate-end' }) : T(ui, null, source))
const md = (ui, text) => (els(ui).Markdown ? h(ui.Markdown, { text }) : T(ui, null, text))

export function renderPlan(ui, model, act) {
  const m = isObj(model) ? model : {}
  if (!Array.isArray(m.tabs) || !m.tabs.length) return empty(ui, 'No phases are planned yet.')
  const tabs = row(ui, { key: 'plan-tabs', flexWrap: 'wrap' }, ...m.tabs.map((t) =>
    btn(ui, 'plan-' + t.id, t.id + (t.title ? ' ' + t.title : ''), act, t.press, t.active ? { variant: 'primary' } : { dimColor: true })))
  const s = m.selected
  if (!isObj(s)) return col(ui, null, tabs)
  const kids = [tabs, T(ui, { bold: true }, s.id + ' ' + s.title)]
  if (s.goal) kids.push(md(ui, s.goal))
  kids.push(T(ui, { dimColor: true }, 'Plans'))
  for (const p of s.plans) {
    kids.push(T(ui, null, p.id + ' ' + p.title + ' · ' + p.status))
    for (const f of p.files) kids.push(T(ui, { dimColor: true }, '  ' + f))
  }
  kids.push(T(ui, { dimColor: true }, 'Checks'))
  for (const c of s.checks) kids.push(T(ui, null, c.id + ' · ' + c.req), code(ui, c.command, 'bash'))
  if (els(ui).Input && isObj(m.ask)) {
    kids.push(h(ui.Input, { key: 'plan-ask', placeholder: m.ask.placeholder, submitLabel: 'ask', onSubmit: (v) => call(act, { ask: String(v) })() }))
  }
  return col(ui, null, ...kids)
}

export const PER_ROW = 20

export function renderProof(ui, model, act) {
  const m = isObj(model) ? model : {}
  const cells = Array.isArray(m.cells) ? m.cells : []
  if (!cells.length) return empty(ui, 'No checks are approved for this milestone yet.')
  const cell = (c) => h(els(ui).Box, { key: 'cell-' + c.id },
    T(ui, { color: c.color }, '■'),
    h(els(ui).Box, { position: 'absolute', top: 1, left: 0, display: 'none', hover: { display: 'flex' }, borderStyle: 'round' },
      T(ui, null, c.hover)))
  const rows = []
  for (let i = 0; i < cells.length; i += PER_ROW) {
    rows.push(row(ui, { key: 'proof-row-' + i / PER_ROW }, ...cells.slice(i, i + PER_ROW).map(cell)))
  }
  const k = isObj(m.counts) ? m.counts : {}
  const kids = [...rows, T(ui, { dimColor: true },
    (k.passed || 0) + ' passed · ' + (k.failing || 0) + ' failing · ' + (k.running || 0) + ' running · ' + (k.none || 0) + ' not run')]
  // Every check is a press away: the failing ones first, as the ones worth reading.
  const order = [...cells.filter((c) => c.state === 'failing'), ...cells.filter((c) => c.state !== 'failing')]
  kids.push(row(ui, { key: 'proof-press', flexWrap: 'wrap' }, ...order.map((c) =>
    btn(ui, 'check-' + c.id, c.id, act, c.press, { plain: true, dimColor: c.state !== 'failing' }))))
  const d = m.detail
  if (isObj(d)) {
    kids.push(T(ui, { bold: true }, d.id + ' · ' + d.requirement),
      T(ui, { dimColor: true }, d.status ? 'last run: ' + d.status + (d.exit !== null ? ' (exit ' + d.exit + ')' : '') : 'not run yet'),
      code(ui, d.command, 'bash'))
    if (d.output) kids.push(code(ui, d.output))
  }
  return col(ui, null, ...kids)
}

export function renderDecisions(ui, model) {
  const items = isObj(model) && Array.isArray(model.items) ? model.items : []
  if (!items.length) return empty(ui, 'No decisions recorded for this milestone yet.')
  return col(ui, null, ...items.map((d) => col(ui, { key: 'decision-' + d.id, marginBottom: 1 },
    T(ui, { dimColor: true }, d.id + (d.question ? ' · ' + d.question : '')),
    T(ui, null, d.answer),
    d.why ? T(ui, { dimColor: true }, 'because ' + d.why) : null)))
}

export function renderTeam(ui, model, act) {
  const m = isObj(model) ? model : {}
  const rows = Array.isArray(m.rows) ? m.rows : []
  if (!rows.length) return empty(ui, 'No team settings to show.')
  const width = Math.max(...rows.map((r) => r.role.length)) + 2
  return col(ui, null,
    ...rows.map((r) => row(ui, { key: 'team-' + r.role },
      T(ui, { color: r.color }, r.role.padEnd(width)),
      T(ui, null, r.model),
      r.override ? T(ui, { dimColor: true }, ' (set by you)') : null)),
    T(ui, null, 'Profile: ' + m.profile + ' · autonomy: ' + m.autonomy + ' (' + m.cap + ' steps) · rigor: ' + m.rigor),
    row(ui, { key: 'team-buttons' }, ...(Array.isArray(m.buttons) ? m.buttons : []).map((b) =>
      btn(ui, 'team-' + b.fill, b.label, act, { fill: b.fill }))))
}
