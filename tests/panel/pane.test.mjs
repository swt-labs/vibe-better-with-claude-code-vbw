// R89: Mission Control's tabs stay visible at the top of the pane however long
// its content is, and each sentence of the pane shows its key value in colour
// (progress green, estimate amber, cost in the accent colour, a need of the
// user yellow). Pure: panelView and renderPane, no Claude Code needed
// (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = Date.parse('2026-10-05T15:00:00Z')
const S = 1000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const TABS = ['now', 'plan', 'proof', 'timeline', 'decisions', 'team', 'costs']

const reqs = (done, total) => Array.from({ length: total }, (_, i) => ({ id: 'R' + (i + 1), text: 'R' + (i + 1) + ' holds', proof: 'auto', status: i < done ? 'proven' : 'open', milestone: 'M9' }))
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, seconds: s, started_at: new Date(NOW - 1e7 - i * 1e5).toISOString(), ended_at: new Date(NOW - 1e7 - i * 1e5 + s * 1000).toISOString() }))
const HISTORY = [...steps('build', [600, 900, 1200]), ...steps('qa', [100, 200, 300])]
const busy = () => deepFreeze(record({
  requirements: reqs(2, 5),
  lease: lease('build', NOW - 300 * S),
  plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' }],
}))

const texts = (tree) => {
  const out = []
  walk(tree, (n) => {
    if (n.type === 'Text') out.push({ text: n.children.filter((c) => typeof c === 'string').join(''), props: n.props })
  })
  return out
}
const input = (v, over = {}) => ({
  st: { tab: 'now', record: record(), run: null, steps: [], leases: [], cost: 1.42, sound: true, agent: null, phase: null, check: null },
  v, now: NOW, width: 60, wrapped: null, portrait: null, sweep: null, ...over,
})
const on = { act: () => {}, sound: () => {} }
const sentence = (tree, text) => texts(tree).filter((t) => t.text === text)

// --- key values in colour -------------------------------------------------------

test('progress is green, the estimate amber and the cost in the accent colour, each sentence whole', () => {
  const v = view.panelView({ record: busy(), next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: HISTORY })
  const tree = pane.renderPane(UI, input(v), on)
  const row = (id) => v.rows.find((r) => r.id === id)
  assert.match(row('progress').text, /2 of 5 requirements done/)
  assert.match(row('estimate-step').text, /About \d+ min left/)
  assert.match(row('cost').text, /\$1\.42/)
  for (const [id, colour] of [['progress', P.PROGRESS], ['estimate-step', P.ESTIMATE], ['estimate-milestone', P.ESTIMATE], ['cost', P.ACCENT]]) {
    const hit = sentence(tree, row(id).text)
    assert.equal(hit.length, 1, id + ' is drawn once, as one piece of text')
    assert.equal(hit[0].props.color, colour, id)
  }
})

test('a need of the user is yellow; with nothing needed the line is plain', () => {
  const needing = view.panelView({ record: record(), next: next({ action: 'approve', gate: true }), now: NOW, cost: 1, steps: [] })
  assert.ok(needing.need)
  const t1 = pane.renderPane(UI, input(needing), on)
  const need = needing.rows.find((r) => r.id === 'need')
  assert.equal(sentence(t1, need.text)[0].props.color, P.NEED)

  const quiet = view.panelView({ record: record(), next: next(), now: NOW, cost: 1, steps: [] })
  assert.equal(quiet.need, null)
  const plain = sentence(pane.renderPane(UI, input(quiet), on), quiet.rows.find((r) => r.id === 'need').text)
  assert.equal(plain.length, 1)
  assert.equal(plain[0].props.color, undefined)
})

test('a sentence with no value in it stays plain: no requirements, no estimate basis, no cost', () => {
  const v = view.panelView({ record: deepFreeze(record({ requirements: [], lease: lease('build', NOW - 60 * S) })), next: next(), now: NOW, cost: undefined, steps: [] })
  const tree = pane.renderPane(UI, input(v), on)
  const row = (id) => v.rows.find((r) => r.id === id)
  assert.match(row('progress').text, /No requirements/)
  assert.match(row('estimate-step').text, /No estimate/)
  assert.match(row('cost').text, /not available/)
  for (const id of ['progress', 'estimate-step', 'cost']) {
    const hit = sentence(tree, row(id).text)
    assert.equal(hit.length, 1, id)
    assert.equal(hit[0].props.color, undefined, id + ' has no value to colour')
  }
})

test('the milestone and doing sentences keep their colour (none), and every term stays dim', () => {
  const v = view.panelView({ record: busy(), next: next({ action: 'run' }), now: NOW, cost: 1.42, steps: HISTORY })
  const tree = pane.renderPane(UI, input(v), on)
  for (const id of ['milestone', 'doing']) assert.equal(sentence(tree, v.rows.find((r) => r.id === id).text)[0].props.color, undefined, id)
  for (const r of v.rows) assert.ok(texts(tree).some((t) => t.text === r.term && t.props.dimColor === true), r.term + ' is dim')
})

// --- the tabs stay on top -------------------------------------------------------

const agent = (i) => ({
  id: 'a' + i, role: ROLES[i % ROLES.length], label: 'P' + Math.floor(i / 3) + '.' + (i % 3), state: 'working', activity: { kind: 'tool', text: 'editing f' + i + '.js' },
  startedAt: NOW - (600 - i) * S, endedAt: null, lastSeenAt: NOW - S, tokens: 1000 + i, result: null,
})
const longRun = () => deepFreeze({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: NOW - 700 * S, endedAt: null, status: 'running', agents: Array.from({ length: 60 }, (_, i) => agent(i)) })
const longInput = (tab, scroll) => input(view.panelView({ record: busy(), next: next(), now: NOW, cost: 1, steps: [] }),
  { st: { tab, record: busy(), run: longRun(), steps: [], leases: [], cost: 1, sound: true, agent: null, phase: null, check: null }, ...(scroll ? { scroll } : {}) })
const tabsIn = (node) => { const out = []; walk(node, (n) => { if (n.type === 'Button' && /^tab-/.test(String(n.props.key))) out.push(n.props.key) }); return out }

test('the tabs are the first thing in the pane, whatever the tab, however long its content and however far it is scrolled', () => {
  for (const tab of TABS) {
    for (const offset of [0, 7, 500]) {
      const tree = pane.renderPane(UI, longInput(tab, { offset, bodyRows: 30 }), on)
      assert.equal(tabsIn(tree.children[0]).length, 7, tab + ' at ' + offset + ': all seven tabs open the pane')
      assert.equal(tabsIn(find(tree, (n) => n.props && n.props.key === 'body') || { children: [] }).length, 0, tab + ': the tabs are not inside what scrolls')
    }
  }
})

test('the content under the tabs is a clipped window of the pane height, so a long tab cannot push the tabs away', () => {
  for (const bodyRows of [12, 30, 60]) {
    const tree = pane.renderPane(UI, longInput('now', { offset: 0, bodyRows }), on)
    const body = find(tree, (n) => n.props && n.props.key === 'body')
    assert.ok(body, 'a body under the tabs')
    assert.equal(body.props.overflow, 'hidden')
    assert.ok(Number.isInteger(body.props.height) && body.props.height >= 1 && body.props.height < bodyRows, 'height ' + body.props.height + ' leaves room for the tabs in ' + bodyRows)
  }
})

test('scrolling still moves the content: the body shows other rows at another offset', () => {
  const at = (offset) => JSON.stringify(find(pane.renderPane(UI, longInput('now', { offset, bodyRows: 30 }), on), (n) => n.props && n.props.key === 'body'))
  assert.notEqual(at(0), at(10))
  assert.notEqual(at(10), at(25))
})

test('without a scroll hint the pane still draws its tabs and its content', () => {
  const tree = pane.renderPane(UI, longInput('now'), on)
  assert.equal(tabsIn(tree).length, 7)
  assert.ok(texts(tree).length > 20)
})
