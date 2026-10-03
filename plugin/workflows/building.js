export const meta = {
  name: 'building',
  description: 'VBW: build one wave of ready plans in parallel, a Dev per plan (Docs for documentation plans), each to its own green checks',
  whenToUse: 'Started by /vbw:vibe when vbw next says build, inside a vbw run start build lease',
  phases: [{ title: 'Build', detail: 'a Dev (or Docs) per plan; disjoint files' }],
}

// args: {plans: ["P1.1", ...], docs?: ["P2.1"], models?: {dev?, docs?}, rigor?: {P1: {models}}} (docs/workflows.md).
// docs: the plans the Lead marked as documentation, built by the Docs agent.
const plans = (args && args.plans) || []
const docs = (args && args.docs) || []
const models = (args && args.models) || {}
const rigor = (args && args.rigor) || {}
if (plans.length === 0) return { results: [], error: 'no plans given: pass args.plans from vbw next --json' }

const BUILD_RESULT = {
  type: 'object',
  required: ['status', 'summary', 'notes'],
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string' },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

phase('Build')
const results = await pipeline(plans, id => {
  const role = docs.includes(id) ? 'docs' : 'dev'
  const cell = rigor[id.split('.')[0]]
  const m = (cell && cell.models && cell.models[role]) || models[role]
  return agent(`Execute VBW plan ${id}. Start with: vbw show plan ${id}`,
    Object.assign({ agentType: `vbw:${role}`, label: `${role} ${id}`, phase: 'Build', schema: BUILD_RESULT },
      m ? { model: m } : {}))
})

// An agent that was stopped or died returns null: its plan stays "building"
// until vbw run end returns it to the next wave. Say so instead of hiding it.
const out = plans.map((id, i) => results[i]
  ? Object.assign({ plan: id }, results[i])
  : { plan: id, status: 'interrupted', summary: 'the agent stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} agent(s) stopped before reporting; their plans return to the next wave`)
return { results: out }
