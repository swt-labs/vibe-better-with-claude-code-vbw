// R55: the panel stays light. It reads only local project files, calls nothing
// that reaches the network or credentials, never writes (the record included),
// and does no redraw when nothing changed (L1, stand-in for the mods API).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, ALLOWED, ROOT, T0 } from './helpers/fake-mod.mjs'

const REC = ROOT + '/.vbw/record.json'
const NEXT = ROOT + '/.vbw/runtime/next.json'

// A busy session: start, many changes, a need, a question, both commands, a close.
async function busySession(h) {
  h.project(record(), next())
  h.git()
  await h.start()
  await h.advance(3000)
  h.project(record({ lease: lease('build', h.now()), plans: [{ id: 'a', title: 'A', status: 'building' }] }), next({ action: 'run' }))
  await h.advance(3000)
  h.project(record(), next({ action: 'approve', gate: true }))
  await h.advance(3000)
  const asking = h.fire('tool.call', { tool: 'AskUserQuestion', questions: [] }, async () => ({ result: 'x' }))
  await asking
  await h.render()
  await h.cmd('vbw-panel')
  await h.cmd('vbw-sound', 'off')
  await h.cmd('vbw-sound', 'on')
  await h.fire('ui.close', { id: 'vbw-panel', origin: { kind: 'person' } })
  await h.advance(10000)
}

test('it only calls what a read-only panel needs: no network, no credentials, no processes', async () => {
  const h = await mount()
  await busySession(h)
  const used = h.names()
  const extra = used.filter((n) => !ALLOWED.has(n))
  assert.deepEqual(extra, [], 'calls outside the allowed set')
  for (const n of used) assert.doesNotMatch(n, /^(http|mcp|model|process|env|settings|agent|tool|prompt|telemetry)\./)
  assert.deepEqual(h.errors, [])
})

test('it reads only the project, and the clone cache of finished steps', async () => {
  const h = await mount()
  await busySession(h)
  const paths = [...h.callsOf('fs.read'), ...h.callsOf('fs.stat'), ...h.callsOf('fs.exists')].map((a) => a[0])
  assert.ok(paths.length > 0)
  for (const p of paths) {
    assert.ok(p.startsWith(ROOT + '/') || p === ROOT, 'outside the project: ' + p)
    assert.doesNotMatch(p, /credentials|settings\.json|\.env|\.ssh|\.claude/i, p)
  }
})

test('it never writes: not the record, not any file', async () => {
  const h = await mount()
  await busySession(h)
  assert.equal(h.count('fs.write'), 0)
  // The record is exactly what the test last wrote: the panel did not touch it.
  assert.equal(h.files.get(REC).text, JSON.stringify(record()))
  assert.equal(h.files.get(NEXT).text, JSON.stringify(next({ action: 'approve', gate: true })))
})

test('nothing changed, no redraw: an idle project is only checked, not read or redrawn', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  const reads = h.count('fs.read')
  const draws = h.count('ui.invalidate')
  await h.advance(120000)
  assert.equal(h.count('fs.read'), reads, 'unchanged files are not read again')
  assert.equal(h.count('ui.invalidate'), draws, 'nothing to redraw')
  assert.ok(h.count('fs.stat') > 0, 'the files are checked cheaply')
})

test('during a run the panel redraws only when the minute it shows changes', async () => {
  const h = await mount()
  h.project(record({ lease: lease('build', T0), plans: [{ id: 'a', title: 'A', status: 'building' }] }), next({ action: 'run' }))
  await h.start()
  await h.advance(4000)
  const draws = h.count('ui.invalidate')
  await h.advance(5 * 60000)
  const redraws = h.count('ui.invalidate') - draws
  assert.ok(redraws >= 4 && redraws <= 6, 'redraws in 5 minutes: ' + redraws)
})

test('a changed file is read once and drawn once, however many ticks follow', async () => {
  const h = await mount()
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  const reads = h.count('fs.read')
  const draws = h.count('ui.invalidate')
  h.write(NEXT, next({ action: 'ship', gate: true }))
  await h.advance(30000)
  assert.ok(h.count('fs.read') - reads <= 2, 'the changed file is read once, not on every tick')
  assert.equal(h.count('ui.invalidate') - draws, 1)
})
