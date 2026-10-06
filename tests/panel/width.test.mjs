// R82: the VBW panel opens at about a quarter of the terminal width, never
// narrower than 40 columns; a width the user set by hand always wins (Claude
// Code keeps a dragged dock width and ignores a plugin's request then).
// Measured in Claude Code 2.1.291 (2026-10-06): session.start carries no width;
// a docked pane's drawing carries viewport.columns (the conversation beside the
// pane) and props.bodyColumns (the pane), and the terminal is their sum plus 1
// (110 + 89 + 1 = 200; 149 + 50 + 1 = 200); a command carries the terminal's
// width as presentation.columns; $.ui.open takes `columns`. Unasked, the dock
// takes about 45% of the screen. L1, stand-in for the mods API.
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT } from './helpers/fake-mod.mjs'

const DEFAULT = (terminal) => Math.round(terminal * 0.45)

// A session opened by itself, then its first drawing as a dock in a terminal
// `terminal` columns wide, where the pane is `pane` columns (the default share,
// or a width the user dragged and Claude Code kept).
async function session(terminal, { pane = DEFAULT(terminal), ...options } = {}) {
  const h = await mount(options)
  h.project(record(), next())
  await h.fire('session.start', { surface: 'terminal', isInteractive: true, cwd: ROOT })
  await h.advance(4000)
  h.draw = async (p = pane, placement = 'dock') => {
    await h.render({
      viewport: { columns: terminal - p - 1, rows: 50, isFullscreen: placement === 'dock' },
      props: { title: 'VBW', isFocused: false, bodyColumns: p, placement, scroll: { offset: 0, bodyRows: 40 }, view: {} },
    })
    await h.advance(4000)
  }
  return h
}
const command = (h, columns) => h.fire('command.run', { command: 'vbw-panel', args: '', presentation: columns === undefined ? {} : { columns } })

test('opening by itself, before it knows the width, the panel opens as Claude Code places it', async () => {
  const h = await session(200)
  assert.equal(h.opens.length, 1)
  assert.equal(h.opens[0].columns, undefined)
})

test('after its first drawing it asks once for a quarter of the terminal', async () => {
  for (const [terminal, want] of [[200, 50], [240, 60], [400, 100], [180, 45]]) {
    const h = await session(terminal)
    await h.draw()
    assert.equal(h.opens.length, 2, terminal + ' columns')
    assert.equal(h.opens[1].columns, want, terminal + ' columns')
    assert.equal(h.opens[1].focus, undefined, 'never takes the keyboard')
  }
})

test('never narrower than 40 columns', async () => {
  for (const terminal of [144, 150, 159]) {
    const h = await session(terminal)
    await h.draw()
    assert.equal(h.opens.at(-1).columns, 40, terminal + ' columns')
  }
})

test('it asks only once a session: later drawings, at any width, ask nothing more', async () => {
  const h = await session(200)
  await h.draw()
  await h.draw(50)
  await h.draw(70)
  await h.draw(30)
  assert.equal(h.opens.length, 2)
})

test('a width the user dragged wins: VBW asks once and never fights it', async () => {
  // Claude Code kept 90 columns; VBW's one request is ignored, and later
  // drawings still show 90: VBW does not ask again.
  const h = await session(200, { pane: 90 })
  await h.draw(90)
  await h.draw(90)
  await h.draw(90)
  assert.ok(h.opens.length <= 2)
})

test('already at a quarter, nothing is asked', async () => {
  const h = await session(200, { pane: 50 })
  await h.draw(50)
  assert.equal(h.opens.length, 1)
})

test('drawn inline (no dock, main screen), no width is asked: columns apply to a dock only', async () => {
  const h = await session(200)
  await h.draw(200, 'inline')
  assert.equal(h.opens.length, 1)
})

test('/vbw-panel opens at a quarter of the terminal the command was typed in', async () => {
  const h = await session(200)
  await command(h, 240)
  assert.equal(h.opens.at(-1).columns, 60)
  assert.equal(h.opens.at(-1).focus, true)
  await command(h, 120)
  assert.equal(h.opens.at(-1).columns, 40)
})

test('a command without a reported width opens as before, without a width', async () => {
  const h = await session(200)
  await command(h, undefined)
  assert.equal(h.opens.at(-1).columns, undefined)
})

test('a drawing with a missing, zero or odd width neither crashes nor asks', async () => {
  for (const viewport of [undefined, { columns: 0, rows: 50 }, { columns: -3, rows: 50 }, { columns: 'x', rows: 50 }]) {
    const h = await session(200)
    await h.render({ viewport, props: { title: 'VBW', isFocused: false, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} } })
    await h.advance(4000)
    assert.deepEqual(h.errors, [], JSON.stringify(viewport))
    assert.equal(h.opens.length, 1, JSON.stringify(viewport))
  }
})

test('the width is never stored as if the user had chosen it', async () => {
  const store = new Map()
  const h = await session(200, { store })
  await h.draw()
  assert.ok(![...store.keys()].some((k) => /width|columns/i.test(k)), [...store.keys()].join(','))
})
