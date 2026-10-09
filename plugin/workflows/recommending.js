export const meta = {
  name: 'recommending',
  description: 'VBW: the Architect reads the record and recommends what to do next: one top pick and up to two runners-up, each with a size',
  whenToUse: 'Started by /vbw:whats-next after a ship or when the user asks what is next',
  phases: [
    { title: 'Recommend', detail: 'one Architect call over the open requirements and the backlog' },
  ],
}

// args: {summary: vbw triage --json, declined: [text], models?: {architect?}, effort?, profile?}.
// Returns {recommendation: {top, runners}}, {recommendation: {empty: true}} or {error}.
const a = (args && typeof args === 'object') ? args : {}
const summary = a.summary || {}
const open = Array.isArray(summary.open) ? summary.open : []
const todos = Array.isArray(summary.todos) ? summary.todos : []
const declined = Array.isArray(a.declined) ? a.declined : []
const models = a.models || {}
const table = (a.effort && typeof a.effort === 'object' && !Array.isArray(a.effort)) ? a.effort : {}
const effort = table.architect && typeof table.architect === 'object' ? table.architect.recommend : null
const profile = a.profile || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

if (open.length === 0 && todos.length === 0) return { recommendation: { empty: true } }

const SCHEMA = {
  type: 'object',
  required: ['top', 'runners'],
  properties: {
    top: {
      type: 'object',
      required: ['text', 'reason', 'size'],
      properties: { text: { type: 'string' }, reason: { type: 'string' }, size: { type: 'string', enum: ['small', 'medium', 'large'] }, source: { type: 'string' } },
    },
    runners: {
      type: 'array',
      maxItems: 2,
      items: {
        type: 'object',
        required: ['text', 'size'],
        properties: { text: { type: 'string' }, size: { type: 'string', enum: ['small', 'medium', 'large'] }, source: { type: 'string' } },
      },
    },
  },
}

const reqLines = open.length ? open.map(r => `- ${r.id}: ${r.text}`).join('\n') : '(none)'
const todoLines = todos.length
  ? todos.map(t => `- ${t.id}: ${t.text} (sort: ${t.sort || 'unsorted'}, size: ${t.size || 'unsized'})`).join('\n')
  : '(none)'
const declinedLines = declined.length ? declined.map(d => `- ${d}`).join('\n') : '(none)'

phase('Recommend')
const opts = Object.assign({ agentType: 'vbw:architect', label: 'architect recommend', phase: 'Recommend', schema: SCHEMA },
  models.architect ? { model: models.architect } : {}, effort ? { effort } : {})
let got = null
try {
  got = await agent(`Job: what's next. Recommend what to do next from the record only: one top pick with a one-sentence reason and a size (small, medium or large), and up to two runners-up with sizes. Read \`vbw show decisions\` and follow every decision. Never pick work of a shipped milestone and never pick a declined suggestion. Name each pick's source (the T or R id below) when it has one. Invent nothing.\n\nOpen requirements:\n${reqLines}\n\nBacklog (sort and size):\n${todoLines}\n\nDeclined suggestions:\n${declinedLines}${voice}`, opts)
} catch (e) {
  return { error: `the Architect could not recommend: ${e && e.message ? e.message : e}` }
}
if (!got || !got.top) return { error: 'the Architect returned no recommendation' }
return { recommendation: { top: got.top, runners: Array.isArray(got.runners) ? got.runners.slice(0, 2) : [] } }
