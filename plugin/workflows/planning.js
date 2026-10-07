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

// args: {requirements, models?: {architect?, lead?}, decided?: true} (docs/workflows.md).
// decided: the user has just answered this round's questions; plan now.
const models = (args && args.models) || {}
const decided = Boolean(args && args.decided)
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
// The active milestone's requirements (args.requirements, from vbw next --json):
// the only ones the Architect is shown, so it never asks about shipped work.
const reqs = (args && Array.isArray(args.requirements)) ? args.requirements : null
const reqList = reqs ? `\n\nRequirements of this milestone (the only ones to consider):\n${reqs.map(r => `- ${r.id} [${r.proof}] ${r.text}`).join('\n')}` : ''
const opts = (role, extra) => Object.assign({ agentType: `vbw:${role}`, label: role },
  models[role] ? { model: models[role] } : {}, extra)

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report'],
  properties: {
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}
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

// The run's own last step (R81): end the run on every way out. Only when the
// router passed args.session.
const session = (args && args.session) || ''
const closeRun = async (phaseIds = []) => {
  if (!session) return null
  const end = `VBW_SESSION_ID=${session} vbw run end`
  const check = phaseIds.length === 0 ? '' : `First check that each planned phase has plans: ${phaseIds.map(id => `vbw show phase ${id}`).join('; ')}. `
  const done = await agent(`Close this VBW run (your own instructions, Close a run, allow it). ${check}Then, whatever you found, run ${end}. Answer ended (run end succeeded), recorded (${phaseIds.length === 0 ? 'true' : 'every phase has plans'}) and report (${phaseIds.length === 0 ? 'what it printed' : 'name each phase without plans, else "all recorded; run ended"'}). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, models.lead ? { model: models.lead } : {}))
  if (!done) log(`the closing agent stopped: run by hand: ${end}`)
  else {
    if (!done.recorded) log(done.report)
    if (!done.ended) log(`the run did not end: run by hand: ${end}`)
  }
  return done
}

// The user decides what matters to them before anything is planned: the
// router asks, records the answers (vbw decide) and starts this workflow again
// with decided: true, so each planning round asks at most once.
if (!reqs || reqs.length === 0) {
  await closeRun()
  return { status: 'blocked', summary: 'planning needs the requirements of this milestone (args.requirements, from vbw next --json) and got none', blockers: [], notes: [] }
}

if (!decided) {
  phase('Decide')
  const found = await agent(`Job 1: find the decisions this VBW project needs from its user before planning. Change nothing.${reqList}${voice}`,
    opts('architect', { schema: DECISIONS, label: 'architect (decide)', phase: 'Decide' }))
  const open = (found && found.decisions) || []
  if (open.length > 0) {
    log(`${open.length} decision(s) for the user before planning`)
    await closeRun()
    return { status: 'needs_decisions', decisions: open }
  }
}

phase('Scope')
const scope = await agent(`Job 2: scope the current milestone into phases, each with a goal and goal-backward success criteria. Change nothing.${reqList}${voice}`,
  opts('architect', { schema: SCOPE, label: 'architect (scope)', phase: 'Scope' }))
if (!scope || !scope.phases || scope.phases.length === 0) {
  await closeRun()
  return { status: 'blocked', summary: 'the Architect could not scope the milestone', blockers: [], notes: [] }
}

phase('Plan')
const plan = await agent(`Plan these phases: research, decompose them into plans with tasks, write the checks, self-review, and apply with vbw apply. The kernel computes a rigor floor per phase from its signals and refuses a lower tier. Use these phases exactly as given, tier included:\n\n${JSON.stringify(scope.phases)}${voice}`,
  opts('lead', { schema: PLAN_RESULT, phase: 'Plan' }))
if (!plan || !plan.applied) {
  await closeRun()
  return { status: 'blocked', summary: plan ? plan.summary : 'the Lead did not finish', blockers: plan ? plan.blockers : [], notes: scope.notes }
}

const closed = await closeRun(scope.phases.map(p => p.id))
if (closed && !closed.recorded) {
  return { status: 'blocked', summary: `planning is not complete: ${closed.report}`, blockers: plan.blockers, notes: scope.notes }
}
return {
  status: 'planned',
  summary: plan.summary,
  blockers: plan.blockers,
  choices: plan.choices || [],
  notes: scope.notes,
}
