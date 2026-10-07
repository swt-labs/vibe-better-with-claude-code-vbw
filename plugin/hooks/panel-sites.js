// What VBW says at every place but the pane (mods_4_vbw.md §2, §3.4-§3.5): the
// spinner, the hint line, the footer modes, the startup notice, the question
// header, and the transcript's turn, Workflow, `vbw` and notification rows. Pure
// over the state panel.js gathered (no `$`: Claude Code follows `$` into functions
// of the hooks' own file only): each answers null (the engine draws its own),
// { props } (the engine's, rewritten), { text, dim } (one line in the row's place)
// or { line, below } (one VBW line above, or below, the engine's own). Transcript
// rows are text only, and a row's words are kept for that row (st.memo), so a
// redraw never changes what it said.
import { spinnerSuffix, hintTail, sessionModes, infoNotice, questionHeader, turnReceipt, workflowCard, runReceipt, vbwRowIntent, recordEditIntent } from './panel-lines.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const props = (e) => (isObj(e) && isObj(e.props) ? e.props : {})
const live = (st) => ({ run: st.run, record: st.record, next: st.next })
const textOr = (text) => (text ? { text } : null)

// A finished run as runReceipt reads it: the run model's end in the final json's words.
const finalOf = (run) => (isObj(run) && run.status !== 'running'
  ? { workflowName: run.kind, status: run.status, durationMs: Number.isFinite(run.endedAt) && Number.isFinite(run.startedAt) ? run.endedAt - run.startedAt : null }
  : null)
// The cost of the run that closed last (Costs' lease bookkeeping), or null.
const lastCost = (st) => {
  const l = st.leases.filter((x) => x.costEnd !== undefined).pop()
  return l && Number.isFinite(l.costStart) && Number.isFinite(l.costEnd) ? l.costEnd - l.costStart : null
}
// A row's words, worked out at most once for that row and kept ('' for none).
const once = (st, e, make) => {
  const id = String(e.component) + ':' + String(e.requestId)
  if (st.memo[id] === undefined) st.memo[id] = make() || ''
  return st.memo[id] || null
}

// True when a TurnDuration row has no words yet and a turn's start is known:
// panel.js reads the record afresh first.
export const turnPending = (st, e) => st.memo['TurnDuration:' + e.requestId] === undefined && Boolean(st.before)

export const SITES = {
  Spinner: (st) => {
    const suffix = spinnerSuffix(live(st))
    return suffix ? { props: { suffix } } : null
  },
  PromptHint: (st, e, now) => {
    const tail = hintTail({ ...live(st), now })
    return tail ? { props: { tail } } : null
  },
  SessionMode: (st, e) => {
    const a = isObj(st.auto) ? { armed: true, step: st.auto.steps, cap: st.auto.cap } : null
    const profile = isObj(st.record) && isObj(st.record.settings) && st.record.settings.profile ? st.record.settings.profile : 'balanced'
    const modes = sessionModes({ modes: props(e).modes, autonomy: a, profile })
    return modes ? { props: { modes } } : null
  },
  // Once: under the first notice Claude Code draws at startup.
  InfoNotice: (st, e) => {
    if (st.notice === null) st.notice = e.requestId
    if (st.notice !== e.requestId) return null
    const line = once(st, e, () => infoNotice(live(st)))
    return line ? { line, below: true } : null
  },
  AskUserQuestion: (st) => {
    const line = questionHeader({ record: st.record })
    return line ? { line } : null
  },
  // After a turn that moved VBW on: what moved, and how long the turn took.
  TurnDuration: (st, e) => {
    const text = once(st, e, () => {
      if (!st.before) return null
      const t = turnReceipt({ before: st.before, after: st.record, ms: props(e).durationMs })
      st.before = st.record
      return t
    })
    return text ? { text, dim: true } : null
  },
  // The Workflow row of a VBW run as a run card; a `vbw` command's row as what VBW
  // did (its result row below stays the engine's).
  ToolUse: (st, e) => {
    const p = props(e)
    if (p.isErrored) return null
    if (p.tool === 'Workflow') return textOr(workflowCard({ input: p.input, run: st.run }))
    if (p.tool === 'Edit' || p.tool === 'MultiEdit' || p.tool === 'Write') return p.isExpanded ? null : textOr(recordEditIntent({ tool: p.tool, input: p.input }))
    return textOr(p.tool === 'Bash' && isObj(p.input) ? vbwRowIntent({ command: p.input.command }) : null)
  },
  // The notification of this session's VBW run ending: the run receipt. Kept once
  // made; until then (the timer has not seen the run end) the engine's row.
  UserMessage: (st, e) => {
    const p = props(e)
    if (p.isExpanded || !isObj(p.origin) || p.origin.kind !== 'task-notification' || !isObj(p.task)) return null
    const id = 'UserMessage:' + e.requestId
    const runId = st.toolRuns[p.task.toolUseId]
    if (!st.memo[id] && runId && isObj(st.run) && st.run.runId === runId) {
      st.memo[id] = runReceipt({ final: finalOf(st.run), record: st.record, cost: lastCost(st) }) || undefined
    }
    return st.memo[id] ? { text: st.memo[id] } : null
  },
}
