// What the VBW panel says (R51): turns the project record and its last `vbw next`
// into plain sentences, each with its technical term beside it. Pure: data in,
// rows out; it never changes its input and never throws.

export const MIN_VERSION = '2.1.287'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const parts = (v) => {
  const m = typeof v === 'string' ? /^(\d+)\.(\d+)\.(\d+)/.exec(v) : null
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// True when this Claude Code version has the panel; anything unreadable counts as older.
export function supports(version) {
  const v = parts(version)
  if (!v) return false
  const min = parts(MIN_VERSION)
  for (let i = 0; i < 3; i++) if (v[i] !== min[i]) return v[i] > min[i]
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
    default: return null
  }
}

export function panelView(input) {
  const { record: rec, next: nx, question, now } = isObj(input) ? input : {}
  if (!isObj(rec) || !isObj(rec.milestone) || !rec.milestone.id) return { rows: [NEUTRAL], need: null }
  const ph = (Array.isArray(rec.phases) ? rec.phases : []).filter((p) => isObj(p) && p.milestone === rec.milestone.id)
  const done = ph.filter((p) => isObj(p.qa) && p.qa.result === 'pass').length
  const progress = ph.length === 0 ? 'No phases are planned yet.'
    : done + ' of ' + ph.length + (ph.length === 1 ? ' phase' : ' phases') + ' done.'
  const open = isObj(rec.lease)
  const need = open ? null : needOf(nx, question)
  return {
    need,
    rows: [
      { id: 'milestone', text: 'Working on ' + rec.milestone.id + ': ' + (rec.milestone.title || 'untitled') + '.', term: 'milestone' },
      { id: 'progress', text: progress, term: 'phases' },
      doing(rec, Number.isFinite(now) ? now : Date.now()),
      { id: 'need', text: need ? need.text : 'Nothing is needed from you right now.', term: 'your turn' },
    ],
  }
}
