// R86: in the band, each agent row shows its plan label and spinner in the
// role's colour, its time and tokens dimmed, and the run's cost in an accent
// colour in the header. Pure: stageModel and renderStage, no Claude Code
// needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000

const agent = (over = {}) => ({
  id: 'a1', role: 'dev', label: 'P6.7', model: 'sonnet', state: 'working',
  activity: { kind: 'tool', text: 'editing app-topbar.tsx' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents) => ({ runId: 'wf_1', kind: 'building', phase: 'wave 1 of 2', startedAt: NOW - 604 * S, endedAt: null, status: 'running', agents })
const draw = (agents, over = {}) => {
  const m = stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'calm', cost: 1.5, run: deepFreeze(run(agents)), ...over })
  return stage.renderStage(UI, m)
}
const rowOf = (tree, id) => find(tree, (n) => n.type === 'Box' && n.props.key === 'agent-' + id)
const texts = (node) => {
  const out = []
  walk(node, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const textOf = (node, want) => texts(node).find((t) => t.text.trim() === want)
const SPIN = /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]$/

test('the plan label is drawn in the role colour, for every role', () => {
  for (const role of ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']) {
    const label = textOf(rowOf(draw([agent({ role, label: 'P6.7' })]), 'a1'), 'P6.7')
    assert.ok(label, role + ' row has its label')
    assert.equal(label.props.color, P.roleColor(role), role)
  }
})

test('the spinner is drawn in the role colour', () => {
  const row = rowOf(draw([agent({ role: 'qa' })]), 'a1')
  const spin = texts(row).find((t) => SPIN.test(t.text.trim()))
  assert.ok(spin, 'a spinner is drawn while the agent works')
  assert.equal(spin.props.color, P.roleColor('qa'))
})

test('time and tokens are dimmed, not coloured', () => {
  const row = rowOf(draw([agent({ tokens: 41_200 })]), 'a1')
  const tail = texts(row).find((t) => /41k/.test(t.text))
  assert.ok(tail, 'the tokens are shown')
  assert.match(tail.text, /2m10s/, 'the time is shown beside them')
  assert.equal(tail.props.dimColor, true)
  assert.equal(tail.props.color, undefined)
})

test('the run cost is drawn in the accent colour in the header; nothing else in the header is', () => {
  const tree = draw([agent()])
  const header = find(tree, (n) => n.type === 'Box' && n.props.key === 'header')
  const accent = texts(header).filter((t) => t.props.color === P.ACCENT)
  assert.equal(accent.length, 1, 'one accent piece in the header')
  assert.match(accent[0].text, /≈\$1\.50/)
  assert.ok(texts(header).some((t) => /VBW ▸ building/.test(t.text) && t.props.color !== P.ACCENT), 'the rest of the header keeps its own colour')
  assert.equal(texts(tree).filter((t) => t.props.color === P.ACCENT).length, 1, 'the accent is for the cost alone')
})

test('without a cost there is no accent piece', () => {
  const tree = draw([agent()], { cost: undefined })
  assert.equal(texts(tree).filter((t) => t.props.color === P.ACCENT).length, 0)
  assert.doesNotMatch(texts(tree).map((t) => t.text).join(' '), /\$/)
})

test('a done and a failed row keep their label in the role colour', () => {
  const tree = draw([agent({ id: 'd', label: 'P1.1', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }), agent({ id: 'f', role: 'qa', label: 'P1.2', state: 'failed', endedAt: NOW - 5 * S, result: 'boom' })])
  assert.equal(textOf(rowOf(tree, 'd'), 'P1.1').props.color, P.roleColor('dev'))
  assert.equal(textOf(rowOf(tree, 'f'), 'P1.2').props.color, P.roleColor('qa'))
})

test('with colour off the states are still told apart by a mark and a word', () => {
  const tree = draw([
    agent({ id: 'w' }), agent({ id: 'd', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }),
    agent({ id: 'f', state: 'failed', endedAt: NOW - 5 * S, result: 'boom' }), agent({ id: 'q', state: 'quiet', lastSeenAt: NOW - 90 * S }),
  ])
  const plain = (id) => texts(rowOf(tree, id)).map((t) => t.text).join('')
  assert.match(plain('w'), /●.*editing app-topbar\.tsx/)
  assert.match(plain('d'), /✓.*done/)
  assert.match(plain('f'), /✗.*boom/)
  assert.match(plain('q'), /quiet 1m30s/)
  const marks = ['w', 'd', 'f'].map((id) => /[●✓✗]/.exec(plain(id))[0])
  assert.equal(new Set(marks).size, 3)
})
