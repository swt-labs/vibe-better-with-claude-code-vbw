export const meta = {
  name: 'investigating',
  description: 'VBW: investigate a bug from three angles in parallel, then weigh the evidence into a root cause and a proposed fix',
  whenToUse: 'Started by /vbw:debug with a description of the problem',
  phases: [
    { title: 'Investigate', detail: 'reproduce, trace the code, check recent changes' },
    { title: 'Judge', detail: 'weigh the evidence into one root cause' },
  ],
}

// args: {problem: "...", models?: {critic?, planner?}}, or the problem as a plain string
const problem = typeof args === 'string' ? args : args && args.problem
if (!problem) return { error: 'no problem given: pass args.problem' }
const models = (args && typeof args === 'object' && args.models) || {}

const LENSES = [
  { key: 'reproduce', ask: 'Reproduce it: find the smallest command or test that shows the problem, and run it. Report the exact steps and output, or that it does not reproduce.' },
  { key: 'trace', ask: 'Trace the code path involved, from the entry point to where the behavior goes wrong. Name the exact place and why.' },
  { key: 'history', ask: 'Check recent changes (git log, git diff of the relevant files) for what introduced or touched this behavior.' },
]

const EVIDENCE = {
  type: 'object',
  required: ['hypotheses'],
  properties: {
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        required: ['cause', 'evidence', 'confidence'],
        properties: {
          cause: { type: 'string' },
          evidence: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}
const VERDICT = {
  type: 'object',
  required: ['root_cause', 'evidence', 'confidence', 'fix', 'unknowns'],
  properties: {
    root_cause: { type: 'string' },
    evidence: { type: 'string' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    fix: { type: 'string' },
    unknowns: { type: 'array', items: { type: 'string' } },
  },
}

phase('Investigate')
const reports = await parallel(LENSES.map(l => () =>
  agent(`Investigate this problem from one angle.\n\nProblem: ${problem}\n\nYour angle: ${l.ask}`,
    Object.assign({ agentType: 'vbw:scout', label: l.key, phase: 'Investigate', schema: EVIDENCE },
      models.critic ? { model: models.critic } : {}))))

const evidence = LENSES.map((l, i) => ({ angle: l.key, hypotheses: reports[i] ? reports[i].hypotheses : [] }))

phase('Judge')
const verdict = await agent(`Weigh this evidence about a bug and decide the most likely root cause. Prefer causes with reproduced or traced evidence; check the deciding fact yourself before you conclude. Propose the smallest fix that removes the cause (not the symptom). Change nothing.\n\nProblem: ${problem}\n\nEvidence: ${JSON.stringify(evidence)}`,
  Object.assign({ agentType: 'vbw:scout', label: 'judge', phase: 'Judge', schema: VERDICT },
    models.planner ? { model: models.planner } : {}))

return { verdict, evidence }
