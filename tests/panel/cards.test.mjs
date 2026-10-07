// R85: in Mission Control's Now tab, each agent card is framed in its role's
// colour and shows its state as a coloured mark and word (running, done,
// failed, quiet), so two agents of different roles never look the same. Pure:
// nowModel and renderNow, no Claude Code needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']

const agent = (over = {}) => ({
  id: 'a1', role: 'dev', label: 'P6.7', state: 'working', activity: { kind: 'tool', text: 'editing app-topbar.tsx' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents, over = {}) => ({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 600 * S, endedAt: null, status: 'running', agents, ...over })
const draw = (r) => live.renderNow(UI, live.nowModel({ run: deepFreeze(r), now: NOW }))
const frameOf = (tree, id) => find(tree, (n) => n.type === 'Box' && n.props.key === 'card-box:' + id).props.borderColor
const texts = (node) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const card = (tree, id) => find(tree, (n) => n.type === 'Box' && n.props.key === 'card-box:' + id)

test('each card is framed in its role colour', () => {
  const tree = draw(run(ROLES.map((role) => agent({ id: role, role }))))
  for (const role of ROLES) assert.equal(frameOf(tree, role), P.roleColor(role), role)
})

test('two agents of different roles never get the same frame colour, whatever their state', () => {
  const states = ['working', 'done', 'failed', 'quiet']
  for (const state of states) {
    const tree = draw(run(ROLES.map((role) => agent({ id: role, role, state }))))
    assert.equal(new Set(ROLES.map((r) => frameOf(tree, r))).size, ROLES.length, state)
  }
})

test('a card shows its state as a mark and a word in the state colour', () => {
  const cases = { working: 'running', done: 'done', failed: 'failed', quiet: 'quiet' }
  for (const [state, name] of Object.entries(cases)) {
    const tree = draw(run([agent({ state })]))
    const line = texts(card(tree, 'a1')).find((t) => t.text === P.STATE_MARKS[name] + ' ' + P.STATE_WORDS[name])
    assert.ok(line, state + ' card says ' + P.STATE_MARKS[name] + ' ' + P.STATE_WORDS[name])
    assert.equal(line.props.color, P.stateColor(name), state)
  }
})

test('a run that was stopped shows what it cut off in the cut-off mark, word and grey', () => {
  const tree = draw(run([agent()], { status: 'stopped', endedAt: NOW - 60 * S }))
  const line = texts(card(tree, 'a1')).find((t) => t.text === P.STATE_MARKS.cut + ' ' + P.STATE_WORDS.cut)
  assert.ok(line)
  assert.equal(line.props.color, P.stateColor('cut'))
})

test('the frame tells the role and the mark tells the state: they do not mix up', () => {
  const tree = draw(run([agent({ id: 'a', role: 'qa', state: 'failed' }), agent({ id: 'b', role: 'dev', state: 'working' })]))
  assert.equal(frameOf(tree, 'a'), P.roleColor('qa'))
  assert.equal(frameOf(tree, 'b'), P.roleColor('dev'))
  assert.equal(texts(card(tree, 'a')).find((t) => /failed/.test(t.text)).props.color, P.stateColor('failed'))
  assert.equal(texts(card(tree, 'b')).find((t) => /running/.test(t.text)).props.color, P.stateColor('running'))
})

test('an unknown role is framed in the neutral grey and does not crash rendering', () => {
  const tree = draw(run([agent({ id: 'x', role: 'mystery' }), agent({ id: 'y', role: undefined, state: 'weird' })]))
  assert.equal(frameOf(tree, 'x'), P.NEUTRAL)
  assert.equal(frameOf(tree, 'y'), P.NEUTRAL)
  assert.ok(card(tree, 'y'))
})

test('with colour off the state is still carried by the mark and the word', () => {
  const tree = draw(run([agent({ id: 'w' }), agent({ id: 'd', state: 'done' }), agent({ id: 'f', state: 'failed' }), agent({ id: 'q', state: 'quiet' })]))
  const plain = (id) => texts(card(tree, id)).map((t) => t.text).join('\n')
  assert.match(plain('w'), /running/)
  assert.match(plain('d'), /done/)
  assert.match(plain('f'), /failed/)
  assert.match(plain('q'), /quiet/)
  const marks = ['w', 'd', 'f', 'q'].map((id) => texts(card(tree, id)).find((t) => / (running|done|failed|quiet)$/.test(t.text)).text.split(' ')[0])
  assert.equal(new Set(marks).size, 4, 'four states, four marks')
})
