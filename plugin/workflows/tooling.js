export const meta = {
  name: 'tooling',
  description: 'VBW: one Scout per angle (safety, quality, tests, skills) looks for the best tools for the project, then a short sourced list is kept',
  whenToUse: 'Started by /vbw:skills (and the interview) after the user agreed to a tool search',
  phases: [{ title: 'Scout', detail: 'a Scout per angle, in parallel' }],
}

// args: {stack: "...", profile?: {level, depth, involvement}, models?: {scout?}}.
const stack = args && typeof args === 'object' && typeof args.stack === 'string' ? args.stack.trim() : ''
const models = (args && typeof args === 'object' && args.models) || {}
const model = models.scout ? { model: models.scout } : {}
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

const ANGLES = [
  { key: 'safety', ask: 'automated code-safety scanners: security and vulnerability scanners, dependency audits and secret detection' },
  { key: 'quality', ask: 'code-quality tools: linters, formatters and type checkers' },
  { key: 'tests', ask: 'unit-test and other test frameworks and runners (integration, end-to-end, coverage)' },
  { key: 'skills', ask: 'community Claude Code skills and plugins that help with this stack' },
]

const PICKS = {
  type: 'object',
  required: ['picks'],
  properties: {
    picks: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'what', 'why', 'sources', 'origin'],
        properties: {
          name: { type: 'string' },
          what: { type: 'string' },
          why: { type: 'string' },
          sources: { type: 'array', items: { type: 'string' } },
          origin: { type: 'string', enum: ['respected-open-source', 'other'] },
        },
      },
    },
  },
}

const WARNING = 'Not from a respected open-source project: check who maintains it and read what it does before you approve it.'
const PER_ANGLE = 2
const TOTAL = 6

if (!stack) {
  return { picks: [], missing: [], note: 'The project\'s stack is not known yet, so no tool search was started. Say what is being built and run it again.' }
}

phase('Scout')
const found = await Promise.all(ANGLES.map(a =>
  agent(`Find the current best-in-class options for one angle of this project: ${a.ask}.\n\nProject stack: ${stack}\n\nReturn at most ${PER_ANGLE} picks, each with what it is, why it fits this stack, one or more source links (https), and its origin: "respected-open-source" only for a well-known, actively maintained open-source project, otherwise "other". Prefer current, widely used options. Install nothing and change nothing.${voice}`,
    Object.assign({ agentType: 'vbw:scout', label: `scout ${a.key}`, phase: 'Scout', schema: PICKS }, model))
    .catch(() => null)))

const missing = []
let picks = []
ANGLES.forEach((a, i) => {
  const r = found[i]
  const kept = ((r && Array.isArray(r.picks)) ? r.picks : [])
    .filter(p => p && p.name && Array.isArray(p.sources) && p.sources.some(s => /^https?:\/\//.test(s)))
    .map(p => {
      const trusted = p.origin === 'respected-open-source'
      const out = { angle: a.key, name: p.name, what: p.what, why: p.why, origin: p.origin, trusted, sources: p.sources.filter(s => /^https?:\/\//.test(s)) }
      if (!trusted) out.warning = WARNING
      return out
    })
    .sort((x, y) => Number(y.trusted) - Number(x.trusted))
    .slice(0, PER_ANGLE)
  if (kept.length === 0) missing.push(a.key)
  picks = picks.concat(kept)
})
picks = picks.sort((x, y) => Number(y.trusted) - Number(x.trusted)).slice(0, TOTAL)

if (missing.length > 0) log(`no picks for: ${missing.join(', ')}`)
const result = { picks, missing }
if (picks.length === 0) result.note = 'No tools could be found right now. Nothing was installed; you can run the search again later.'
return result
