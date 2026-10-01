export const meta = {
  name: 'building',
  description: 'VBW: build one wave of ready plans in parallel, each to its own green checks',
  whenToUse: 'Started by /vbw:vibe when vbw next says build, inside a vbw run start build lease',
  phases: [{ title: 'Build', detail: 'one builder per plan; disjoint files' }],
}

// args: {plans: ["P1.1", ...], models?: {builder?}} (docs/workflows.md)
const plans = (args && args.plans) || []
const models = (args && args.models) || {}
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
const results = await pipeline(plans, id =>
  agent(`Build VBW plan ${id}. Start with: vbw show plan ${id}`,
    Object.assign({ agentType: 'vbw:builder', label: id, phase: 'Build', schema: BUILD_RESULT },
      models.builder ? { model: models.builder } : {})))

// An agent that was stopped or died returns null: its plan stays "building"
// until vbw run end returns it to the next wave. Say so instead of hiding it.
const out = plans.map((id, i) => results[i]
  ? Object.assign({ plan: id }, results[i])
  : { plan: id, status: 'interrupted', summary: 'the builder stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} builder(s) stopped before reporting; their plans return to the next wave`)
return { results: out }
