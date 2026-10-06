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
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
if (plans.length === 0) return { results: [], error: 'no plans given: pass args.plans from vbw next --json' }

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report'],
  properties: {
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const BUILD_RESULT = {
  type: 'object',
  required: ['status', 'summary', 'notes'],
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string' },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

// The run's own last step (R78, R81): confirm what the agents recorded, say plainly
// what was not, and end the run. Only when the router passed args.session.
const session = (args && args.session) || ''
const closeRun = async ids => {
  if (!session) return null
  const sh = c => `VBW_SESSION_ID=${session} ${c}`
  const done = await agent(`Close this VBW run. Run ${sh(`vbw run confirm ${ids.join(' ')}`)} (it exits 1 when some plans were not recorded), then, whatever it said, run ${sh('vbw run end')}. Answer ended (run end succeeded), recorded (confirm exited 0) and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:scout', label: 'close run', schema: CLOSE_RESULT }, models.scout ? { model: models.scout } : {}))
  if (!done) log('the closing agent stopped: run vbw run confirm and vbw run end by hand')
  else if (!done.recorded || !done.ended) log(done.report)
  return done
}

phase('Build')
const results = await pipeline(plans, id => {
  const role = docs.includes(id) ? 'docs' : 'dev'
  const cell = rigor[id.split('.')[0]]
  const m = (cell && cell.models && cell.models[role]) || models[role]
  return agent(`Execute VBW plan ${id}. Start with: vbw show plan ${id}${voice}`,
    Object.assign({ agentType: `vbw:${role}`, label: `${role} ${id}`, phase: 'Build', schema: BUILD_RESULT },
      m ? { model: m } : {}))
})

// An agent that was stopped or died returns null: its plan stays "building"
// until vbw run end returns it to the next wave. Say so instead of hiding it.
const out = plans.map((id, i) => results[i]
  ? Object.assign({ plan: id }, results[i])
  : { plan: id, status: 'interrupted', summary: 'the agent stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} agents stopped before reporting; their plans return to the next wave`)
const confirmation = await closeRun(plans)
return confirmation ? { results: out, confirmation } : { results: out }
