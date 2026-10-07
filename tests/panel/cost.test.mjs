// R56: the panel shows what the session has cost so far, as one small line
// (D106): no breakdown, updated as the cost changes, and never a wrong number
// when the cost is not available (L1, stand-in for the mods API).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, dimTexts, ALLOWED } from './helpers/fake-mod.mjs'

async function session(options) {
  const h = await mount(options)
  h.project(record(), next())
  await h.start()
  await h.advance(4000)
  return h
}
const money = (text) => text.match(/\$\d[\d,]*\.\d\d/g) || []

test('the cost so far is one small line with its technical term beside it', async () => {
  const h = await session()
  const texts = await h.texts()
  const cost = texts.filter((t) => /\$/.test(t))
  assert.equal(cost.length, 1, 'one line')
  assert.match(cost[0], /\$1\.42/)
  assert.match(cost[0], /cost/i)
  assert.match(dimTexts(await h.render()).join('|'), /cost/i)
})

test('there is no breakdown: no tokens, no cache, no per-model lines', async () => {
  const h = await session({ usage: { cost: { usd: 3.2 }, context: { tokens: 1000, window: 200000, percent: 1 }, rateLimits: [] } })
  const text = await h.text()
  assert.equal(money(text).length, 1)
  assert.doesNotMatch(text, /tokens|cache|input|output|context window|per model/i)
})

test('it follows the cost within 5 seconds, by itself', async () => {
  const h = await session()
  const draws = h.count('ui.invalidate')
  h.setUsage({ cost: { usd: 2.5 } })
  const took = await h.until(async () => /\$2\.50/.test(await h.text()), 10000)
  assert.ok(took >= 0 && took <= 5000, 'took ' + took + ' ms')
  assert.ok(h.count('ui.invalidate') > draws)
  assert.doesNotMatch(await h.text(), /\$1\.42/)
})

test('when the cost is not available the line is left out or says so, never a number', async () => {
  for (const options of [{ usageError: true }, { usage: {} }, { usage: { cost: undefined } }, { usage: { cost: { usd: 'x' } } }, { usage: { cost: { usd: NaN } } }, { usage: null }]) {
    const h = await session(options)
    const text = await h.text()
    assert.deepEqual(money(text), [], JSON.stringify(options))
    assert.doesNotMatch(text, /\$/)
    assert.doesNotMatch(text, /undefined|NaN|null/)
    // Every line about the cost says it is not available (the Costs tab's button names a tab, not a cost).
    for (const t of await h.texts()) if (/cost/i.test(t) && t !== 'Costs') assert.match(t, /not available/i)
    assert.deepEqual(h.errors, [])
  }
})

test('only read-only calls are made to learn the cost', async () => {
  const h = await session()
  for (const n of h.names()) assert.ok(ALLOWED.has(n), n)
})
