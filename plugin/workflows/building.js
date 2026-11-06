export const meta = {
  name: 'building',
  description: 'VBW: build one wave of ready plans in parallel, a Dev per plan (Docs for documentation plans), each to its own green checks',
  whenToUse: 'Started by /vbw:vibe when vbw next says build, inside a vbw run start build lease',
  phases: [{ title: 'Build', detail: 'a Dev (or Docs) per plan; disjoint files' }],
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

// args: {plans: ["P1.1", ...], docs?: ["P2.1"], effort?: {dev?: {build}, docs?: {build}, lead?: {close}}, models?: {dev?, docs?; models.lead is not used for closing}, rigor?: {P1: {models, tier}}} (docs/workflows.md).
// docs: the plans the Lead marked as documentation, built by the Docs agent.
const plans = (args && args.plans) || []
const docs = (args && args.docs) || []
const models = (args && args.models) || {}
// R186, D369: the closing step is a few fixed commands and the record stays the source of truth.
const CLOSE_MODEL = 'haiku'
const rigor = (args && args.rigor) || {}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
if (plans.length === 0) return reply({ results: [], error: 'no plans given: pass args.plans from vbw next --json' })

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

const BUILD_RESULT = {
  type: 'object',
  required: ['status', 'summary', 'notes', 'refused'],
  properties: {
    refused: REFUSED,
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
  const done = await ask(`Close this VBW run (your own instructions, Close a run, allow it). Run ${confirm} (it exits 1 when some plans were not recorded), then, whatever it said, run ${end}. Answer ended (run end succeeded), recorded (confirm exited 0) and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, { model: CLOSE_MODEL }, effortOf('lead', 'close')))
  if (!done) log(`the closing agent stopped: run by hand: ${confirm} ; then ${end}`)
  else {
    if (!done.recorded || !done.ended) log(done.report)
    if (!done.recorded) log(`not everything was recorded: check by hand with ${confirm}`)
    if (!done.ended) log(`the run did not end: run by hand: ${end}`)
  }
  return done
}

// T123: a decision recorded after the approval may correct the plan mid-milestone; the brief names them.
// #705: the plan's id, so an approval that left the plan as it was hides no decision from it.
const SINCE = id => `vbw show decisions --since-approval ${id} (decisions recorded since the contract was last approved with a change to this plan: where one differs from the plan, the decision wins).`

// R261: the stack packs (args.packs, args.packs_root from vbw next --json). A plan with a pack gets a
// note naming the pack's dev text by path (the workflow reads no file); a plan without one gets the empty string.
const packsRoot = (args && typeof args === 'object' && typeof args.packs_root === 'string' && args.packs_root) || ''
const packNote = id => {
  const names = (args && args.packs && args.packs.plans && Array.isArray(args.packs.plans[id])) ? args.packs.plans[id].filter(n => typeof n === 'string' && n) : []
  return packsRoot && names.length ? `\n\nThis plan's stack pack text: read ${names.map(n => `${packsRoot}/${n}/dev.md`).join(' and ')} first.` : ''
}

phase('Build')
const results = await pipeline(plans, id => {
  const role = docs.includes(id) ? 'docs' : 'dev'
  const cell = rigor[id.split('.')[0]]
  const m = (cell && cell.models && cell.models[role]) || models[role]
  const tier = cell && cell.tier
  const mutate = tier === 'standard' || tier === 'deep' ? ` This plan's rigor tier: ${tier}. Do the mutation step of your instructions before vbw plan done.` : ''
  return ask(`Execute VBW plan ${id}. Start with: vbw show plan ${id}; then ${SINCE(id)}${mutate}${role === 'dev' ? packNote(id) : ''}${voice}`,
    Object.assign({ agentType: `vbw:${role}`, label: `${role} ${id}`, phase: 'Build', schema: BUILD_RESULT },
      m ? { model: m } : {}, effortOf(role, 'build')))
})

// An agent that was stopped or died returns null: its plan stays "building"
// until vbw run end returns it to the next wave. Say so instead of hiding it.
const out = plans.map((id, i) => results[i]
  ? Object.assign({ plan: id }, results[i])
  : { plan: id, status: 'interrupted', summary: 'the agent stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} agents stopped before reporting; their plans return to the next wave`)
const confirmation = await closeRun(plans)
const complete = interrupted === 0 && (!session || Boolean(confirmation && confirmation.recorded && confirmation.ended))
return reply(confirmation ? { results: out, complete, confirmation } : { results: out, complete })
