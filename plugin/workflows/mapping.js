export const meta = {
  name: 'mapping',
  description: 'VBW: map an existing codebase from several angles in parallel, then merge the findings into one map',
  whenToUse: 'Started by /vbw:map, usually before planning work on an existing codebase',
  phases: [
    { title: 'Scout', detail: 'one scout per angle, in parallel' },
    { title: 'Merge', detail: 'one map from all findings' },
  ],
}

// args: {models?: {scout?}}
const models = (args && args.models) || {}
const model = models.scout ? { model: models.scout } : {}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

// The run's own last step (R81): end the run on every way out. Only when the
// router passed args.session.
const session = (args && args.session) || ''
const closeRun = async () => {
  if (!session) return
  const done = await agent(`Close this VBW run: run VBW_SESSION_ID=${session} vbw run end. Answer ended (it succeeded), recorded (true) and report (what it printed). Change nothing else.`,
    Object.assign({ agentType: 'vbw:scout', label: 'close run', schema: CLOSE_RESULT }, model))
  if (!done || !done.ended) log('the closing agent stopped: run vbw run end by hand')
}

const ANGLES = [
  { key: 'stack', ask: 'The stack and how to work with it: languages, frameworks, package manager, and the exact commands to install, build, run, test and lint (try the test and lint commands and report what happens).' },
  { key: 'structure', ask: 'The structure: the top-level layout, the entry points, the main modules and what each owns, and how a request or command flows through them.' },
  { key: 'conventions', ask: 'The conventions a new change must follow: code style, naming, error handling, logging, file organization, and anything in CLAUDE.md, CONTRIBUTING or a linter config.' },
  { key: 'tests', ask: 'The tests: framework, where they live, how they are organized, fixtures and helpers, what is well covered and what is not.' },
  { key: 'risks', ask: 'The risks for someone changing this code: fragile or complex areas, generated or vendored code not to edit, global state, missing tests around important paths.' },
]

const CLOSE_RESULT = {
  type: 'object',
  required: ['ended', 'recorded', 'report'],
  properties: {
    ended: { type: 'boolean' },
    recorded: { type: 'boolean' },
    report: { type: 'string' },
  },
}

const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: { findings: { type: 'array', items: { type: 'string' } } },
}

const MAP = {
  type: 'object',
  required: ['map'],
  properties: { map: { type: 'string' } },
}

phase('Scout')
const found = await parallel(ANGLES.map(a => () =>
  agent(`Map this codebase from one angle. ${a.ask}${voice}`, Object.assign({ agentType: 'vbw:scout', label: `scout ${a.key}`, phase: 'Scout', schema: FINDINGS }, model))))

const sections = ANGLES.map((a, i) => ({ angle: a.key, findings: found[i] ? found[i].findings : [] }))
const missing = sections.filter(s => s.findings.length === 0).map(s => s.angle)
if (missing.length > 0) log(`no findings for: ${missing.join(', ')}`)

phase('Merge')
const map = await agent(`Merge these verified findings about this codebase into one concise markdown map, with the sections Stack and commands, Structure, Conventions, Tests, Risks. Keep every command and path exactly. Drop duplicates. No preamble.\n\n${JSON.stringify(sections)}${voice}`,
  Object.assign({ agentType: 'vbw:scout', label: 'scout merge', phase: 'Merge', schema: MAP }, model))

await closeRun()
return { map: (map && map.map) || sections.map(s => `## ${s.angle}\n${s.findings.map(f => `- ${f}`).join('\n')}`).join('\n\n'), missing }
