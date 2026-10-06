export const meta = {
  name: 'verifying',
  description: 'VBW: QA verifies each built phase goal-backward against its goal, criteria and plans, and records findings and a verdict',
  whenToUse: 'Started by /vbw:vibe when vbw next says qa',
  phases: [{ title: 'Verify', detail: 'one QA agent per phase, in parallel' }],
}

// args: {phases: ["P1", ...], tier: "quick"|"standard"|"deep", models?: {qa?}, rigor?: {P1: {qa, models}}} (docs/workflows.md).
const phases = (args && args.phases) || []
const tier = (args && args.tier) || 'standard'
const models = (args && args.models) || {}
const rigor = (args && args.rigor) || {}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
if (phases.length === 0) return { results: [], error: 'no phases given: pass args.phases from vbw next --json' }

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report'],
  properties: {
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const VERDICT = {
  type: 'object',
  required: ['verdict', 'checks'],
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    checks: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'check', 'status', 'evidence'],
        properties: {
          id: { type: 'string' },
          check: { type: 'string' },
          status: { type: 'string', enum: ['pass', 'fail'] },
          evidence: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}

// The run's own last step (R78, R81): confirm what the agents recorded, say plainly
// what was not, and end the run. Only when the router passed args.session.
const session = (args && args.session) || ''
const closeRun = async ids => {
  if (!session) return null
  const sh = c => `VBW_SESSION_ID=${session} ${c}`
  const done = await agent(`Close this VBW run. Run ${sh(`vbw run confirm ${ids.join(' ')}`)} (it exits 1 when some verdicts were not recorded), then, whatever it said, run ${sh('vbw run end')}. Answer ended (run end succeeded), recorded (confirm exited 0) and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:scout', label: 'close run', schema: CLOSE_RESULT }, models.scout ? { model: models.scout } : {}))
  if (!done) log('the closing agent stopped: run vbw run confirm and vbw run end by hand')
  else if (!done.recorded || !done.ended) log(done.report)
  return done
}

// The proof's one run of the project's test command (args.round.suite, from vbw next --json):
// every QA agent gets its result and none runs the suite again.
const suite = (args && args.round && args.round.suite) || null
const ran = suite && suite.status !== 'skipped' && suite.status !== 'not run'
const suiteNote = !suite ? '' : ran
  ? `\n\nThe project's test command (${suite.command}) ran once for this round: ${suite.status}, exit ${suite.exit}, ${suite.seconds}s. Its output ends: ${suite.tail}\nDo not run the project's test command; use this result.`
  : `\n\nThe project's test command (${suite.command}) did not run in this round (${suite.status}). Do not retry it and do not run it yourself; say in your summary that the suite was not run.`
if (suite && !ran) log(`the project's test command (${suite.command}) did not run (${suite.status}): QA agents were told not to retry it`)

phase('Verify')
const cellOf = id => rigor[id] || {}
const sized = (args && args.round && args.round.tiers) || {}
const tierOf = id => sized[id] || cellOf(id).qa || tier
const modelOf = id => (cellOf(id).models && cellOf(id).models.qa) || models.qa
const results = await pipeline(phases, id =>
  agent(`Verify VBW phase ${id} at the ${tierOf(id)} tier, then record your findings and verdict with vbw qa (if qa record refuses a stale proof, run vbw prove, then retry the record once). Start with: vbw show phase ${id}${suiteNote}${voice}`,
    Object.assign({ agentType: 'vbw:qa', label: `qa ${id}`, phase: 'Verify', schema: VERDICT },
      modelOf(id) ? { model: modelOf(id) } : {})))

const out = phases.map((id, i) => results[i]
  ? Object.assign({ phase: id }, results[i])
  : { phase: id, verdict: 'interrupted', checks: [], summary: 'QA stopped before reporting' })
const failed = out.filter(r => r.verdict !== 'pass').length
if (failed > 0) log(`${failed} phase(s) did not pass QA`)
const confirmation = await closeRun(phases)
return confirmation ? { tier, results: out, confirmation } : { tier, results: out }
