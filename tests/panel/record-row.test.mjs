// R88: when Claude Code shows a change to .vbw/record.json in the conversation,
// VBW shows one line saying what happened (VBW · build run started) instead of
// the full diff; the full diff still shows when the user expands the row. A
// change with no known meaning gets a generic line; other files are untouched.
// Driven through the stand-in for Claude Code's mods API (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, collect, PLUGIN, ROOT } from './helpers/fake-mod.mjs'
import { ENV } from './helpers/run.mjs'

const lines = await import(pathToFileURL(PLUGIN + '/hooks/panel-lines.js').href)

const RECORD = ROOT + '/.vbw/record.json'
const text = (tree) => collect(tree).join('\n')
const isEngine = (x, component) => x && x.type === 'engine' && x.ref === component

async function started() {
  const h = await mount({ env: ENV })
  h.project(record(), next())
  await h.start()
  await h.settle()
  return h
}
const row = (h, tool, input, over = {}) => h.draw('ToolUse', { tool_use_id: 'e1', tool, input, isRunning: false, isErrored: false, isInterrupted: false, ...over })
const edit = (oldText, newText, file = RECORD) => ({ file_path: file, old_string: oldText, new_string: newText })
const LEASE_OLD = '  "lease": null,'
const LEASE_NEW = '  "lease": {\n    "run": "build-1",\n    "kind": "build",\n    "started_at": "2026-10-07T10:00:00Z"\n  },'

test('an Edit of the record that opens a build run reads VBW · build run started, one line', async () => {
  const h = await started()
  const out = await row(h, 'Edit', edit(LEASE_OLD, LEASE_NEW))
  assert.equal(text(out), 'VBW · build run started')
})

test('the other known changes read as what happened', async () => {
  const h = await started()
  assert.equal(text(await row(h, 'Edit', edit(LEASE_NEW, LEASE_OLD))), 'VBW · run closed')
  assert.equal(text(await row(h, 'Edit', edit('"status": "building"', '"status": "done"'))), 'VBW · recorded a plan done')
  assert.equal(text(await row(h, 'Edit', edit('"result": null', '"result": "pass"'))), 'VBW · recorded a QA verdict')
})

test('a MultiEdit and a Write of the record are one line too', async () => {
  const h = await started()
  const multi = await row(h, 'MultiEdit', { file_path: RECORD, edits: [{ old_string: LEASE_OLD, new_string: LEASE_NEW }, { old_string: 'a', new_string: 'b' }] })
  assert.equal(text(multi), 'VBW · build run started')
  const write = await row(h, 'Write', { file_path: RECORD, content: '{\n  "schema": 2\n}\n' })
  assert.equal(text(write), 'VBW · record updated')
})

test('a change with no known meaning shows a generic one-line summary', async () => {
  const h = await started()
  const out = await row(h, 'Edit', edit('"schema": 2', '"schema": 3'))
  assert.equal(text(out), 'VBW · record updated')
  assert.equal(collect(out).length, 1)
})

test('expanded, the row shows the full diff: VBW leaves the engine row alone', async () => {
  const h = await started()
  assert.ok(isEngine(await row(h, 'Edit', edit(LEASE_OLD, LEASE_NEW), { isExpanded: true }), 'ToolUse'))
})

test('changes to other files, failed calls and a path that only ends alike are untouched', async () => {
  const h = await started()
  assert.ok(isEngine(await row(h, 'Edit', edit('a', 'b', ROOT + '/src/app.js')), 'ToolUse'))
  assert.ok(isEngine(await row(h, 'Edit', edit('a', 'b', ROOT + '/.vbw/spec.md')), 'ToolUse'))
  assert.ok(isEngine(await row(h, 'Edit', edit('a', 'b', ROOT + '/docs/record.json')), 'ToolUse'))
  assert.ok(isEngine(await row(h, 'Edit', edit(LEASE_OLD, LEASE_NEW), { isErrored: true }), 'ToolUse'))
  assert.ok(isEngine(await row(h, 'Read', { file_path: RECORD }), 'ToolUse'))
})

test('garbage input leaves the engine row and throws nothing', async () => {
  const h = await started()
  for (const input of [null, 7, 'x', {}, { file_path: 7 }, { file_path: RECORD }, { file_path: RECORD, edits: 'x' }, { file_path: RECORD, old_string: 4, new_string: {} }]) {
    const out = await row(h, 'Edit', input)
    assert.ok(out, JSON.stringify(input))
  }
  assert.deepEqual(h.errors, [])
})

test('outside a VBW project the engine row stays', async () => {
  const out = await mount({ env: ENV })
  out.write(ROOT + '/README.md', 'x')
  await out.start()
  assert.ok(isEngine(await row(out, 'Edit', edit(LEASE_OLD, LEASE_NEW)), 'ToolUse'))
})

test('the summary is the pure recordEditIntent of the call: one line, null when it is not the record', () => {
  assert.equal(lines.recordEditIntent({ tool: 'Edit', input: edit(LEASE_OLD, LEASE_NEW) }), 'VBW · build run started')
  assert.equal(lines.recordEditIntent({ tool: 'Edit', input: edit('a', 'b', ROOT + '/src/app.js') }), null)
  assert.equal(lines.recordEditIntent({ tool: 'Bash', input: { command: 'ls' } }), null)
  assert.equal(lines.recordEditIntent(null), null)
  assert.equal(lines.recordEditIntent({ tool: 'Edit', input: null }), null)
})
