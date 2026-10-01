export const meta = {
  name: 'planning',
  description: 'VBW: find the decisions the user must make, then turn the spec into phases, plans and contract checks and critique them once',
  whenToUse: 'Started by /vbw:vibe when vbw next says plan, inside a vbw run start plan lease',
  phases: [
    { title: 'Decide', detail: 'planner finds the decisions only the user should make' },
    { title: 'Plan', detail: 'planner writes checks and applies the plan' },
    { title: 'Critique', detail: 'critic looks for what would make the plan fail' },
    { title: 'Revise', detail: 'planner fixes blocker and major issues' },
  ],
}

// args: {models?: {planner?, critic?}, decided?: true} (docs/workflows.md).
// decided: the user has just answered this round's questions; plan now.
const models = (args && args.models) || {}
const decided = Boolean(args && args.decided)
const opts = (role, extra) => Object.assign({ agentType: `vbw:${role}`, label: role },
  models[role] ? { model: models[role] } : {}, extra)

const DECISIONS = {
  type: 'object',
  required: ['decisions'],
  properties: {
    decisions: {
      type: 'array',
      maxItems: 4,
      items: {
        type: 'object',
        required: ['question', 'why_it_matters', 'options', 'recommended'],
        properties: {
          question: { type: 'string' },
          why_it_matters: { type: 'string' },
          options: {
            type: 'array',
            minItems: 2,
            maxItems: 4,
            items: {
              type: 'object',
              required: ['label', 'tradeoff'],
              properties: { label: { type: 'string' }, tradeoff: { type: 'string' } },
            },
          },
          recommended: { type: 'string' },
        },
      },
    },
  },
}
const PLAN_RESULT = {
  type: 'object',
  required: ['applied', 'summary', 'blockers'],
  properties: {
    applied: { type: 'boolean' },
    summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'string' } },
    choices: { type: 'array', items: { type: 'string' } },
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

// The user decides what matters to them before anything is planned: the
// router asks, records the answers (vbw decide) and starts this workflow again
// with decided: true, so each planning round asks at most once.
if (!decided) {
  phase('Decide')
  const found = await agent('Find the decisions this VBW project needs from its user before planning. Do not plan or write anything yet.',
    opts('planner', { schema: DECISIONS, label: 'planner (decide)' }))
  const open = (found && found.decisions) || []
  if (open.length > 0) {
    log(`${open.length} decision(s) for the user before planning`)
    return { status: 'needs_decisions', decisions: open }
  }
}

phase('Plan')
let plan = await agent('Plan this project: read .vbw/spec.md, the recorded decisions and the code, write the check test files, and apply the plan with vbw apply.',
  opts('planner', { schema: PLAN_RESULT }))
if (!plan || !plan.applied) {
  return { status: 'blocked', summary: plan ? plan.summary : 'the planner did not finish', blockers: plan ? plan.blockers : [], issues: [] }
}

phase('Critique')
const critique = await agent('Review the applied VBW plan against .vbw/spec.md and the recorded decisions before the user approves it.',
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
  choices: plan.choices || [],
  issues: (critique && critique.issues) || [],
  revised: serious.length > 0,
}
