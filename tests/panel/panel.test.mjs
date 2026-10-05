// R51: the panel module draws the view and keeps it current by itself. Driven
// through a stand-in for Claude Code's mods API (L1): a virtual project, a clock
// the test advances, and the hooks the module registers.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, dimTexts, ROOT, T0 } from './helpers/fake-mod.mjs'

const REC = ROOT + '/.vbw/record.json'

async function started(rec = record(), nxt = next(), options = {}) {
  const h = await mount(options)
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return h
}

test('the pane shows the milestone, its progress, what VBW is doing and whether it needs the user', async () => {
  const h = await started()
  const text = await h.text()
  assert.match(text, /Live VBW panel/)
  assert.match(text, /2 of 5 phases/i)
  assert.match(text, /idle|nothing is running/i)
  assert.match(text, /nothing is needed/i)
  assert.deepEqual(h.errors, [])
})

test('D107: each technical term is drawn in small text beside its sentence', async () => {
  const h = await started(record({ lease: lease('qa', T0 - 90000) }))
  const small = dimTexts(await h.render()).join('|')
  assert.match(small, /\bQA\b/i)
  assert.match(small, /milestone/i)
})

test('the pane is drawn only for its own id; other panes are left alone', async () => {
  const h = await started()
  const other = await h.render({ requestId: 'somebody-else' })
  assert.deepEqual(other, { type: 'engine', ref: 'default' })
})

test('a phase finishing shows in the panel within 5 seconds, by itself', async () => {
  const h = await started()
  const done = record().phases.map((p) => (p.milestone === 'M9' ? { ...p, qa: { result: 'pass' } } : p))
  const before = h.count('ui.invalidate')
  h.project(record({ phases: done }))
  const took = await h.until(async () => /5 of 5 phases/i.test(await h.text()), 10000)
  assert.ok(took >= 0 && took <= 5000, 'took ' + took + ' ms')
  assert.ok(h.count('ui.invalidate') > before, 'a redraw was asked for')
})

test('a run starting shows as building, with the parts, within 5 seconds', async () => {
  const h = await started()
  const plans = [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }]
  h.project(record({ lease: lease('build', h.now()), plans }), next({ action: 'run' }))
  const took = await h.until(async () => /building.*Show the cost/is.test(await h.text()), 10000)
  assert.ok(took >= 0 && took <= 5000, 'took ' + took + ' ms')
})

test('a need for the user shows with what it is for within 5 seconds, and clears within 5 seconds', async () => {
  const h = await started()
  h.project(undefined, next({ action: 'accept', gate: true, detail: { requirements: ['R54'] } }))
  let took = await h.until(async () => /R54/.test(await h.text()), 10000)
  assert.ok(took >= 0 && took <= 5000, 'took ' + took + ' ms')
  assert.doesNotMatch(await h.text(), /nothing is needed/i)
  h.project(undefined, next())
  took = await h.until(async () => /nothing is needed/i.test(await h.text()), 10000)
  assert.ok(took >= 0 && took <= 5000, 'took ' + took + ' ms')
})

test('a half-written or invalid project file keeps the last good text and raises no error', async () => {
  const h = await started()
  for (const bad of ['{"milestone": {"id": "M9", "ti', '', 'not json', '[]', 'null']) {
    h.write(REC, bad)
    await h.advance(4000)
    const text = await h.text()
    assert.match(text, /Live VBW panel/, 'last good text for ' + JSON.stringify(bad))
  }
  h.remove(REC)
  await h.advance(4000)
  assert.match(await h.text(), /Live VBW panel/)
  assert.deepEqual(h.errors, [])
  h.write(REC, JSON.stringify(record({ milestone: { id: 'M10', title: 'Next thing', status: 'active' } })))
  assert.ok((await h.until(async () => /Next thing/.test(await h.text()), 10000)) >= 0, 'recovers when the file is good again')
})

test('with no good state yet, an invalid file shows a neutral line', async () => {
  const h = await mount()
  h.write(REC, '{"half')
  await h.start()
  await h.settle()
  const texts = await h.texts()
  assert.ok(texts.length >= 1 && texts.every((t) => t.length > 0))
  assert.doesNotMatch(texts.join(' '), /undefined|NaN|\[object/)
  assert.deepEqual(h.errors, [])
})

test('the panel is never drawn with undefined, NaN or object text', async () => {
  const h = await started(record({ lease: lease('build', T0), plans: [{ id: 'x', status: 'building' }] }))
  assert.doesNotMatch(await h.text(), /undefined|NaN|\[object/)
})
