// VBW's one-line surfaces and transcript rows (mods_4_vbw.md §2, §3.4, §3.5):
// plugin/hooks/panel-lines.js turns the record, the last `vbw next` and the run
// model into the spinner suffix, the hint tail, the footer modes, the startup
// notice, the question header, the turn receipt, the Workflow run card, the run
// receipt and the `vbw` row intentions. Pure: data in, a string out, null to
// leave the engine's own (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, deepFreeze } from './helpers/fake-mod.mjs'

const L = await import(pathToFileURL(PLUGIN + '/hooks/panel-lines.js').href)
const NOW = Date.parse('2026-10-07T16:43:00Z')
const MIN = 60000

const run = (over = {}) => deepFreeze({ runId: 'wf_1', kind: 'planning', phase: null, startedAt: NOW - 10 * MIN, endedAt: null, status: 'running', agents: [], ...over })
const building = () => deepFreeze(record({
  milestone: { id: 'M11', title: 'Faster', status: 'active' },
  phases: [{ id: 'P53', title: 'Build', milestone: 'M11' }, { id: 'P54', title: 'Other', milestone: 'M11' }],
  plans: [
    { id: 'P53.1', phase: 'P53', status: 'done' },
    { id: 'P53.2', phase: 'P53', status: 'building' },
    { id: 'P53.3', phase: 'P53', status: 'planned' },
    { id: 'P53.4', phase: 'P53', status: 'planned' },
    { id: 'P53.5', phase: 'P53', status: 'planned' },
    { id: 'P54.1', phase: 'P54', status: 'planned' },
  ],
}))

test('spinner suffix names the plan being built and where it is in its phase', () => {
  assert.equal(L.spinnerSuffix({ run: run({ kind: 'building' }), record: building() }), ' · VBW building P53.2 (2/5)…')
})

test('spinner suffix for other runs names the kind and the workflow phase', () => {
  assert.equal(L.spinnerSuffix({ run: run(), record: building() }), ' · VBW planning…')
  assert.equal(L.spinnerSuffix({ run: run({ kind: 'verifying', phase: 'Verify' }), record: null }), ' · VBW verifying · Verify…')
})

test('spinner suffix is null when no VBW run is live', () => {
  assert.equal(L.spinnerSuffix({ run: null, record: building() }), null)
  assert.equal(L.spinnerSuffix({ run: run({ status: 'completed', endedAt: NOW }), record: building() }), null)
  assert.equal(L.spinnerSuffix(undefined), null)
})

test('hint tail: the gate first, then the run with its time, else the next step', () => {
  const rec = record()
  assert.equal(L.hintTail({ record: rec, next: next({ action: 'approve', gate: true }), run: null, now: NOW }), 'VBW needs you: /vbw:approve')
  assert.equal(L.hintTail({ record: rec, next: next({ action: 'accept', gate: true }), run: null, now: NOW }), 'VBW needs you: /vbw:verify')
  assert.equal(L.hintTail({ record: rec, next: next({ action: 'ship', gate: true }), run: null, now: NOW }), 'VBW needs you: /vbw:vibe')
  assert.equal(L.hintTail({ record: rec, next: next(), run: run(), now: NOW }), 'VBW: planning 10m')
  assert.equal(L.hintTail({ record: rec, next: next(), run: run({ startedAt: NOW - 20000 }), now: NOW }), 'VBW: planning 20s')
  assert.equal(L.hintTail({ record: rec, next: next(), run: null, now: NOW }), 'VBW next: /vbw:vibe')
  assert.equal(L.hintTail({ record: rec, next: null, run: null, now: NOW }), 'VBW next: /vbw:vibe')
})

test('hint tail is null outside a VBW project', () => {
  assert.equal(L.hintTail({ record: null, next: next({ action: 'approve', gate: true }), run: null, now: NOW }), null)
  assert.equal(L.hintTail({}), null)
})

test('footer modes: autonomous run armed, else the profile in plain words', () => {
  assert.deepEqual(L.sessionModes({ modes: ['plan mode'], autonomy: { armed: true, step: 3, cap: 10 }, profile: 'balanced' }), ['plan mode', 'VBW auto ⟳ 3/10'])
  assert.deepEqual(L.sessionModes({ modes: [], autonomy: { armed: false, step: 0, cap: 10 }, profile: 'quality' }), ['VBW careful'])
  assert.deepEqual(L.sessionModes({ modes: [], autonomy: null, profile: 'balanced' }), ['VBW standard'])
  assert.deepEqual(L.sessionModes({ modes: [], autonomy: null, profile: 'budget' }), ['VBW fast'])
})

test('footer modes never duplicate a VBW label and never change the input', () => {
  const modes = deepFreeze(['VBW standard', 'accept edits'])
  assert.deepEqual(L.sessionModes({ modes, autonomy: { armed: true, step: 4, cap: 10 }, profile: 'balanced' }), ['accept edits', 'VBW auto ⟳ 4/10'])
  assert.deepEqual(L.sessionModes({ modes, autonomy: null, profile: 'balanced' }), ['accept edits', 'VBW standard'])
  assert.equal(L.sessionModes({ modes: [], autonomy: null, profile: 'unknown' }), null)
  assert.equal(L.sessionModes({ modes: 'x' }), null)
})

const m11 = () => deepFreeze(record({
  milestone: { id: 'M11', title: 'Faster', status: 'active' },
  requirements: [
    { id: 'R1', milestone: 'M1', status: 'proven' },
    { id: 'R70', milestone: 'M11', status: 'proven' },
    { id: 'R71', milestone: 'M11', status: 'accepted' },
    { id: 'R72', milestone: 'M11', status: 'pending' },
    { id: 'R73', milestone: 'M11' },
  ],
}))

test('startup notice: milestone, requirements proven or accepted of total, next command', () => {
  assert.equal(L.infoNotice({ record: m11(), next: next() }), 'VBW M11 · 2/4 · next: /vbw:vibe')
  assert.equal(L.infoNotice({ record: m11(), next: next({ action: 'approve', gate: true }) }), 'VBW M11 · 2/4 · next: /vbw:approve')
  assert.equal(L.infoNotice({ record: null, next: next() }), null)
})

test('question header numbers the decision for the milestone', () => {
  assert.equal(L.questionHeader({ record: m11(), decisionIndex: 2, decisionCount: 4 }), 'VBW · decision 2 of 4 for M11')
  assert.equal(L.questionHeader({ record: m11() }), 'VBW · a decision for M11')
  assert.equal(L.questionHeader({ record: null, decisionIndex: 1, decisionCount: 1 }), null)
})

test('turn receipt names the VBW step that changed and the time', () => {
  const before = m11()
  const approved = { ...before, decisions: [{ id: 'D1', text: 'Contract approved: 4 requirements, 3 checks, 2 plans (abc)' }] }
  assert.equal(L.turnReceipt({ before, after: approved, ms: 3000 }), 'VBW · plan approved · 3s')
  const b = building()
  const done = { ...b, plans: b.plans.map((p) => (p.id === 'P53.2' ? { ...p, status: 'done' } : p)) }
  assert.equal(L.turnReceipt({ before: b, after: done, ms: 64000 }), 'VBW · P53.2 done · 1m 4s')
  const proven = { ...before, requirements: before.requirements.map((r) => (r.id === 'R72' ? { ...r, status: 'proven' } : r)) }
  assert.equal(L.turnReceipt({ before, after: proven, ms: 5000 }), 'VBW · R72 proven · 5s')
  const shipped = { ...before, milestone: { ...before.milestone, status: 'shipped' } }
  assert.equal(L.turnReceipt({ before, after: shipped, ms: 2000 }), 'VBW · M11 shipped · 2s')
})

test('turn receipt is null when no VBW step changed', () => {
  assert.equal(L.turnReceipt({ before: m11(), after: m11(), ms: 3000 }), null)
  assert.equal(L.turnReceipt({ before: null, after: m11(), ms: 3000 }), null)
})

test('Workflow row: a VBW run card with the start time and the watch key', () => {
  const at = NOW - 10 * MIN
  const hhmm = new Date(at).toTimeString().slice(0, 5)
  assert.equal(L.workflowCard({ input: { name: 'vbw:planning' }, run: run({ startedAt: at }) }), 'VBW planning · started ' + hhmm + ' · [p] watch live')
  const script = "export const meta = { name: 'vbw:building', description: 'x', phases: [] }\n"
  assert.equal(L.workflowCard({ input: { script }, run: null }), 'VBW building · [p] watch live')
  assert.equal(L.workflowCard({ input: { workflowName: 'vbw:fixing' }, run: run({ kind: 'fixing', status: 'completed', endedAt: NOW }) }), 'VBW fixing · started ' + hhmm + ' · finished')
})

test('Workflow row that is not VBW keeps the engine row', () => {
  assert.equal(L.workflowCard({ input: { name: 'deep-research' }, run: null }), null)
  assert.equal(L.workflowCard({ input: { script: "export const meta = { name: 'planning' }" }, run: null }), null)
  assert.equal(L.workflowCard({ input: null, run: null }), null)
})

const planned = () => deepFreeze(record({
  milestone: { id: 'M11', title: 'Faster', status: 'active' },
  requirements: [{ id: 'R70', milestone: 'M11' }, { id: 'R71', milestone: 'M11' }, { id: 'R1', milestone: 'M1' }],
  phases: [{ id: 'P53', milestone: 'M11', qa: { result: 'pass' } }, { id: 'P54', milestone: 'M11' }, { id: 'P1', milestone: 'M1' }],
  plans: [{ id: 'P53.1', phase: 'P53', status: 'done' }, { id: 'P53.2', phase: 'P53', status: 'done' }, { id: 'P54.1', phase: 'P54', status: 'planned' }, { id: 'P1.1', phase: 'P1', status: 'done' }],
  checks: [{ id: 'C1', req: 'R70' }, { id: 'C2', req: 'R71' }, { id: 'C3', req: 'R1' }],
}))

test('run receipt: what the run produced, its time and its cost', () => {
  const final = { workflowName: 'planning', status: 'completed', durationMs: 14 * MIN + 2000 }
  assert.equal(L.runReceipt({ final, record: planned(), cost: 4.1 }), '✓ VBW planning finished · 2 phases · 3 plans · 2 checks · 14m · ≈$4.10')
  assert.equal(L.runReceipt({ final: { ...final, workflowName: 'vbw:building' }, record: planned(), cost: null }), '✓ VBW building finished · 2 of 3 plans done · 14m')
  assert.equal(L.runReceipt({ final: { ...final, workflowName: 'verifying', durationMs: 45000 }, record: planned() }), '✓ VBW verifying finished · 1 of 2 phases passed · 45s')
  assert.equal(L.runReceipt({ final: { ...final, status: 'failed', durationMs: 3 * MIN }, record: planned(), cost: 0.5 }), '✗ VBW planning failed · 3m · ≈$0.50')
  assert.equal(L.runReceipt({ final: { ...final, workflowName: 'mapping', durationMs: 65 * MIN }, record: planned() }), '✓ VBW mapping finished · 1h 5m')
})

test('run receipt is null for other workflows or outside a VBW project', () => {
  assert.equal(L.runReceipt({ final: { workflowName: 'deep-research', status: 'completed', durationMs: 1000 }, record: planned() }), null)
  assert.equal(L.runReceipt({ final: { workflowName: 'planning', status: 'completed', durationMs: 1000 }, record: null }), null)
  assert.equal(L.runReceipt({}), null)
})

test('vbw Bash rows read as what VBW did', () => {
  const i = (command) => L.vbwRowIntent({ command })
  assert.equal(i('vbw plan done P53.1'), 'VBW · recorded P53.1 done')
  assert.equal(i('"${CLAUDE_PLUGIN_ROOT}/bin/vbw" plan done P53.1'), 'VBW · recorded P53.1 done')
  assert.equal(i('"/Users/x/My Plugins/vbw/bin/vbw" run start plan'), 'VBW · plan run started')
  assert.equal(i('vbw run start build P53.1 P53.2'), 'VBW · build run started: P53.1, P53.2')
  assert.equal(i('vbw run end'), 'VBW · run closed')
  assert.equal(i('vbw qa record P55 pass deep "12/12 checks"'), 'VBW · P55 passed QA')
  assert.equal(i('vbw qa record P55 fail standard'), 'VBW · P55 failed QA')
  assert.equal(i('vbw prove'), 'VBW · proving the checks')
  assert.equal(i('vbw apply < /dev/stdin'), 'VBW · recorded the plan')
  assert.equal(i('cd /proj && vbw next --json'), 'VBW · reading the next step')
  assert.equal(i('vbw fix done F3 F4'), 'VBW · recorded F3, F4 fixed')
  assert.equal(i('vbw req accept R9'), 'VBW · recorded R9 accepted')
  assert.equal(i('vbw frobnicate'), 'VBW · frobnicate')
})

test('non-vbw Bash rows keep the engine row', () => {
  assert.equal(L.vbwRowIntent({ command: 'ls -la' }), null)
  assert.equal(L.vbwRowIntent({ command: 'grep vbw README.md' }), null)
  assert.equal(L.vbwRowIntent({ command: 'cat bin/vbwx' }), null)
  assert.equal(L.vbwRowIntent({}), null)
})

test('record diffs read as what changed', () => {
  const lease = '@@ -1 +1 @@\n-  "lease": null,\n+  "lease": {\n+    "run": "plan-1",\n+    "kind": "plan",\n'
  assert.equal(L.recordDiffIntent(lease), 'VBW · plan run started')
  assert.equal(L.recordDiffIntent('-  "lease": {\n-    "kind": "build",\n+  "lease": null,\n'), 'VBW · run closed')
  assert.equal(L.recordDiffIntent('-      "status": "building"\n+      "status": "done"\n'), 'VBW · recorded a plan done')
  assert.equal(L.recordDiffIntent('+      "text": "Contract approved: 3 requirements"\n'), 'VBW · plan approved')
  assert.equal(L.recordDiffIntent(' "schema": 2\n+  "todos": []\n'), 'VBW · record updated')
  assert.equal(L.recordDiffIntent(''), null)
  assert.equal(L.recordDiffIntent(null), null)
})

test('bad input never throws: every function answers null', () => {
  const bad = [undefined, null, 0, 'x', [], {}, { record: 'x', run: 5, next: [] }, { record: { milestone: {} } }]
  const fns = ['spinnerSuffix', 'hintTail', 'sessionModes', 'infoNotice', 'questionHeader', 'turnReceipt', 'workflowCard', 'runReceipt', 'vbwRowIntent', 'recordDiffIntent']
  for (const f of fns) for (const b of bad) {
    const out = L[f](b)
    assert.ok(out === null || (f === 'recordDiffIntent' && b === 'x'), f + '(' + JSON.stringify(b) + ') -> ' + JSON.stringify(out))
  }
})
