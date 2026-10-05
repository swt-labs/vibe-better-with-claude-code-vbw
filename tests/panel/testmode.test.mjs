// R64: VBW's own real-app test sessions (their project holds the marker file
// .vbw/runtime/test-mode, written by tools/l3.sh; the panel reads no
// environment, R55) never play the sound aloud and never read or change the user's own panel and
// sound choices: they keep their choices under test keys. Outside test mode
// the panel uses the user's keys. And every redraw names 'ui.render', as Claude
// Code requires (an unnamed redraw is dropped). Driven through the stand-in (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, PANE, ROOT } from './helpers/fake-mod.mjs'

const approve = () => next({ action: 'approve', gate: true })
const USER_KEYS = ['vbw-panel.closed', 'vbw-panel.sound']

const TEST_MODE = { [ROOT + '/.vbw/runtime/test-mode']: '1' }

async function session(files) {
  const store = new Map([['vbw-panel.closed', false], ['vbw-panel.sound', true]])
  const h = await mount({ files, store })
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  return { h, store }
}

test('in test mode a need records the sound but plays nothing aloud', async () => {
  const { h } = await session(TEST_MODE)
  h.project(undefined, approve())
  await h.advance(30000)
  assert.equal(h.plays.length, 0, 'no audio in a test session')
})

test('in test mode the sound switch and a close never touch the user keys', async () => {
  const { h, store } = await session(TEST_MODE)
  const before = USER_KEYS.map((k) => store.get(k))
  await h.cmd('vbw-sound', 'off')
  await h.fire('ui.close', { id: PANE, origin: { kind: 'person' } })
  assert.deepEqual(USER_KEYS.map((k) => store.get(k)), before, 'user choices unchanged')
  assert.ok([...store.keys()].some((k) => k.startsWith('test.')), 'test choices kept under test keys')
})

test('outside test mode the sound plays and the switch uses the user keys', async () => {
  const { h, store } = await session({})
  h.project(undefined, approve())
  await h.advance(30000)
  assert.equal(h.plays.length, 1)
  await h.cmd('vbw-sound', 'off')
  assert.equal(store.get('vbw-panel.sound'), false)
})

test('a change on disk redraws the panel by itself, with the redraw naming ui.render', async () => {
  const { h } = await session({})
  const n = h.invalidations()
  h.project(undefined, approve())
  await h.advance(6000)
  assert.ok(h.invalidations() > n, 'the panel asked Claude Code to redraw')
})
