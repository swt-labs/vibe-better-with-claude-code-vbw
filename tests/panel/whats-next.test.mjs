// R124, R125's mechanics (L1, the stand-in for Claude Code's mods API): the
// Now tab has a What's next section (a Box keyed 'whats-next') with the stored
// recommendation, in the same order as vbw status: the top pick with its size,
// its reason, then up to two runners-up with their sizes. It follows the record
// as it changes, says there is none yet when none is stored, survives a missing
// or malformed field, fits the pane's width, and its Suggest next button fills
// the prompt with the what's-next request without sending it. Its title
// shimmers and its top pick pulses when a recommendation with a new written
// time arrives, then both settle within a few seconds, only with full motion;
// one already seen does not move. Whether that looks subtle and elegant is the
// owner's call (R125, [human]).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { mount, record, next, walk, find, collect, PLUGIN } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const PALETTE = new Set([...Object.values(P.ROLE_COLORS), ...Object.values(P.STATE_COLORS), P.NEUTRAL, P.ACCENT, P.NEED, P.PROGRESS, P.ESTIMATE])
const REQUEST = "/vbw:vibe what's next"

const REC = (over = {}) => ({
  at: '2026-10-09T10:00:00Z',
  top: { text: 'Refunds for paid orders', reason: 'Customers ask for it most this month.', size: 'small', source: 'T4' },
  runners: [{ text: 'Gift cards', size: 'large', source: 'T9' }, { text: 'Dark mode', size: 'medium' }],
  ...over,
})

const props = (bodyColumns = 50) => ({
  props: { title: 'VBW', isFocused: false, bodyColumns, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} },
})

async function session(rec, options = {}) {
  const h = await mount(options)
  h.project(rec, next())
  await h.start()
  await h.settle()
  return h
}

const section = async (h, columns) => find(await h.render(columns ? props(columns) : props()), (n) => n.type === 'Box' && n.props.key === 'whats-next')
const texts = (node) => (node ? collect(node) : [])
// What the section looks like, without its press handlers.
const snap = async (h) => JSON.stringify(await section(h))
const button = (node) => find(node, (n) => n.type === 'Button' && n.props.label === 'Suggest next')

async function frames(h, ms, step = 100) {
  const out = []
  for (let t = 0; t <= ms; t += step) {
    out.push(await snap(h))
    await h.advance(step)
  }
  return out
}
const moves = (fs) => new Set(fs).size > 1

test("the Now tab shows a What's next section: the top pick with its size, its reason, then each runner-up with its size", async () => {
  const h = await session(record({ recommendation: REC() }))
  const s = await section(h)
  assert.ok(s, "no Box keyed 'whats-next' on the Now tab")
  const all = texts(s).join('\n')
  assert.match(all, /What's next/)
  const at = (re) => all.search(re)
  for (const re of [/Refunds for paid orders/, /small/, /Customers ask for it most this month\./, /Gift cards/, /large/, /Dark mode/, /medium/]) assert.ok(at(re) >= 0, 'missing ' + re)
  assert.ok(at(/Refunds for paid orders/) < at(/Customers ask/), 'the pick comes before its reason')
  assert.ok(at(/Customers ask/) < at(/Gift cards/), 'the reason comes before the runners-up')
  assert.ok(at(/Gift cards/) < at(/Dark mode/), 'the runners-up keep their order')
  assert.ok(button(s), 'no Suggest next button')
  assert.deepEqual(h.errors, [])
})

test('a new recommendation in the record appears without restarting or closing the panel', async () => {
  const h = await session(record({ recommendation: REC() }))
  h.project(record({ recommendation: REC({ at: '2026-10-09T11:00:00Z', top: { text: 'Invoices by email', reason: 'Accountants need them.', size: 'medium' }, runners: [] }) }))
  await h.advance(4000)
  const all = texts(await section(h)).join('\n')
  assert.match(all, /Invoices by email/)
  assert.match(all, /Accountants need them\./)
  assert.doesNotMatch(all, /Refunds for paid orders/)
  assert.deepEqual(h.errors, [])
})

test('with no recommendation stored, one line says there is none yet, and the button is there', async () => {
  const h = await session(record())
  const s = await section(h)
  assert.ok(s)
  assert.match(texts(s).join('\n'), /none yet/i)
  assert.ok(button(s))
})

test('an empty backlog is said as such', async () => {
  const h = await session(record({ recommendation: { at: '2026-10-09T10:00:00Z', empty: true } }))
  assert.match(texts(await section(h)).join('\n'), /backlog is empty/i)
})

test('a malformed recommendation hides the pick lines and never breaks the panel', async () => {
  for (const bad of ['soon', 42, [], { at: 'x' }, { top: 'Refunds' }, { at: '2026-10-09T10:00:00Z', top: { text: 7 }, runners: 'x' }, null]) {
    const h = await session(record({ recommendation: bad }))
    const tree = await h.render(props())
    const s = find(tree, (n) => n.type === 'Box' && n.props.key === 'whats-next')
    assert.ok(s, 'the section stays: ' + JSON.stringify(bad))
    assert.ok(button(s), 'the button stays: ' + JSON.stringify(bad))
    assert.doesNotMatch(texts(s).join('\n'), /Refunds|undefined|null|\[object/, JSON.stringify(bad))
    assert.ok(collect(tree).includes('Plan'), 'the tabs still draw')
    assert.deepEqual(h.errors, [], JSON.stringify(bad))
  }
})

test("long picks and reasons are cut to the pane's width, never wrapped", async () => {
  const long = 'An extremely long recommendation that goes on and on well past any pane width you would ever see'
  const h = await session(record({ recommendation: REC({ top: { text: long, reason: long + ' because ' + long, size: 'large' }, runners: [{ text: long, size: 'small' }] }) }))
  for (const columns of [30, 50]) {
    const s = await section(h, columns)
    assert.ok(s, "no Box keyed 'whats-next' at " + columns + ' columns')
    assert.match(texts(s).join('\n'), /An extremely/)
    walk(s, (n) => {
      if (n.type !== 'Text') return
      const t = n.children.filter((c) => typeof c === 'string').join('')
      assert.ok(t.length <= columns, `"${t}" is ${t.length} wide in ${columns} columns`)
      assert.ok(!n.props.wrap || /truncate/.test(n.props.wrap), 'wraps: ' + n.props.wrap)
    })
  }
})

test("Suggest next fills the prompt with the what's-next request and never sends it", async () => {
  const h = await session(record({ recommendation: REC() }))
  await button(await section(h)).props.onPress({ surface: 'terminal' })
  await h.settle()
  const fills = h.callsOf('prompt.fill')
  assert.equal(fills.length, 1)
  assert.equal(fills[0][0].text, REQUEST)
  const prompt = h.names().filter((n) => n.startsWith('prompt.'))
  assert.deepEqual(prompt.filter((n) => n !== 'prompt.fill' && n !== 'prompt.suggest'), [], 'only fills, never sends')
})

test('with no prompt box, pressing Suggest next does nothing and shows no error', async () => {
  const h = await session(record({ recommendation: REC() }))
  const push = h.calls.push.bind(h.calls)
  h.calls.push = (c) => {
    if (c && c.name === 'prompt.fill') throw new Error('no prompt box here')
    return push(c)
  }
  await assert.doesNotReject(async () => {
    await button(await section(h)).props.onPress({ surface: 'terminal' })
    await h.settle()
  })
  h.calls.push = push
  assert.deepEqual(h.errors, [])
  assert.equal(h.count('ui.toast'), 0)
})

test('with full motion the title shimmers and the top pick pulses when a new recommendation arrives, then both settle within a few seconds', async () => {
  const h = await session(record({ recommendation: REC(), settings: { profile: 'balanced', autonomy_cap: 25, motion: 'full' } }))
  assert.ok(moves(await frames(h, 2500)), 'nothing moved after a new recommendation arrived')
  await h.advance(4000)
  const late = await frames(h, 2000, 250)
  assert.ok(!moves(late), 'still moving more than six seconds after it arrived')
  h.project(record({ recommendation: REC({ at: '2026-10-09T12:00:00Z' }), settings: { profile: 'balanced', autonomy_cap: 25, motion: 'full' } }))
  await h.advance(2000)
  assert.ok(moves(await frames(h, 2500)), 'a newer written time did not move again')
})

test('the motion is drawn in the colours of the existing palette', async () => {
  const h = await session(record({ recommendation: REC(), settings: { profile: 'balanced', autonomy_cap: 25, motion: 'full' } }))
  for (let i = 0; i < 25; i++) {
    const s = await section(h)
    assert.ok(s, "no Box keyed 'whats-next'")
    walk(s, (n) => {
      for (const k of ['color', 'backgroundColor', 'borderColor']) {
        if (n.props[k] !== undefined) assert.ok(PALETTE.has(n.props[k]), `${k} ${n.props[k]} is not a palette colour`)
      }
    })
    await h.advance(100)
  }
})

test('opening the panel on a recommendation already seen does not move', async () => {
  const store = new Map()
  const rec = record({ recommendation: REC(), settings: { profile: 'balanced', autonomy_cap: 25, motion: 'full' } })
  const first = await session(rec, { store })
  await frames(first, 3000)
  await first.advance(5000)
  const again = await session(rec, { store })
  assert.match(texts(await section(again)).join('\n'), /Refunds for paid orders/)
  assert.ok(!moves(await frames(again, 3000)), 'a recommendation already seen moved again')
})

test('with motion off or calm, by setting or by the interview level, the section is still', async () => {
  const cases = [
    { settings: { profile: 'balanced', autonomy_cap: 25, motion: 'off' } },
    { settings: { profile: 'balanced', autonomy_cap: 25, motion: 'calm' } },
    { project: { name: 'demo', interview: { level: 'senior engineer', depth: 'technical and brief', involvement: 'I make the calls', at: '2026-10-01T00:00:00Z' } } },
  ]
  for (const over of cases) {
    const h = await session(record({ recommendation: REC(), ...over }))
    assert.ok(!moves(await frames(h, 3000)), 'moved with ' + JSON.stringify(over))
    assert.match(texts(await section(h)).join('\n'), /Refunds for paid orders/)
  }
})

test('a level new to code moves by default (full motion), as the rest of the panel does', async () => {
  const h = await session(record({ recommendation: REC(), project: { name: 'demo', interview: { level: 'never', depth: 'plain with technical terms explained', involvement: 'options with a recommendation', at: '2026-10-01T00:00:00Z' } } }))
  assert.ok(moves(await frames(h, 2500)))
})
