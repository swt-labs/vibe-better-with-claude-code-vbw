// R87, drawing: an agent's activity is drawn with the verb coloured and the
// object dimmed, in the band and on Mission Control's cards, and a long object
// is cut to the row's width without breaking colour. Pure: renderStage and
// renderNow, no Claude Code needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000
const len = (s) => [...s].length

const agent = (activity, over = {}) => ({
  id: 'a1', role: 'dev', label: 'P6.7', state: 'working', activity,
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents) => ({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 600 * S, endedAt: null, status: 'running', agents })
const tool = (text) => ({ kind: 'tool', text })
const band = (a, columns = 100) => {
  const tree = stage.renderStage(UI, stage.stageModel({ now: NOW, maxRows: 12, columns, motion: 'calm', run: deepFreeze(run([a])) }))
  return find(tree, (n) => n.type === 'Box' && n.props.key === 'agent-a1')
}
const cardOf = (a) => find(live.renderNow(UI, live.nowModel({ run: deepFreeze(run([a])), now: NOW })), (n) => n.type === 'Box' && n.props.key === 'card-box:a1')
const texts = (node) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const SURFACES = { band: (a) => band(a), card: (a) => cardOf(a) }

for (const [name, draw] of Object.entries(SURFACES)) {
  test(name + ': the verb is coloured and the object dimmed', () => {
    const t = texts(draw(agent(tool('editing app-topbar.tsx'))))
    const verb = t.find((x) => x.text.trim() === 'editing')
    const object = t.find((x) => x.text.includes('app-topbar.tsx'))
    assert.ok(verb, 'the verb stands alone')
    assert.ok(object, 'the object stands apart')
    assert.equal(verb.props.color, P.roleColor('dev'))
    assert.equal(verb.props.dimColor, undefined)
    assert.equal(object.props.dimColor, true)
    assert.equal(object.props.color, undefined)
  })

  test(name + ': a one-word intention is just the coloured verb', () => {
    const t = texts(draw(agent(tool('thinking'))))
    const verb = t.find((x) => x.text.trim() === 'thinking')
    assert.ok(verb)
    assert.equal(verb.props.color, P.roleColor('dev'))
  })

  test(name + ': a generic intention is drawn the same way, with a verb and an object', () => {
    const t = texts(draw(agent(tool('running a command'))))
    const verb = t.find((x) => x.text.trim() === 'running')
    assert.ok(verb)
    assert.equal(verb.props.color, P.roleColor('dev'))
    assert.equal(t.find((x) => x.text.includes('a command')).props.dimColor, true)
  })

  test(name + ': a long object is cut with an ellipsis, the verb keeps its colour, and no colour code is written into the text', () => {
    const long = 'editing ' + 'a-very-long-file-name-that-keeps-going-and-going-'.repeat(3) + '.tsx'
    const t = texts(draw(agent(tool(long))))
    const verb = t.find((x) => x.text.trim() === 'editing')
    assert.equal(verb.props.color, P.roleColor('dev'))
    const object = t.find((x) => x.text.includes('a-very-long'))
    assert.match(object.text, /…$/)
    for (const x of t) assert.doesNotMatch(x.text, /\x1b|\\x1b|\[[0-9;]*m/, 'no escape code in ' + JSON.stringify(x.text))
  })
}

test('band: a long object is cut to the row width, columns counted over the whole row', () => {
  const long = 'editing ' + 'a-very-long-file-name-that-keeps-going-and-going.tsx'
  for (const columns of [30, 40, 60, 100]) {
    const row = band(agent(tool(long)), columns)
    const width = texts(row).reduce((n, x) => n + len(x.text), 0)
    assert.ok(width <= columns, columns + ' columns: the row is ' + width)
    assert.ok(texts(row).some((x) => x.text.trim() === 'editing' || x.text.trim() === 'edit…' || /^ed/.test(x.text.trim())), 'the verb survives at ' + columns)
  }
})

test('card: the activity stays within 40 characters', () => {
  const t = texts(cardOf(agent(tool('editing ' + 'x'.repeat(120)))))
  const parts = t.filter((x) => /editing|x{5}/.test(x.text))
  assert.ok(parts.reduce((n, x) => n + len(x.text), 0) <= 41)
})

test('band: what an agent says (not a tool) stays one quoted line, not split into a verb and an object', () => {
  const t = texts(band(agent({ kind: 'text', text: 'Splitting R69 into two plans' })))
  assert.ok(t.some((x) => x.text.trim() === '"Splitting R69 into two plans"'))
})

test('band: quiet, done and failed rows keep one state-coloured phrase', () => {
  const quiet = texts(band(agent(tool('editing a.js'), { state: 'quiet', lastSeenAt: NOW - 90 * S })))
  assert.equal(quiet.find((x) => /^quiet 1m30s$/.test(x.text.trim())).props.color, P.stateColor('quiet'))
  const done = texts(band(agent(null, { state: 'done', endedAt: NOW - 5 * S, result: 'ok' })))
  assert.equal(done.find((x) => /^done · ok$/.test(x.text.trim())).props.color, P.stateColor('done'))
  const failed = texts(band(agent(null, { state: 'failed', endedAt: NOW - 5 * S, result: 'boom' })))
  assert.equal(failed.find((x) => x.text.trim() === 'boom').props.color, P.stateColor('failed'))
})
