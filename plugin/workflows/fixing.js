export const meta = {
  name: 'fixing',
  description: 'VBW: work the open fix items, a Dev per group of fixes that share files, groups in parallel',
  whenToUse: 'Started by /vbw:vibe when vbw next says fix, inside a vbw run start fix lease',
  phases: [{ title: 'Fix', detail: 'a Dev per group of fixes; groups have disjoint files' }],
}

// args: {groups: [["F1", "F3"], ["F2"]], models?: {dev?}, rigor?: {P1: {tier, models}}} (docs/workflows.md).
// Fixes in one group share files, so one Dev works them together.
const groups = ((args && args.groups) || []).filter(g => Array.isArray(g) && g.length > 0)
const models = (args && args.models) || {}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
// The Dev model of the highest-tier phase (a fix has no phase of its own).
const RANK = { express: 0, standard: 1, deep: 2 }
const top = Object.values((args && args.rigor) || {}).filter(c => c && c.models && c.models.dev)
  .reduce((a, c) => (!a || (RANK[c.tier] || 0) > (RANK[a.tier] || 0) ? c : a), null)
const devModel = top ? top.models.dev : models.dev
if (groups.length === 0) return { results: [], error: 'no fix groups given: pass args.groups from vbw next --json (detail.groups)' }

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report'],
  properties: {
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const FIX_RESULT = {
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
  const confirm = sh(`vbw run confirm ${ids.join(' ')}`)
  const end = sh('vbw run end')
  const done = await agent(`Close this VBW run (your own instructions, Close a run, allow it). Run ${confirm} (it exits 1 when some fixes were not recorded), then, whatever it said, run ${end}. Answer ended (run end succeeded), recorded (confirm exited 0) and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, models.lead ? { model: models.lead } : {}))
  if (!done) log(`the closing agent stopped: run by hand: ${confirm} ; then ${end}`)
  else {
    if (!done.recorded || !done.ended) log(done.report)
    if (!done.recorded) log(`not everything was recorded: check by hand with ${confirm}`)
    if (!done.ended) log(`the run did not end: run by hand: ${end}`)
  }
  return done
}

phase('Fix')
const results = await pipeline(groups, ids =>
  agent(ids.length === 1
    ? `Fix VBW fix item ${ids[0]}. Start with: vbw show fix ${ids[0]}${voice}`
    : `Fix VBW fix items ${ids.join(', ')} together: they touch the same files and may share one cause. Start with: ${ids.map(id => `vbw show fix ${id}`).join('; ')}${voice}`,
    Object.assign({ agentType: 'vbw:dev', label: ids.join('+'), phase: 'Fix', schema: FIX_RESULT },
      devModel ? { model: devModel } : {})))

const out = groups.map((ids, i) => results[i]
  ? Object.assign({ fixes: ids }, results[i])
  : { fixes: ids, status: 'interrupted', summary: 'the Dev stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} fixer(s) stopped before reporting; their fixes stay open`)
const confirmation = await closeRun(groups.flat())
const complete = interrupted === 0 && (!session || Boolean(confirmation && confirmation.recorded && confirmation.ended))
return confirmation ? { results: out, complete, confirmation } : { results: out, complete }
