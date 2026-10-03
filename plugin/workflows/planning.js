export const meta = {
  name: 'planning',
  description: 'VBW: the Architect finds the decisions for the user and scopes the phases; the Lead plans them with tests that fail today and self-reviews',
  whenToUse: 'Started by /vbw:vibe when vbw next says plan, inside a vbw run start plan lease',
  phases: [
    { title: 'Decide', detail: 'Architect: the decisions only the user should make' },
    { title: 'Scope', detail: 'Architect: phases with goal-backward success criteria' },
    { title: 'Plan', detail: 'Lead: research, decompose, checks, self-review, apply' },
  ],
}

// args: {models?: {architect?, lead?}, decided?: true} (docs/workflows.md).
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
const SCOPE = {
  type: 'object',
  required: ['phases', 'notes'],
  properties: {
    phases: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        required: ['id', 'title', 'reqs', 'goal', 'criteria'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          reqs: { type: 'array', items: { type: 'string' } },
          goal: { type: 'string' },
          criteria: { type: 'array', items: { type: 'string' } },
          tier: { type: 'string', enum: ['express', 'standard', 'deep'] },
        },
      },
    },
    notes: { type: 'array', items: { type: 'string' } },
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

// The user decides what matters to them before anything is planned: the
// router asks, records the answers (vbw decide) and starts this workflow again
// with decided: true, so each planning round asks at most once.
if (!decided) {
  phase('Decide')
  const found = await agent('Job 1: find the decisions this VBW project needs from its user before planning. Change nothing.',
    opts('architect', { schema: DECISIONS, label: 'architect (decide)', phase: 'Decide' }))
  const open = (found && found.decisions) || []
  if (open.length > 0) {
    log(`${open.length} decision(s) for the user before planning`)
    return { status: 'needs_decisions', decisions: open }
  }
}

phase('Scope')
const scope = await agent('Job 2: scope the current milestone into phases, each with a goal and goal-backward success criteria. Change nothing.',
  opts('architect', { schema: SCOPE, label: 'architect (scope)', phase: 'Scope' }))
if (!scope || !scope.phases || scope.phases.length === 0) {
  return { status: 'blocked', summary: 'the Architect could not scope the milestone', blockers: [], notes: [] }
}

phase('Plan')
const plan = await agent(`Plan these phases: research, decompose them into plans with tasks, write the checks, self-review, and apply with vbw apply. The kernel computes a rigor floor per phase from its signals and refuses a lower tier. Use these phases exactly as given, tier included:\n\n${JSON.stringify(scope.phases)}`,
  opts('lead', { schema: PLAN_RESULT, phase: 'Plan' }))
if (!plan || !plan.applied) {
  return { status: 'blocked', summary: plan ? plan.summary : 'the Lead did not finish', blockers: plan ? plan.blockers : [], notes: scope.notes }
}

return {
  status: 'planned',
  summary: plan.summary,
  blockers: plan.blockers,
  choices: plan.choices || [],
  notes: scope.notes,
}
