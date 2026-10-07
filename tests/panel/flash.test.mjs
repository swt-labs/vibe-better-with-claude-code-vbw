// R91: when an agent starts, its new row in the band flashes briefly in its
// role's colour (about a second), only when the motion setting is full. The
// flash ends on its own and leaves the row in its normal colours. The model
// and the drawing are tested by value; the wiring through the stand-in for
// Claude Code's mods API (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, mount, record, next, lease, walk, find, T0 } from './helpers/fake-mod.mjs'
import { ENV, writeRun, launch, band } from './helpers/run.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000

const agent = (over = {}) => ({
  id: 'a1', role: 'dev', label: 'P6.7', state: 'working', activity: { kind: 'tool', text: 'editing app-topbar.tsx' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents) => ({ runId: 'wf_1', kind: 'building', phase: 'wave 1', startedAt: NOW - 600 * S, endedAt: null, status: 'running', agents })
const model = (born, over = {}) => stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', run: run([agent(), agent({ id: 'a2', role: 'qa', label: 'P6.8' })]), born, ...over })
const flashed = (m, id) => m.rows.find((r) => r.id === id).flash === true
const texts = (node) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const rowOf = (tree, id) => find(tree, (n) => n.type === 'Box' && n.props.key === 'agent-' + id)

// --- the model ------------------------------------------------------------------

test('a row that appeared less than a second ago flashes; an older one does not', () => {
  const m = model({ a1: NOW - 300, a2: NOW - 5000 })
  assert.equal(flashed(m, 'a1'), true)
  assert.equal(flashed(m, 'a2'), false)
  assert.equal(flashed(model({ a1: NOW - 1500 }), 'a1'), false, 'it ends on its own')
  assert.equal(flashed(model({ a1: NOW }), 'a1'), true, 'it starts with the row')
})

test('a row never seen before has nothing to flash from: no flash without a birth time', () => {
  for (const born of [undefined, null, {}, { a1: 'x' }, { a1: NaN }, 7]) assert.equal(flashed(model(born), 'a1'), false, JSON.stringify(born))
})

test('only the full motion setting flashes: calm, off and an unknown level do not', () => {
  for (const motion of ['calm', 'off', undefined, 'wild']) {
    const m = model({ a1: NOW - 100, a2: NOW - 100 }, { motion })
    assert.equal(flashed(m, 'a1'), false, String(motion))
    assert.equal(flashed(m, 'a2'), false, String(motion))
  }
  assert.equal(flashed(model({ a1: NOW - 100 }, { motion: 'full' }), 'a1'), true)
})

test('a row that already finished does not flash', () => {
  const m = stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', born: { d: NOW - 100 }, run: run([agent({ id: 'd', state: 'done', endedAt: NOW - 50, result: 'ok' })]) })
  assert.equal(m.rows.find((r) => r.id === 'd').flash === true, false)
})

// --- the drawing ----------------------------------------------------------------

test('a flashing row is drawn inverted in its role colour; a normal row has nothing inverted', () => {
  const m = model({ a1: NOW - 300 })
  const tree = stage.renderStage(UI, m)
  const inverted = texts(rowOf(tree, 'a1')).filter((t) => t.props.inverse === true)
  assert.ok(inverted.length >= 1, 'something in the row is inverted')
  for (const t of inverted) assert.equal(t.props.color, P.roleColor('dev'), 'the flash is in the role colour')
  assert.equal(texts(rowOf(tree, 'a2')).filter((t) => t.props.inverse).length, 0)
})

test('when the flash is over the row is back in its normal colours: no inverse, same colours as a row that never flashed', () => {
  const during = texts(rowOf(stage.renderStage(UI, model({ a1: NOW - 300 })), 'a1'))
  const after = texts(rowOf(stage.renderStage(UI, model({ a1: NOW - 3000 })), 'a1'))
  const never = texts(rowOf(stage.renderStage(UI, model(undefined)), 'a1'))
  assert.equal(after.filter((t) => t.props.inverse).length, 0)
  assert.deepEqual(after.map((t) => [t.text, t.props.color, t.props.dimColor]), never.map((t) => [t.text, t.props.color, t.props.dimColor]))
  assert.deepEqual(during.map((t) => t.text), after.map((t) => t.text), 'the flash changes colour only, never the words')
})

// --- the wiring -----------------------------------------------------------------

const invertedIn = (tree) => { let n = 0; walk(tree, (x) => { if (x.type === 'Text' && x.props && x.props.inverse === true) n++ }); return n }

async function started(motion) {
  const h = await mount({ env: ENV })
  h.project(record({ lease: lease('plan', T0), settings: { motion } }), next({ action: 'run' }))
  await h.start()
  await h.settle()
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  return h
}

test('wired: a new agent flashes in the band at full motion, and the flash ends by itself with a redraw', async () => {
  const h = await started('full')
  assert.ok(invertedIn(await band(h)) >= 1, 'the new rows flash')
  const before = h.invalidations()
  await h.advance(1500)
  assert.ok(h.invalidations() > before, 'the band is redrawn when the flash ends')
  assert.equal(invertedIn(await band(h)), 0, 'the rows are back to normal')
  assert.deepEqual(h.errors, [])
})

test('wired: with calm or off motion nothing ever flashes', async () => {
  for (const motion of ['calm', 'off']) {
    const h = await started(motion)
    assert.equal(invertedIn(await band(h)), 0, motion)
    await h.advance(1500)
    assert.equal(invertedIn(await band(h)), 0, motion + ' later')
  }
})
