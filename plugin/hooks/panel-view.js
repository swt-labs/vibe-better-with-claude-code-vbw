// What the VBW panel says (R51): turns the project record and its last `vbw next`
// into plain sentences, each with its technical term beside it. Pure: data in,
// rows out; it never changes its input and never throws.

import { estimate } from './panel-estimate.js'

export const MIN_VERSION = '2.1.287'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const parts = (v) => {
  const m = typeof v === 'string' ? /^(\d+)\.(\d+)\.(\d+)/.exec(v) : null
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// The band redraws forever before 2.1.290 when its tree changes height (fixed in 2.1.290).
export const BAND_MIN_VERSION = '2.1.290'

// True when this Claude Code version has the panel (or, with `min`, that feature);
// anything unreadable counts as older.
export function supports(version, min = MIN_VERSION) {
  const v = parts(version)
  const m = parts(min)
  if (!v || !m) return false
  for (let i = 0; i < 3; i++) if (v[i] !== m[i]) return v[i] > m[i]
  return true
}

const NEUTRAL = { id: 'neutral', text: 'No VBW project is open here yet.', term: 'no project' }

function doing(rec, now) {
  const l = rec.lease
  if (!isObj(l)) return { id: 'doing', text: 'VBW is idle: nothing is running.', term: 'idle' }
  const ms = now - Date.parse(l.started_at)
  const mins = Number.isFinite(ms) ? Math.floor(ms / 60000) : 0
  const since = mins >= 1 ? mins + ' min so far' : 'just started'
  const names = (Array.isArray(rec.plans) ? rec.plans : [])
    .filter((p) => isObj(p) && p.status === 'building').map((p) => p.title).filter(Boolean)
  const what = {
    plan: ['planning the work', 'plan'],
    build: ['building' + (names.length ? ': ' + names.join(', ') : ' the plan'), 'build'],
    qa: ['checking the results', 'QA'],
    fix: ['fixing what the checks found', 'fix'],
    map: ['reading the project to map it', 'map'],
  }[l.kind] || ['working', String(l.kind || 'run')]
  return { id: 'doing', text: 'VBW is ' + what[0] + ' (' + since + ').', term: what[1] }
}

function needOf(nx, question) {
  if (isObj(question)) return { key: 'question:' + (question.id ?? ''), text: 'VBW has a question for you and is waiting for your answer.' }
  if (!isObj(nx) || nx.gate !== true) return null
  const d = isObj(nx.detail) ? nx.detail : {}
  const list = (a) => (Array.isArray(a) ? a.join(', ') : '')
  switch (nx.action) {
    case 'approve': return { key: 'approve', text: 'Please approve the plan before VBW builds it.' }
    case 'accept': { const r = list(d.requirements); return { key: 'accept:' + r, text: 'Please check the result by hand: ' + r + '.' } }
    case 'ship': return { key: 'ship', text: 'The milestone is ready: your go-ahead to ship it is needed.' }
    case 'spec': return { key: 'spec', text: 'VBW needs you to say what to build: the requirements.' }
    case 'escalate': { const f = list(d.fixes); return { key: 'escalate:' + f, text: 'A decision is needed from you on ' + f + '.' } }
    case 'unblock': { const p = list(d.plans); return { key: 'unblock:' + p, text: 'Work is blocked and needs you' + (p ? ': ' + p : '') + '.' } }
    case 'scope': return { key: 'scope', text: 'Some changes went outside their planned files: your decision is needed.' }
    case 'milestone': return { key: 'milestone', text: 'The milestone is shipped: say what to build next.' }
    case 'convert': return { key: 'convert', text: 'A VBW 1 plan is here: bring it into VBW 2 or start fresh.' }
    default: return { key: 'other:' + String(nx.action), text: 'VBW is waiting for you: run /vbw:vibe to see what for.' }
  }
}

// The session cost as one small line; no number when there is none to show.
function costRow(cost) {
  return Number.isFinite(cost) && cost >= 0
    ? { id: 'cost', text: 'This session has cost $' + cost.toFixed(2) + ' so far.', term: 'session cost' }
    : { id: 'cost', text: 'The cost so far is not available.', term: 'cost, not available' }
}

const mins = (sec) => Math.max(1, Math.round(sec / 60))
const NO_BASIS = { text: 'No estimate yet: there are not enough finished steps to go on.', term: 'estimate, no basis' }

// Time left for the running step and for the milestone, never more exact than it is.
function estimateRows(rec, steps, phasesLeft, now) {
  const e = estimate({ steps, lease: isObj(rec.lease) ? rec.lease : null, phasesLeft, now })
  const row = (id, x, what) => {
    if (x.state === 'none') return { id, ...NO_BASIS }
    if (x.state === 'longer') return { id, text: 'This step is taking longer than usual.', term: 'estimate, approximate' }
    return { id, text: 'About ' + mins(x.seconds) + ' min left in ' + what + '.', term: 'estimate, approximate' }
  }
  const rows = []
  if (e.step) rows.push(row('estimate-step', e.step, 'this step'))
  if (e.milestone && !(e.milestone.state === 'none' && rows.length && rows[0].term === NO_BASIS.term)) rows.push(row('estimate-milestone', e.milestone, 'the milestone'))
  return rows
}

export function panelView(input) {
  const { record: rec, next: nx, question, now, cost, steps } = isObj(input) ? input : {}
  if (!isObj(rec) || !isObj(rec.milestone) || !rec.milestone.id) return { rows: [NEUTRAL], need: null }
  const ph = (Array.isArray(rec.phases) ? rec.phases : []).filter((p) => isObj(p) && p.milestone === rec.milestone.id)
  const phasesLeft = ph.filter((p) => !(isObj(p.qa) && p.qa.result === 'pass')).length
  // Progress as the status line counts it: the current milestone's requirements proven or accepted.
  const rq = (Array.isArray(rec.requirements) ? rec.requirements : []).filter((r) => isObj(r) && r.milestone === rec.milestone.id)
  const done = rq.filter((r) => r.status === 'proven' || r.status === 'accepted').length
  const progress = rq.length === 0 ? 'No requirements are set yet.'
    : done + ' of ' + rq.length + (rq.length === 1 ? ' requirement' : ' requirements') + ' done.'
  const open = isObj(rec.lease)
  const need = open ? null : needOf(nx, question)
  return {
    need,
    rows: [
      { id: 'milestone', text: 'Working on ' + rec.milestone.id + ': ' + (rec.milestone.title || 'untitled') + '.', term: 'milestone' },
      { id: 'progress', text: progress, term: 'requirements' },
      doing(rec, Number.isFinite(now) ? now : Date.now()),
      ...estimateRows(rec, Array.isArray(steps) ? steps : [], phasesLeft, Number.isFinite(now) ? now : Date.now()),
      costRow(cost),
      { id: 'need', text: need ? need.text : 'Nothing is needed from you right now.', term: 'your turn' },
    ],
  }
}
