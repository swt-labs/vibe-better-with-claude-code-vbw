export const meta = {
  name: 'fix',
  description: 'VBW: work the open fix items in parallel, each scoped to the files of the plans serving it',
  whenToUse: 'Started by /vbw:vibe when vbw next says fix, inside a vbw run start fix lease',
  phases: [{ title: 'Fix', detail: 'one builder per fix item' }],
}

// args: {fixes: ["F1", ...], models?: {builder?}} (docs/workflows.md)
const fixes = (args && args.fixes) || []
const models = (args && args.models) || {}
if (fixes.length === 0) return { results: [], error: 'no fixes given: pass args.fixes from vbw next --json' }

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
const results = await pipeline(fixes, id =>
  agent(`Fix VBW fix item ${id}. Start with: vbw show fix ${id}`,
    Object.assign({ agentType: 'vbw:builder', label: id, phase: 'Fix', schema: FIX_RESULT },
      models.builder ? { model: models.builder } : {})))

const out = fixes.map((id, i) => results[i]
  ? Object.assign({ fix: id }, results[i])
  : { fix: id, status: 'interrupted', summary: 'the builder stopped before reporting', notes: [] })
const interrupted = out.filter(r => r.status === 'interrupted').length
if (interrupted > 0) log(`${interrupted} fixer(s) stopped before reporting; their fixes stay open`)
return { results: out }
