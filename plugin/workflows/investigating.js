export const meta = {
  name: 'investigating',
  description: 'VBW: Debuggers investigate a bug from three angles in parallel and diagnose its root cause; with a diagnosis given, one Debugger fixes it',
  whenToUse: 'Started by /vbw:debug with a description of the problem, and again with the diagnosis once the user wants it fixed',
  phases: [
    { title: 'Investigate', detail: 'a Debugger per angle: reproduce, trace, history' },
    { title: 'Diagnose', detail: 'one Debugger weighs the evidence into a root cause' },
    { title: 'Fix', detail: 'one Debugger: minimal fix, regression test, verify' },
  ],
}

// args: {problem: "...", models?: {debugger?}} to investigate, or the problem as
// a plain string; {problem, fix: <the diagnosis returned before>, models?} to fix.
const problem = typeof args === 'string' ? args : args && args.problem
if (!problem) return { error: 'no problem given: pass args.problem' }
const models = (args && typeof args === 'object' && args.models) || {}
const model = models.debugger ? { model: models.debugger } : {}
const fix = args && typeof args === 'object' ? args.fix : null
// The user's level, explanation depth and involvement (args.profile, from vbw next --json):
// every agent writes what reaches the user at that level.
const profile = (args && typeof args === 'object' && args.profile) || {}
const voice = `\n\nThe user's level: ${profile.level || 'small scripts or no-code'}. Explanation depth: ${profile.depth || 'plain with technical terms explained'}. Involvement: ${profile.involvement || 'options with a recommendation'}. Write whatever the user will read at that level and depth.`

const DONE = {
  type: 'object',
  required: ['status', 'summary', 'root_cause', 'files', 'commit', 'regression_test'],
  properties: {
    status: { type: 'string', enum: ['fixed', 'not_fixed'] },
    summary: { type: 'string' },
    root_cause: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    commit: { type: 'string' },
    regression_test: { type: 'string' },
    pre_existing: { type: 'array', items: { type: 'string' } },
  },
}

if (fix) {
  phase('Fix')
  const done = await agent(`Fix mode (steps 5 to 7). Fix this bug at its root cause, add a regression test, verify, and document.\n\nProblem: ${problem}\n\nDiagnosis: ${JSON.stringify(fix)}${voice}`,
    Object.assign({ agentType: 'vbw:debugger', label: 'debugger fix', phase: 'Fix', schema: DONE }, model))
  return { fixed: done }
}

const LENSES = [
  { key: 'reproduce', ask: 'Reproduce it: find the smallest command or test that shows the problem, run it, and report the exact steps and output (or that it does not reproduce).' },
  { key: 'trace', ask: 'Trace the code path involved, from the entry point to where the behavior goes wrong: name the exact place and why.' },
  { key: 'history', ask: 'Check the recent changes (git log, git show, git blame of the files involved) for what introduced or touched this behavior.' },
]

const EVIDENCE = {
  type: 'object',
  required: ['hypotheses'],
  properties: {
    reproduction: { type: 'string' },
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        required: ['cause', 'evidence_for', 'evidence_against', 'confidence'],
        properties: {
          cause: { type: 'string' },
          evidence_for: { type: 'string' },
          evidence_against: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}
const DIAGNOSIS = {
  type: 'object',
  required: ['root_cause', 'evidence', 'confidence', 'rejected', 'fix', 'unknowns'],
  properties: {
    root_cause: { type: 'string' },
    evidence: { type: 'string' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    rejected: { type: 'array', items: { type: 'string' } },
    fix: { type: 'string' },
    unknowns: { type: 'array', items: { type: 'string' } },
  },
}

phase('Investigate')
const reports = await parallel(LENSES.map(l => () =>
  agent(`Investigation mode (steps 1 to 4), from one angle only. Change nothing.\n\nProblem: ${problem}\n\nYour angle: ${l.ask}${voice}`,
    Object.assign({ agentType: 'vbw:debugger', label: `debugger ${l.key}`, phase: 'Investigate', schema: EVIDENCE }, model))))

const evidence = LENSES.map((l, i) => ({ angle: l.key, report: reports[i] }))

phase('Diagnose')
const diagnosis = await agent(`Investigation mode, step 4: weigh this evidence into the root cause. Prefer causes with reproduced or traced evidence; check the deciding fact yourself before you conclude; list the hypotheses you rejected and why. Propose the minimal fix for the root cause, not the symptom. Change nothing.\n\nProblem: ${problem}\n\nEvidence: ${JSON.stringify(evidence)}${voice}`,
  Object.assign({ agentType: 'vbw:debugger', label: 'debugger diagnose', phase: 'Diagnose', schema: DIAGNOSIS }, model))

return { diagnosis, evidence }
