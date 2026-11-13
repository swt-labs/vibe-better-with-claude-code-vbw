export const meta = {
  name: 'verifying',
  description: 'VBW: QA verifies each built phase goal-backward against its goal, criteria and plans, and records findings and a verdict',
  whenToUse: 'Started by /vbw:vibe when vbw next says qa',
  phases: [{ title: 'Verify', detail: 'one QA agent per phase, in parallel' }],
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

// args: {phases: ["P1", ...], tier: "quick"|"standard"|"deep", models?: {qa?}, rigor?: {P1: {qa, models}},
// round?: {tiers, suite, focus?: {P1: {since, round, fixes}}, deviations?: {P1: [{file, plan, change, commit, by, decision}]}}} (docs/workflows.md).
const phases = (args && args.phases) || []
const tier = (args && args.tier) || 'standard'
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
if (phases.length === 0) return reply({ results: [], error: 'no phases given: pass args.phases from vbw next --json' })
// args.round is the round object of vbw next --json (tiers, suite, focus), absent or null when there is none.
// Anything else (a round number) would drop the depth and the test run without a word and tell every QA agent the project has no test command.
const given = args && args.round
if (given !== undefined && given !== null && (typeof given !== 'object' || Array.isArray(given))) return reply({ results: [], error: `args.round must be the round object of vbw next --json (tiers, suite, focus), not ${JSON.stringify(given)}: read it from vbw next --json` })

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report', 'state', 'refused'],
  properties: {
    refused: REFUSED,
    state: { type: 'string', description: 'What vbw run state printed, exactly as printed (one JSON line)' },
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const VERDICT = {
  type: 'object',
  required: ['verdict', 'checks', 'refused'],
  properties: {
    refused: REFUSED,
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
// R306 (T275, T288): the kernel's own answer, vbw run state as the closing agent returned it, never
// the agent's word. Null when it is missing or is not the JSON {open, recorded}.
const kernelState = done => {
  try {
    let s = JSON.parse(done && done.state)
    if (typeof s === 'string') s = JSON.parse(s) // a model may hand the line back quoted once
    return s && typeof s.open === 'boolean' && s.recorded && typeof s.recorded === 'object' && !Array.isArray(s.recorded) ? s : null
  } catch (e) { return null }
}
const closeRun = async ids => {
  if (!session) return null
  const sh = c => `VBW_SESSION_ID=${session} ${c}`
  const confirm = sh(`vbw run confirm ${ids.join(' ')}`)
  const end = sh('vbw run end')
  const state = sh(`vbw run state ${ids.join(' ')}`)
  const done = await ask(`Close this VBW run (your own instructions, Close a run, allow it). Run ${confirm} (it exits 1 when some verdicts were not recorded), then, whatever it said, run ${end}, then run ${state} and return its output exactly as printed in state. Answer ended (run end succeeded), recorded (confirm exited 0), state and report (the lines for what was not recorded, else "all recorded; run ended"). Change nothing else.${voice}`,
    Object.assign({ agentType: 'vbw:lead', label: 'close run', schema: CLOSE_RESULT }, { model: CLOSE_MODEL }, effortOf('lead', 'close')))
  if (!done) { log(`the closing agent stopped: run by hand: ${confirm} ; then ${end}`); return done }
  // The kernel decides: ended and recorded come from vbw run state, whatever the agent said.
  const k = kernelState(done)
  done.ended = Boolean(k) && k.open === false
  done.recorded = Boolean(k) && ids.every(id => k.recorded[id] === true)
  if (!k && done.report) log(done.report)
  if (!k) log(`the closing agent gave no readable vbw run state, so nothing is taken as done: run by hand: ${confirm} ; then ${end} ; then vbw run state ${ids.join(' ')}`)
  else {
    if (!done.recorded || !done.ended) log(done.report)
    if (!done.recorded) log(`not everything was recorded: check by hand with ${confirm}`)
    if (!done.ended) log(`the run is still open: run by hand: ${end}`)
  }
  return done
}

// The proof's one run of the project's test command (args.round.suite, from vbw next --json).
// The round carries command (the proof's, else the project's own, joined by spaces), status,
// exit, seconds and tail (the end of the output). A piece that is missing, null or empty is
// said in plain words, never printed as a value. Every QA agent gets the result; none runs the suite again.
const suite = (args && args.round && args.round.suite) || null
const ran = suite && suite.status !== 'skipped' && suite.status !== 'not run'
const has = (v) => v !== undefined && v !== null && v !== ''
const said = (v, missing, fmt) => (has(v) ? fmt(v) : missing)
const cmdWords = suite ? said(suite.command, 'the test command was not named', (v) => `the project's test command (${v})`) : ''
const statusWords = suite ? said(suite.status, 'its result was not kept', (v) => String(v)) : ''
const suiteNote = !suite ? `\n\nThis project has no test command (vbw next found none to run). Do not look for one to run; say in your summary that there is no test command.` : ran
  ? `\n\nThe project's test command ran once for this round. Facts: ${cmdWords}; ${statusWords}; ${said(suite.exit, 'its exit code was not kept', (v) => `exit ${v}`)}; ${said(suite.seconds, 'its time was not kept', (v) => `${v}s`)}; ${said(suite.tail, 'its output was not kept', (v) => `its output ends: ${v}`)}.\nDo not run the project's test command; use this result.`
  : `\n\nThe project's test command did not run in this round (${cmdWords}; ${statusWords}). Do not retry it and do not run it yourself; say in your summary that the suite was not run.`
if (suite && !ran) log(`the project's test command did not run (${cmdWords}; ${statusWords}): QA agents were told not to retry it`)

phase('Verify')
const cellOf = id => rigor[id] || {}
const sized = (args && args.round && args.round.tiers) || {}
const tierOf = id => sized[id] || cellOf(id).qa || tier
const modelOf = id => (cellOf(id).models && cellOf(id).models.qa) || models.qa
// A re-check round (args.round.focus, T131): the whole-phase sweep ran at round 1 and the goal,
// criteria and plans have not changed since, so QA verifies the fixes, what they reach and the goal.
const focuses = (args && args.round && args.round.focus) || {}
const focusNote = id => {
  const r = focuses[id]
  if (!r || !r.since) return ''
  const fixes = (r.fixes || []).map(f => `${f.id} (${f.req}): ${f.note}`).join('; ') || 'none recorded'
  return `\n\nThis is re-check round ${r.round || 2} for ${id}: the whole-phase sweep ran at round 1 and the goal, criteria and plans have not changed since. Verify only: the fixes since the last verdict (${fixes}); the files changed since that verdict (git diff --name-only ${r.since} HEAD, leaving out .vbw/) and what those files reach (callers, tests, documents stating their behaviour); and that the phase goal still holds. Do not sweep the rest of the phase again; a problem outside that scope is a note, unless it breaks the goal.`
}
// The files a phase's plans delivered that the last proof found changed outside any plan
// (args.round.deviations, docs/proof.md, Delivered files), in the words of vbw show phase:
// each one no decision of the user covers is a deviation, and vbw qa record refuses a pass while one stands.
const deviations = (args && args.round && args.round.deviations && typeof args.round.deviations === 'object') ? args.round.deviations : {}
const short = c => String(c || '').slice(0, 12)
const deviationLine = d => `${d.file} (${d.plan}) ${d.change} outside any plan`
  + (Array.isArray(d.by) && d.by.length > 0 ? `, by ${d.by.map(short).join(', ')}` : `, since ${short(d.commit)}`)
  + (d.decision ? `, covered by ${d.decision}` : '')
const deviationNote = id => {
  const list = Array.isArray(deviations[id]) ? deviations[id] : []
  if (list.length === 0) return ''
  return `\n\nVBW found files the plans of ${id} delivered that HEAD no longer holds as VBW left them: ${list.map(deviationLine).join('; ')}. Each one no decision covers is a deviation: record a finding for it (vbw qa finding ${id} REQ "<the file, what is missing or different, the commit>"); vbw qa record ${id} pass refuses while one stands. For one covered by a decision, check that the decision is the user's and covers that change: then it is not a deviation.`
}
// Red first (args.round.red_first, R292, D690): per plan, its own checks that never ran red before
// the plan's first code commit. QA lists each in its notes as a deviation from test first.
const redFirst = (args && args.round && args.round.red_first && typeof args.round.red_first === 'object' && !Array.isArray(args.round.red_first)) ? args.round.red_first : {}
const redFirstNote = id => {
  const rows = Object.keys(redFirst).filter(p => p.split('.')[0] === id && Array.isArray(redFirst[p]) && redFirst[p].length > 0)
  if (rows.length === 0) return ''
  return `\n\nRed first: these checks never ran red before their plan's first code commit: ${rows.map(p => `${p} (${redFirst[p].join(', ')})`).join('; ')}. List each in your notes as a deviation from test first; it is not a vbw qa finding and not a failure by itself.`
}
// R261: the packs of a phase's plans (args.packs.phases, args.packs_root): QA is told the qa text by path.
const packsRoot = (args && typeof args === 'object' && typeof args.packs_root === 'string' && args.packs_root) || ''
const packPhases = (args && args.packs && typeof args.packs === 'object' && args.packs.phases && typeof args.packs.phases === 'object') ? args.packs.phases : {}
const packNote = id => {
  const names = Array.isArray(packPhases[id]) ? packPhases[id].filter(n => typeof n === 'string' && n) : []
  return packsRoot && names.length ? `\n\nStack pack text for this phase: read ${names.map(n => `${packsRoot}/${n}/qa.md`).join(' and ')} first.` : ''
}
const results = await pipeline(phases, id =>
  ask(`Verify VBW phase ${id} at the ${tierOf(id)} tier, then record your findings and verdict with vbw qa (if qa record refuses a stale proof, run vbw prove --full, then retry the record once). Start with: vbw show phase ${id}${focusNote(id)}${deviationNote(id)}${redFirstNote(id)}${suiteNote}${packNote(id)}${voice}`,
    Object.assign({ agentType: 'vbw:qa', label: `qa ${id}`, phase: 'Verify', schema: VERDICT },
      modelOf(id) ? { model: modelOf(id) } : {}, effortOf('qa', 'verify'))))

const out = phases.map((id, i) => results[i]
  ? Object.assign({ phase: id }, results[i])
  : { phase: id, verdict: 'interrupted', checks: [], summary: 'QA stopped before reporting' })
const failed = out.filter(r => r.verdict !== 'pass').length
if (failed > 0) log(`${failed} phase(s) did not pass QA`)
const confirmation = await closeRun(phases)
const stopped = out.filter(r => r.verdict === 'interrupted').length
const complete = stopped === 0 && (!session || Boolean(confirmation && confirmation.recorded && confirmation.ended))
return reply(confirmation ? { tier, results: out, complete, confirmation } : { tier, results: out, complete })
