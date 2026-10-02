export const meta = {
  name: 'verifying',
  description: 'VBW: QA verifies each built phase goal-backward against its goal, criteria and plans, and records findings and a verdict',
  whenToUse: 'Started by /vbw:vibe when vbw next says qa',
  phases: [{ title: 'Verify', detail: 'one QA agent per phase, in parallel' }],
}

// args: {phases: ["P1", ...], tier: "quick"|"standard"|"deep", models?: {qa?}} (docs/workflows.md).
const phases = (args && args.phases) || []
const tier = (args && args.tier) || 'standard'
const models = (args && args.models) || {}
if (phases.length === 0) return { results: [], error: 'no phases given: pass args.phases from vbw next --json' }

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

phase('Verify')
const results = await pipeline(phases, id =>
  agent(`Verify VBW phase ${id} at the ${tier} tier, then record your findings and verdict with vbw qa (if qa record refuses a stale proof, run vbw prove, then retry the record once). Start with: vbw show phase ${id}`,
    Object.assign({ agentType: 'vbw:qa', label: `qa ${id}`, phase: 'Verify', schema: VERDICT },
      models.qa ? { model: models.qa } : {})))

const out = phases.map((id, i) => results[i]
  ? Object.assign({ phase: id }, results[i])
  : { phase: id, verdict: 'interrupted', checks: [], summary: 'QA stopped before reporting' })
const failed = out.filter(r => r.verdict !== 'pass').length
if (failed > 0) log(`${failed} phase(s) did not pass QA`)
return { tier, results: out }
