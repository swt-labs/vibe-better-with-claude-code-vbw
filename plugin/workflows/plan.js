export const meta = {
  name: 'plan',
  description: 'VBW: turn the spec into phases, plans and contract checks, then critique them once',
  whenToUse: 'Started by /vbw:vibe when vbw next says plan, inside a vbw run start plan lease',
  phases: [
    { title: 'Plan', detail: 'planner writes checks and applies the plan' },
    { title: 'Critique', detail: 'critic looks for what would make the plan fail' },
    { title: 'Revise', detail: 'planner fixes blocker and major issues' },
  ],
}

// args: {models?: {planner?, critic?}} (docs/workflows.md)
const models = (args && args.models) || {}
const opts = (role, extra) => Object.assign({ agentType: `vbw:${role}`, label: role },
  models[role] ? { model: models[role] } : {}, extra)

const PLAN_RESULT = {
  type: 'object',
  required: ['applied', 'summary', 'blockers'],
  properties: {
    applied: { type: 'boolean' },
    summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } },
  },
}
const CRITIQUE = {
  type: 'object',
  required: ['issues'],
  properties: {
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'what', 'fix'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          what: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
  },
}

phase('Plan')
let plan = await agent('Plan this project: read .vbw/spec.md and the code, write the check test files, and apply the plan with vbw apply.',
  opts('planner', { schema: PLAN_RESULT }))
if (!plan || !plan.applied) {
  return { status: 'blocked', summary: plan ? plan.summary : 'the planner did not finish', blockers: plan ? plan.blockers : [], issues: [] }
}

phase('Critique')
const critique = await agent('Review the applied VBW plan against .vbw/spec.md before the user approves it.',
  opts('critic', { schema: CRITIQUE }))
const serious = ((critique && critique.issues) || []).filter(i => i.severity !== 'minor')

if (serious.length > 0) {
  phase('Revise')
  log(`critic found ${serious.length} issue(s) to fix before approval`)
  const list = serious.map((i, n) => `${n + 1}. [${i.severity}] ${i.what}\n   Fix: ${i.fix}`).join('\n')
  const revised = await agent(`Revise the applied VBW plan to resolve these review findings, then apply it again with vbw apply:\n\n${list}`,
    opts('planner', { schema: PLAN_RESULT, label: 'planner (revise)' }))
  if (revised) plan = revised
}

return {
  status: plan.applied ? 'planned' : 'blocked',
  summary: plan.summary,
  blockers: plan.blockers,
  issues: (critique && critique.issues) || [],
  revised: serious.length > 0,
}
