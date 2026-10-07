// A VBW workflow run as Claude Code writes it, inside the stand-in of fake-mod.mjs:
// the session's folder under the Claude config folder, the run's journal, agent
// metas and transcripts, and the Workflow tool call that launched it (L1).
import { ROOT } from './fake-mod.mjs'
import { line, usage, jsonl } from './feed-fs.mjs'

export const HOME = '/home/u'
export const SESSION_ID = 'sess-1'
// Claude Code names a project's folder after its path, every other character a dash.
export const SESSION_DIR = HOME + '/.claude/projects/' + ROOT.replace(/[^A-Za-z0-9]/g, '-') + '/' + SESSION_ID
export const RUN = 'wf_0669fe8d-c12'
export const RUN_DIR = SESSION_DIR + '/subagents/workflows/' + RUN
export const FINAL = SESSION_DIR + '/workflows/' + RUN + '.json'
export const ARCH = 'a143aa'
export const LEAD = 'b276bb'
export const ENV = { HOME }

// Two agents at work: the architect reading the spec, the lead writing.
export function writeRun(h, at, over = {}) {
  h.write(RUN_DIR + '/journal.jsonl', jsonl([
    { type: 'launched' },
    { type: 'started', agentId: ARCH, label: 'architect scope', phase: 'Scope' },
    { type: 'started', agentId: LEAD, label: 'lead P53', phase: 'Plan' },
    ...(over.journal || []),
  ]))
  h.write(RUN_DIR + '/agent-' + ARCH + '.meta.json', { agentType: 'vbw:architect', description: 'architect scope', model: 'opus' })
  h.write(RUN_DIR + '/agent-' + LEAD + '.meta.json', { agentType: 'vbw:lead', description: 'lead P53', model: 'sonnet' })
  h.write(RUN_DIR + '/agent-' + ARCH + '.jsonl', jsonl([line.user(at - 5000), line.tool(at, 'Read', { file_path: ROOT + '/.vbw/spec.md' }, usage(10, 40000, 1000))]))
  h.write(RUN_DIR + '/agent-' + LEAD + '.jsonl', jsonl([line.user(at - 4000), line.text(at, 'Splitting R69 into two plans', usage(5, 18000, 0))]))
}

export const finish = (h, start, status = 'completed') =>
  h.write(FINAL, { workflowName: 'planning', status, startTime: start, durationMs: 840000, phases: [{ title: 'Scope' }, { title: 'Plan' }] })

// The Workflow tool call of /vbw:vibe, answered as Claude Code answers a launch.
export function launch(h, name = 'vbw:planning', id = 'tu-wf-1') {
  return h.fire('tool.call', { tool: 'Workflow', name, tool_use_id: id }, async () => ({
    result: { status: 'async_launched', taskId: 't1', taskType: 'local_workflow', workflowName: name.replace(/^vbw:/, ''), runId: RUN, transcriptDir: RUN_DIR },
  }))
}

// The band above the prompt, as Claude Code asks for it.
export const band = (h, props = {}) =>
  h.draw('AbovePrompt', { hasSurvey: false, isWorking: true, maxRows: 12, bodyColumns: 100, scroll: { offset: 0, bodyRows: 12 }, ...props })
