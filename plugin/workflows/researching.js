export const meta = {
  name: 'researching',
  description: 'VBW: up to four Scouts research a question from different angles in parallel, then one weighs their findings into a sourced answer',
  whenToUse: 'Started by /vbw:research with the question',
  phases: [
    { title: 'Research', detail: 'a Scout per angle, in parallel' },
    { title: 'Answer', detail: 'one sourced answer with a recommendation' },
  ],
}

// args: {question: "...", models?: {scout?}}, or the question as a plain string.
const question = typeof args === 'string' ? args : args && args.question
if (!question) return { error: 'no question given: pass args.question' }
const models = (args && typeof args === 'object' && args.models) || {}
const model = models.scout ? { model: models.scout } : {}
// The effort the profile gives a role and step (args.effort, from vbw next --json): the option
// for an agent call, or nothing when there is no table or no value (agents then run as before).
const table = (args && typeof args === 'object' && args.effort && typeof args.effort === 'object' && !Array.isArray(args.effort)) ? args.effort : {}
const effortOf = (role, step) => {
  const e = table[role] && typeof table[role] === 'object' ? table[role][step] : null
  return e ? { effort: e } : {}
}
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

const ANGLES = [
  { key: 'docs', ask: 'The official documentation and primary sources (the vendor\'s docs, changelogs, specifications).' },
  { key: 'practice', ask: 'Real-world practice: how projects and teams actually do this, with concrete examples and their pitfalls.' },
  { key: 'current', ask: 'What is current: versions, prices, limits, deprecations and recent changes, each with its date.' },
  { key: 'fit', ask: 'This project: what its code, .vbw/spec.md, recorded decisions (vbw show decisions) and .vbw/map.md mean for the answer.' },
]

const FINDINGS = {
  type: 'object',
  required: ['findings', 'confidence'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['finding', 'source'],
        properties: { finding: { type: 'string' }, source: { type: 'string' } },
      },
    },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
}

const ANSWER = {
  type: 'object',
  required: ['answer'],
  properties: { answer: { type: 'string' } },
}

phase('Research')
const found = await parallel(ANGLES.map(a => () =>
  agent(`Research this question from one angle.\n\nQuestion: ${question}\n\nYour angle: ${a.ask}${voice}`,
    Object.assign({ agentType: 'vbw:scout', label: `scout ${a.key}`, phase: 'Research', schema: FINDINGS }, model, effortOf('scout', 'survey')))))

const evidence = ANGLES.map((a, i) => ({ angle: a.key, report: found[i] }))
const missing = evidence.filter(e => !e.report || e.report.findings.length === 0).map(e => e.angle)
if (missing.length > 0) log(`no findings for: ${missing.join(', ')}`)

phase('Answer')
const answer = await agent(`Weigh these findings into one answer to the question, in plain words: what is true, the options with their trade-offs, your recommendation for this project, the sources (with links), and what could not be confirmed. Prefer primary and recent sources. Change nothing.\n\nQuestion: ${question}\n\nFindings: ${JSON.stringify(evidence)}${voice}`,
  Object.assign({ agentType: 'vbw:scout', label: 'scout answer', phase: 'Answer', schema: ANSWER }, model, effortOf('scout', 'merge')))

return { answer: answer ? answer.answer : null, missing }
