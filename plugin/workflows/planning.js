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

// Kernel refusals reach the user as written (docs/workflows.md, "Refusals reach the user"):
// every agent schema requires refused, and the result carries them all, each named by
// the agent that saw it, so the router shows them word for word.
const REFUSED = {
  type: 'array',
  description: 'Each refusal VBW gave you: a vbw command that refused (it exited non-zero with a message starting "vbw:") or a tool call a guard blocked (a reason starting "VBW guard:"), each copied verbatim and whole, through its Next: line; [] when none',
  items: { type: 'string' },
}
// The project folder (args.root: vbw next --json or vbw root). A session started in a subfolder
// starts its agents there, so each agent is told where the project's paths are.
const projectRoot = (args && typeof args === 'object' && typeof args.root === 'string' && args.root) || ''
const where = projectRoot ? `\n\nThe project folder is ${projectRoot}. Every path VBW names (plan and check files, .vbw/...) is relative to it, whatever folder you start in: give file tools and shell redirects absolute paths under it, and run other shell commands from it (cd "${projectRoot}" && ...).` : ''
const refused = []
const ask = async (prompt, o) => {
  const r = await agent(prompt + where, o)
  for (const text of r && Array.isArray(r.refused) ? r.refused : []) {
    if (typeof text !== 'string' || !text.trim()) continue
    refused.push({ by: o.label, text })
    log(`${o.label} was refused: ${text}`)
  }
  return r
}
const reply = o => Object.assign(o, { refused })

// args: {requirements, models?: {architect?, lead?}, decided?: true, research?, effort?, next_phase?} (docs/workflows.md).
// decided: the user has just answered this round's questions; plan now.
// research: with decided, the decide step's findings from the needs_decisions reply.
// effort: {<role>: {<step>: level}} from vbw next --json; used only when it is an object, else agents run as before.
// next_phase: the next free phase number; the Architect numbers new phases from it.
const models = (args && args.models) || {}
// R186, D369: the closing step is a few fixed commands and the record stays the source of truth.
const CLOSE_MODEL = 'haiku'
const decided = Boolean(args && args.decided)
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
// The active milestone's requirements (args.requirements, from vbw next --json):
// the only ones the Architect is shown, so it never asks about shipped work.
const reqs = (args && Array.isArray(args.requirements)) ? args.requirements : null
const reqList = reqs ? `\n\nRequirements of this milestone (the only ones to consider):\n${reqs.map(r => `- ${r.id} [${r.proof}] ${r.text}`).join('\n')}` : ''
// The requirements reworded since they were planned (args.reworded, vbw next's detail.reworded):
// their rules were kept, and the Lead reviews them in this plan step.
const reworded = (args && Array.isArray(args.reworded)) ? args.reworded.filter(x => typeof x === 'string') : []
const rewordedLine = reworded.length ? `\n\nReworded requirements (${reworded.join(', ')}): their rules were kept; review each one as your instructions say.` : ''
// The effort option for a role and step, or nothing when the table has none.
const effortTable = (args && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : null
const effortFor = (role, step) => {
  const t = effortTable && effortTable[role]
  const level = t && typeof t === 'object' ? t[step] : undefined
  return level ? { effort: level } : {}
}
const opts = (role, step, extra) => Object.assign({ agentType: `vbw:${role}`, label: role },
  models[role] ? { model: models[role] } : {}, effortFor(role, step), extra)
const nextPhase = args && args.next_phase
const numbering = nextPhase ? ` Number the new phases from P${nextPhase}, in order, and keep phases already started exactly as they are.` : ''

// #720: what an agent verified in the code, handed to the next stage so it is not researched again.
const RESEARCH = {
  type: 'array',
  description: 'What you verified in the code that the next planning stage needs, one short fact each as "path:line — fact" (where the behaviour lives, call paths, existing tests, how to run them); [] when you read no code',
  items: { type: 'string' },
}
const strings = v => Array.isArray(v) ? v.filter(s => typeof s === 'string' && s.trim()) : []
const findings = list => list.length === 0 ? '' : `\n\nFindings already verified in the code. Start from them; read code only for what they lack or where you need exact lines:\n${list.map(s => `- ${s}`).join('\n')}`

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report', 'refused'],
  properties: {
    refused: REFUSED,
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}
const DECISIONS = {
  type: 'object',
  required: ['decisions', 'research', 'refused'],
  properties: {
    refused: REFUSED,
    research: RESEARCH,
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
  required: ['phases', 'notes', 'research', 'refused'],
  properties: {
    refused: REFUSED,
    research: RESEARCH,
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
  required: ['applied', 'summary', 'blockers', 'refused'],
  properties: {
    refused: REFUSED,
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
  const done = await ask(`Close this VBW run (your own instructions, Close a run, allow it). ${check}Then, whatever you found, run ${end}. Answer ended (run end succeeded), recorded (${phaseIds.length === 0 ? 'true' : 'every phase has plans'}) and report (${phaseIds.length === 0 ? 'what it printed' : 'name each phase without plans, else "all recorded; run ended"'}). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, { model: CLOSE_MODEL }, effortFor('lead', 'close')))
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
  return reply({ status: 'blocked', summary: 'planning needs the requirements of this milestone (args.requirements, from vbw next --json) and got none', blockers: [], notes: [] })
}

// The decide step's findings: from this run, or handed back by the router after the
// user's decision round (args.research), so the scope step does not research again.
let research = decided ? strings(args.research) : []
if (!decided) {
  phase('Decide')
  const found = await ask(`Job 1: find the decisions this VBW project needs from its user before planning. Change nothing.${reqList}${voice}`,
    opts('architect', 'decide', { schema: DECISIONS, label: 'architect (decide)', phase: 'Decide' }))
  const open = (found && found.decisions) || []
  research = strings(found && found.research)
  if (open.length > 0) {
    log(`${open.length} decision(s) for the user before planning`)
    await closeRun()
    return reply({ status: 'needs_decisions', decisions: open, research })
  }
}

phase('Scope')
const scope = await ask(`Job 2: scope the current milestone into phases, each with a goal and goal-backward success criteria. Change nothing.${numbering}${reqList}${findings(research)}${voice}`,
  opts('architect', 'scope', { schema: SCOPE, label: 'architect (scope)', phase: 'Scope' }))
if (!scope || !scope.phases || scope.phases.length === 0) {
  await closeRun()
  return reply({ status: 'blocked', summary: 'the Architect could not scope the milestone', blockers: [], notes: [] })
}

phase('Plan')
// R261: the packs the project's tracked files match (args.packs.project, args.packs_root): the Lead is told the lead text by path.
const packsRoot = (args && typeof args === 'object' && typeof args.packs_root === 'string' && args.packs_root) || ''
const packNames = (args && args.packs && Array.isArray(args.packs.project)) ? args.packs.project.filter(n => typeof n === 'string' && n) : []
const packLine = packsRoot && packNames.length ? `\n\nStack pack text: read ${packNames.map(n => `${packsRoot}/${n}/lead.md`).join(' and ')} first.` : ''
const plan = await ask(`Plan these phases: research, decompose them into plans with tasks, write the checks, self-review, and apply with vbw apply. The kernel computes a rigor floor per phase from its signals and refuses a lower tier. Use these phases exactly as given, tier included:\n\n${JSON.stringify(scope.phases)}${rewordedLine}${strings(scope.notes).length ? `\n\nThe Architect's notes (what is out of scope waits in the backlog; do not plan it):\n${strings(scope.notes).map(s => `- ${s}`).join('\n')}` : ''}${findings(strings(scope.research))}${packLine}${voice}`,
  opts('lead', 'plan', { schema: PLAN_RESULT, phase: 'Plan' }))
if (!plan || !plan.applied) {
  await closeRun()
  return reply({ status: 'blocked', summary: plan ? plan.summary : 'the Lead did not finish', blockers: plan ? plan.blockers : [], notes: scope.notes })
}

const closed = await closeRun(scope.phases.map(p => p.id))
if (closed && !closed.recorded) {
  return reply({ status: 'blocked', summary: `planning is not complete: ${closed.report}`, blockers: plan.blockers, notes: scope.notes })
}
return reply({
  status: 'planned',
  summary: plan.summary,
  blockers: plan.blockers,
  choices: plan.choices || [],
  notes: scope.notes,
})
