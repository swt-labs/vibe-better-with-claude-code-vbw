// R52: the panel opens by itself when a VBW project session starts (Claude Code
// itself keeps a pane that opens unasked out of a narrow window), opens at any
// width with a command, and once the user closes it, it stays closed until they
// open it again, across sessions. Closing and opening change no project data.
// Driven through a stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT, PANE } from './helpers/fake-mod.mjs'

async function session(store, options = {}) {
  const h = await mount({ store, ...options })
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  return h
}
const personClose = (h) => h.fire('ui.close', { id: PANE, origin: { kind: 'person' } })

test('a VBW project session opens the panel by itself, without taking the keyboard', async () => {
  const h = await session(new Map())
  assert.equal(h.opens.length, 1)
  assert.equal(h.opens[0].id, PANE)
  assert.equal(h.opens[0].focus, undefined)
})

test('where Claude Code keeps the pane closed (a narrow window) nothing fails and it is not tried again', async () => {
  const h = await session(new Map(), { placed: false })
  h.project(undefined, next({ action: 'approve', gate: true }))
  await h.advance(20000)
  h.project(record({ milestone: { id: 'M10', title: 'Other', status: 'active' } }))
  await h.advance(20000)
  assert.equal(h.opens.length, 1)
  assert.deepEqual(h.errors, [])
})

test('a VBW command opens the panel at any width', async () => {
  for (const placed of [true, false]) {
    const h = await session(new Map(), { placed })
    await personClose(h)
    const before = h.opens.length
    const answer = await h.cmd('vbw-panel')
    assert.equal(h.opens.length, before + 1)
    assert.equal(h.opens.at(-1).id, PANE)
    assert.ok(!answer || !/error|cannot|narrow/i.test(answer.text || ''))
  }
})

test('the command is registered, and works while Claude is busy', async () => {
  const h = await session(new Map())
  const reg = h.callsOf('command.register').map((a) => a[0])
  const panel = reg.find((c) => c.name === 'vbw-panel')
  assert.ok(panel && panel.description)
  assert.equal(panel.immediate, true)
})

test('closing the panel by hand keeps it closed: not on new activity, not in a new session', async () => {
  const store = new Map()
  const h = await session(store)
  await personClose(h)
  h.project(record({ milestone: { id: 'M10', title: 'Other', status: 'active' } }), next({ action: 'approve', gate: true }))
  await h.advance(30000)
  assert.equal(h.opens.length, 1, 'new activity does not reopen it')
  const again = await session(store)
  assert.equal(again.opens.length, 0, 'a new session does not reopen it')
  const third = await session(store)
  assert.equal(third.opens.length, 0)
})

test('the user opening it again is remembered: later sessions open it by themselves', async () => {
  const store = new Map()
  const h = await session(store)
  await personClose(h)
  await h.cmd('vbw-panel')
  const again = await session(store)
  assert.equal(again.opens.length, 1)
})

test('only the user closing it counts: a close made by a plugin or an unload is not remembered', async () => {
  const store = new Map()
  const h = await session(store)
  await h.fire('ui.close', { id: PANE, origin: { kind: 'plugin' } })
  await h.fire('ui.close', { id: PANE, origin: { kind: 'unload' } })
  assert.equal((await session(store)).opens.length, 1)
})

test('closing another pane changes nothing', async () => {
  const store = new Map()
  const h = await session(store)
  await h.fire('ui.close', { id: 'something-else', origin: { kind: 'person' } })
  assert.equal((await session(store)).opens.length, 1)
})

test('the close is passed on, never refused', async () => {
  const h = await session(new Map())
  const e = { id: PANE, origin: { kind: 'person' } }
  assert.deepEqual(await h.fire('ui.close', e), e)
})

test('opening and closing change no project data and no tracked file: the choice lives in the user store only', async () => {
  const store = new Map()
  const h = await mount({ store })
  h.project(record(), next())
  h.git()
  const before = h.snapshot()
  await h.start()
  await personClose(h)
  await h.cmd('vbw-panel')
  await personClose(h)
  await h.advance(10000)
  assert.equal(h.count('fs.write'), 0)
  assert.equal(h.count('process.run'), 0)
  assert.equal(h.snapshot(), before)
  assert.ok(store.size >= 1, 'the choice is kept in the user store')
  for (const [k, v] of store) assert.doesNotMatch(JSON.stringify([k, v]), new RegExp(ROOT), 'no project path in the user store')
})

test('outside a VBW project the panel is never opened', async () => {
  const h = await mount()
  await h.start()
  await h.cmd('vbw-panel')
  assert.equal(h.opens.length, 0)
})
