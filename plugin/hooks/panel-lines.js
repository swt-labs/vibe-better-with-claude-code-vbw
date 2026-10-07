// VBW's one-line surfaces and transcript rows (mods_4_vbw.md §2, §3.4, §3.5):
// the spinner suffix, the hint tail, the footer modes, the startup notice, the
// question header, the turn receipt, the Workflow run card, the run receipt and
// the `vbw` row intentions. Pure: data in, one string out, or null to leave the
// engine's own line. Never throws, never changes its input, no `$` here.

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const arr = (x) => (Array.isArray(x) ? x.filter(isObj) : [])
const WORKFLOWS = ['planning', 'building', 'fixing', 'verifying', 'mapping', 'researching', 'investigating', 'tooling']
const PROFILES = { quality: 'careful', balanced: 'standard', budget: 'fast' }
const GATE_COMMANDS = { approve: '/vbw:approve', accept: '/vbw:verify', convert: '/vbw:convert' }

const isProject = (rec) => isObj(rec) && isObj(rec.milestone) && typeof rec.milestone.id === 'string' && rec.milestone.id !== ''
const live = (run) => isObj(run) && run.status === 'running' && typeof run.kind === 'string' && run.kind !== ''

// 'vbw:planning' or 'planning' -> 'planning' when it is one of VBW's workflows.
function vbwKind(name, bareOk) {
  if (typeof name !== 'string') return null
  const m = /^vbw:([a-z-]+)$/.exec(name)
  const k = m ? m[1] : bareOk ? name : null
  return WORKFLOWS.includes(k) ? k : null
}

// Durations as the engine writes them: 45s, 14m, 1h 5m; seconds kept under 2 min for turns.
function dur(ms, fine) {
  if (!Number.isFinite(ms) || ms < 0) return null
  const s = Math.round(ms / 1000)
  if (s < 60) return s + 's'
  const m = Math.floor(s / 60)
  if (m < 60) return fine && m < 2 && s % 60 ? m + 'm ' + (s % 60) + 's' : m + 'm'
  return Math.floor(m / 60) + 'h' + (m % 60 ? ' ' + (m % 60) + 'm' : '')
}

const milestonePhases = (rec) => arr(rec.phases).filter((p) => p.milestone === rec.milestone.id)
const milestonePlans = (rec) => {
  const ids = new Set(milestonePhases(rec).map((p) => p.id))
  return arr(rec.plans).filter((p) => ids.has(p.phase))
}
const milestoneReqs = (rec) => arr(rec.requirements).filter((r) => r.milestone === rec.milestone.id)
const nextCommand = (nx) => (isObj(nx) && nx.gate === true && GATE_COMMANDS[nx.action]) || '/vbw:vibe'

// Spinner `suffix` (drawn in place of the engine's ellipsis) while a VBW run is live.
export function spinnerSuffix(input) {
  const { run, record: rec } = isObj(input) ? input : {}
  if (!live(run)) return null
  if (run.kind === 'building' && isObj(rec)) {
    const plan = arr(rec.plans).find((p) => p.status === 'building')
    if (plan) {
      const mine = arr(rec.plans).filter((p) => p.phase === plan.phase)
      const at = mine.filter((p) => p.status === 'done' || p.status === 'building').length
      return ' · VBW building ' + plan.id + ' (' + at + '/' + mine.length + ')…'
    }
  }
  return ' · VBW ' + run.kind + (typeof run.phase === 'string' && run.phase ? ' · ' + run.phase : '') + '…'
}

// PromptHint `tail`: the run and its time, else the gate, else the next step.
export function hintTail(input) {
  const { record: rec, next: nx, run, now } = isObj(input) ? input : {}
  if (!isProject(rec)) return null
  if (live(run)) {
    const t = dur((Number.isFinite(now) ? now : Date.now()) - run.startedAt)
    return 'VBW: ' + run.kind + (t ? ' ' + t : '')
  }
  if (isObj(nx) && nx.gate === true) return 'VBW needs you: ' + nextCommand(nx)
  return 'VBW next: /vbw:vibe'
}

// SessionMode `modes`: the engine's labels, any VBW label replaced by the current one.
// The label is the same at every motion level: nothing here animates.
export function sessionModes(input) {
  const { modes, autonomy: a, profile } = isObj(input) ? input : {}
  if (!Array.isArray(modes)) return null
  let label = null
  if (isObj(a) && a.armed === true && Number.isFinite(a.step) && Number.isFinite(a.cap)) label = 'VBW auto ⟳ ' + a.step + '/' + a.cap
  else if (Object.hasOwn(PROFILES, profile)) label = 'VBW ' + PROFILES[profile]
  if (!label) return null
  return [...modes.filter((m) => !(typeof m === 'string' && m.startsWith('VBW '))), label]
}

// InfoNotice text, once at startup: requirements proven or accepted of the milestone's total.
export function infoNotice(input) {
  const { record: rec, next: nx } = isObj(input) ? input : {}
  if (!isProject(rec)) return null
  const reqs = milestoneReqs(rec)
  const ok = reqs.filter((r) => r.status === 'proven' || r.status === 'accepted').length
  return 'VBW ' + rec.milestone.id + ' · ' + ok + '/' + reqs.length + ' · next: ' + nextCommand(nx)
}

// A header above VBW's AskUserQuestion dialog.
export function questionHeader(input) {
  const { record: rec, decisionIndex: i, decisionCount: n } = isObj(input) ? input : {}
  if (!isProject(rec)) return null
  const ok = Number.isInteger(i) && Number.isInteger(n) && i >= 1 && i <= n
  return 'VBW · ' + (ok ? 'decision ' + i + ' of ' + n : 'a decision') + ' for ' + rec.milestone.id
}

// What VBW steps a turn made, from two record snapshots.
function changes(a, b) {
  const out = []
  const was = (list, id) => list.find((x) => x.id === id) || {}
  const approvals = (r) => arr(r.decisions).filter((d) => typeof d.text === 'string' && d.text.startsWith('Contract approved')).length
  if (approvals(b) > approvals(a)) out.push('plan approved')
  const turned = (key, status, word) => {
    const ids = arr(b[key]).filter((x) => x.status === status && was(arr(a[key]), x.id).status !== status).map((x) => x.id)
    if (ids.length) out.push(ids.join(', ') + ' ' + word)
  }
  turned('plans', 'done', 'done')
  turned('requirements', 'proven', 'proven')
  turned('requirements', 'accepted', 'accepted')
  const passed = arr(b.phases).filter((p) => isObj(p.qa) && p.qa.result === 'pass' && !(isObj(was(arr(a.phases), p.id).qa) && was(arr(a.phases), p.id).qa.result === 'pass'))
  if (passed.length) out.push(passed.map((p) => p.id).join(', ') + ' passed QA')
  if (b.milestone.status === 'shipped' && a.milestone.status !== 'shipped') out.push(b.milestone.id + ' shipped')
  return out
}

// TurnDuration: a short receipt after a turn that moved VBW on.
export function turnReceipt(input) {
  const { before, after, ms } = isObj(input) ? input : {}
  if (!isProject(before) || !isProject(after)) return null
  const steps = changes(before, after)
  if (!steps.length) return null
  const t = dur(ms, true)
  return 'VBW · ' + steps.join(', ') + (t ? ' · ' + t : '')
}

// The Workflow tool row of a VBW run, as a run card.
export function workflowCard(input) {
  const { input: wi, run } = isObj(input) ? input : {}
  if (!isObj(wi)) return null
  const meta = typeof wi.script === 'string' ? /meta\s*=\s*\{[^}]*?\bname\s*:\s*['"]([^'"]+)['"]/.exec(wi.script) : null
  const kind = vbwKind(wi.name, false) || vbwKind(wi.workflowName, false) || vbwKind(meta && meta[1], false)
  if (!kind) return null
  const mine = isObj(run) && run.kind === kind && Number.isFinite(run.startedAt)
  const started = mine ? ' · started ' + new Date(run.startedAt).toTimeString().slice(0, 5) : ''
  return 'VBW ' + kind + started + (mine && run.status !== 'running' ? ' · finished' : ' · [p] watch live')
}

// What a finished run produced, by kind, read from the record it left.
function produced(kind, rec) {
  const phases = milestonePhases(rec)
  const plans = milestonePlans(rec)
  const n = (k, one) => k + ' ' + one + (k === 1 ? '' : 's')
  if (kind === 'planning') {
    const reqs = new Set(milestoneReqs(rec).map((r) => r.id))
    return [n(phases.length, 'phase'), n(plans.length, 'plan'), n(arr(rec.checks).filter((c) => reqs.has(c.req)).length, 'check')]
  }
  if (kind === 'building' && plans.length) return [plans.filter((p) => p.status === 'done').length + ' of ' + n(plans.length, 'plan') + ' done']
  if (kind === 'verifying' && phases.length) return [phases.filter((p) => isObj(p.qa) && p.qa.result === 'pass').length + ' of ' + n(phases.length, 'phase') + ' passed']
  return []
}

// The task-notification row when a VBW workflow ends: the run receipt.
export function runReceipt(input) {
  const { final, record: rec, cost } = isObj(input) ? input : {}
  if (!isObj(final) || !isProject(rec)) return null
  const kind = vbwKind(final.workflowName, true)
  if (!kind) return null
  const head = final.status === 'completed' ? '✓ VBW ' + kind + ' finished'
    : final.status === 'failed' ? '✗ VBW ' + kind + ' failed' : '■ VBW ' + kind + ' stopped'
  const parts = [head, ...(final.status === 'completed' ? produced(kind, rec) : [])]
  const t = dur(final.durationMs)
  if (t) parts.push(t)
  if (Number.isFinite(cost) && cost >= 0) parts.push('≈$' + cost.toFixed(2))
  return parts.join(' · ')
}

// The words after `vbw` in a shell command, unquoted; null when no command runs vbw.
function vbwArgs(command) {
  if (typeof command !== 'string') return null
  // vbw in command position only: at the start, or after ; & | or (.
  const m = /(?:^|[;&|(])\s*(?:"[^"]*\/bin\/vbw"|'[^']*\/bin\/vbw'|[^\s"';&|()]*\/bin\/vbw|vbw)(?=\s|$)([^;&|<>]*)/.exec(command)
  if (!m) return null
  return (m[1].match(/"[^"]*"|'[^']*'|\S+/g) || []).map((w) => w.replace(/^(["'])(.*)\1$/, '$2'))
}

const ids = (a) => a.filter((w) => !w.startsWith('-')).join(', ')
const INTENTS = {
  'run start': (a) => a[0] + ' run started' + (a.length > 1 ? ': ' + ids(a.slice(1)) : ''),
  'run end': () => 'run closed',
  'run confirm': (a) => 'checked what ' + ids(a) + ' recorded',
  'plan done': (a) => 'recorded ' + a[0] + ' done',
  'plan block': (a) => 'recorded ' + a[0] + ' blocked',
  'plan reset': (a) => 'reset ' + a[0],
  'fix done': (a) => 'recorded ' + ids(a) + ' fixed',
  'fix retry': (a) => 'retrying ' + a[0],
  'qa finding': (a) => 'QA finding on ' + a[0],
  'qa record': (a) => a[0] + (a[1] === 'pass' ? ' passed QA' : ' failed QA'),
  'req accept': (a) => 'recorded ' + a[0] + ' accepted',
  'req reject': (a) => 'recorded ' + a[0] + ' rejected',
  'spec sync': () => 'synced the spec',
  'spec check': () => 'checking the spec',
  'spec add': () => 'added a requirement',
  'milestone start': () => 'new milestone started',
  'todo add': () => 'added a todo',
  apply: (a) => (a.includes('--patch') ? 'updated the plan' : 'recorded the plan'),
  approve: () => 'approving the contract',
  prove: () => 'proving the checks',
  check: () => 'running the checks',
  next: () => 'reading the next step',
  status: () => 'reading the status',
  show: (a) => 'showing ' + (a[0] || 'the record'),
  ship: () => 'shipping the milestone',
  decide: () => 'recorded a decision',
  commit: (a) => 'committed ' + a[0],
}

// A Bash row that runs `vbw …`, as what VBW did.
export function vbwRowIntent(input) {
  const a = vbwArgs(isObj(input) ? input.command : null)
  if (!a || !a.length) return null
  const two = a.length > 1 && INTENTS[a[0] + ' ' + a[1]]
  const one = INTENTS[a[0]]
  const text = two ? two(a.slice(2)) : one ? one(a.slice(1)) : a.slice(0, 2).join(' ')
  return 'VBW · ' + text
}

// A diff shown on .vbw/record.json, as what changed.
export function recordDiffIntent(diffText) {
  if (typeof diffText !== 'string' || !diffText.trim()) return null
  const lines = diffText.split('\n')
  const added = lines.filter((l) => l.startsWith('+')).join('\n')
  const removed = lines.filter((l) => l.startsWith('-')).join('\n')
  if (/"lease":\s*\{/.test(added)) {
    const k = /"kind":\s*"([a-z]+)"/.exec(added)
    return 'VBW · ' + (k ? k[1] + ' ' : '') + 'run started'
  }
  if (/"lease":\s*null/.test(added) && /"lease":\s*\{/.test(removed)) return 'VBW · run closed'
  if (/"text":\s*"Contract approved/.test(added)) return 'VBW · plan approved'
  const st = /"status":\s*"(done|proven|accepted|shipped|blocked)"/.exec(added)
  if (st) return 'VBW · recorded ' + { done: 'a plan done', proven: 'a requirement proven', accepted: 'a requirement accepted', shipped: 'the milestone shipped', blocked: 'a plan blocked' }[st[1]]
  if (/"result":\s*"(pass|fail)"/.test(added)) return 'VBW · recorded a QA verdict'
  return 'VBW · record updated'
}
