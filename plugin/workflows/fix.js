export const meta = {
  name: 'fix',
  description: 'VBW: work the open fix items, one builder per group of fixes that share files, groups in parallel',
  whenToUse: 'Started by /vbw:vibe when vbw next says fix, inside a vbw run start fix lease',
  phases: [{ title: 'Fix', detail: 'one builder per group of fixes; groups have disjoint files' }],
}

// args: {groups: [["F1", "F3"], ["F2"]], models?: {builder?}} (docs/workflows.md).
// Fixes in one group share files, so one builder works them together.
const groups = ((args && args.groups) || []).filter(g => Array.isArray(g) && g.length > 0)
const models = (args && args.models) || {}
if (groups.length === 0) return { results: [], error: 'no fix groups given: pass args.groups from vbw next --json (detail.groups)' }

const FIX_RESULT = {
  type: 'object',
  required: ['status', 'summary', 'notes'],
  properties: {
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string' },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

phase('Fix')
const results = await pipeline(groups, ids =>
  agent(ids.length === 1
    ? `Fix VBW fix item ${ids[0]}. Start with: vbw show fix ${ids[0]}`
    : `Fix VBW fix items ${ids.join(', ')} together: they touch the same files and may share one cause. Start with: ${ids.map(id => `vbw show fix ${id}`).join('; ')}`,
    Object.assign({ agentType: 'vbw:builder', label: ids.join('+'), phase: 'Fix', schema: FIX_RESULT },
      models.builder ? { model: models.builder } : {})))

const out = groups.map((ids, i) => results[i]
  ? Object.assign({ fixes: ids }, results[i])
  : { fixes: ids, status: 'interrupted', summary: 'the builder stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} fixer(s) stopped before reporting; their fixes stay open`)
return { results: out }
