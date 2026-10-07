// Mission Control's live tabs (mods_4_vbw.md §3.3): Now, Timeline, Costs.
// Pure models tested by value, renders by tree shape (evidence level L1).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { collect, find, walk, deepFreeze } from './helpers/fake-mod.mjs'
import { nowModel, timelineModel, costsModel, renderNow, renderTimeline, renderCosts } from '../../plugin/hooks/panel-mission-live.js'

const S = 1_800_000_000_000
const MIN = 60_000
const UI = { Box: Object.freeze({ element: 'Box' }), Text: Object.freeze({ element: 'Text' }), Button: Object.freeze({ element: 'Button' }) }

const agent = (over) => ({ id: 'a1', role: 'dev', label: 'P55.1', model: 'sonnet', state: 'working', activity: null, startedAt: S, endedAt: null, lastSeenAt: S, tokens: null, result: null, ...over })
const run = (agents, over = {}) => ({ runId: 'wf_1', kind: 'building', phase: 'Build', startedAt: S, endedAt: null, status: 'running', agents, ...over })
const step = (kind, seconds) => ({ kind, run: kind + '-x', started_at: '2026-10-01T00:00:00Z', ended_at: '2026-10-01T00:10:00Z', seconds })

test('nowModel: no run, or a damaged one, gives no model and never throws', () => {
  for (const r of [null, undefined, 42, 'x', {}, { agents: 'no' }]) assert.equal(nowModel({ run: r, now: S }), null)
  assert.equal(nowModel(null), null)
  assert.equal(nowModel(undefined), null)
})

test('nowModel: phases are columns in the run order; agents without a phase go by their label', () => {
  const r = deepFreeze(run([
    agent({ id: 'q', role: 'qa', label: 'P55', phase: 'Verify', startedAt: S + 3 * MIN }),
    agent({ id: 'l', role: 'lead', label: 'P55', phase: 'Plan', startedAt: S }),
    agent({ id: 'd1', role: 'dev', label: 'P55.1', phase: 'Build', startedAt: S + MIN }),
    agent({ id: 'd2', role: 'dev', label: 'P55.2', phase: 'Build', startedAt: S + MIN }),
  ]))
  const m = nowModel({ run: r, now: S + 4 * MIN })
  assert.deepEqual(m.columns.map((c) => c.title), ['Plan', 'Build', 'Verify'])
  assert.deepEqual(m.columns.map((c) => c.cards.map((x) => x.id)), [['l'], ['d1', 'd2'], ['q']])
  const told = nowModel({ run: { ...r, phases: ['Verify', 'Build', 'Plan'] }, now: S })
  assert.deepEqual(told.columns.map((c) => c.title), ['Verify', 'Build', 'Plan'])
  const bare = nowModel({ run: run([agent({ id: 'x', label: 'P7.2' }), agent({ id: 'y', label: '' })]), now: S })
  assert.deepEqual(bare.columns.map((c) => c.title), ['P7', 'Agents'])
})

test('nowModel: the frame shows the state; a stopped run greys what was cut off', () => {
  const r = run([
    agent({ id: 'w', state: 'working' }), agent({ id: 'd', state: 'done' }),
    agent({ id: 'f', state: 'failed' }), agent({ id: 'q', state: 'quiet' }),
  ])
  const frames = (m) => Object.fromEntries(m.columns[0].cards.map((c) => [c.id, c.frame]))
  assert.deepEqual(frames(nowModel({ run: r, now: S })), { w: '#ffaf00', d: 'green', f: 'red', q: 'gray' })
  const stopped = nowModel({ run: { ...r, status: 'stopped', endedAt: S + MIN }, now: S + 2 * MIN })
  assert.deepEqual(frames(stopped), { w: 'gray', d: 'green', f: 'red', q: 'gray' })
  assert.equal(stopped.columns[0].cards[0].state, 'cut')
})

test('nowModel: a card carries its role colour, activity, tokens and a select action', () => {
  const m = nowModel({ run: run([agent({ id: 'a9', role: 'qa', label: 'P55', tokens: 48_213, activity: { kind: 'tool', text: 'reading spec.md' } })]), now: S })
  const c = m.columns[0].cards[0]
  assert.deepEqual(c, {
    id: 'a9', title: 'qa P55', role: 'qa', roleColor: 'yellow', state: 'working', frame: '#ffaf00',
    activity: 'reading spec.md', tokens: '48k tokens', selected: false, action: { select: 'a9' },
  })
  const big = nowModel({ run: run([agent({ tokens: 1_250_000 }), agent({ id: 'b', tokens: 900, role: 'docs' })]), now: S })
  assert.deepEqual(big.columns[0].cards.map((x) => [x.tokens, x.roleColor]), [['1.3M tokens', 'green'], ['900 tokens', '#ff87d7']])
  const long = nowModel({ run: run([agent({ activity: { kind: 'text', text: 'x'.repeat(100) } })]), now: S })
  assert.ok(long.columns[0].cards[0].activity.length <= 40)
  assert.ok(long.columns[0].cards[0].activity.endsWith('…'))
})

test('nowModel: the selected agent opens its detail; an unknown one opens nothing', () => {
  const r = run([agent({ id: 'd', state: 'done', startedAt: S + MIN, endedAt: S + 4 * MIN + 12_000, result: 'built P55.1' }), agent({ id: 'w', role: 'scout', label: 'docs', model: null })])
  const m = nowModel({ run: r, now: S + 10 * MIN, selected: 'd' })
  assert.deepEqual(m.detail, { id: 'd', label: 'dev P55.1', role: 'dev', model: 'sonnet', activity: null, result: 'built P55.1', elapsed: '3 min 12 s' })
  assert.deepEqual(m.columns.flatMap((c) => c.cards).map((c) => [c.id, c.selected]), [['w', false], ['d', true]])
  const w = nowModel({ run: r, now: S + 45_000, selected: 'w' })
  assert.deepEqual([w.detail.model, w.detail.elapsed], [null, '45 s'])
  assert.equal(nowModel({ run: r, now: S, selected: 'nope' }).detail, null)
  assert.deepEqual(m.header, { kind: 'building', status: 'running', elapsed: '10 min' })
})

test('timelineModel: one lane per agent, start and end as column spans on the run clock', () => {
  const r = run([
    agent({ id: 'a', startedAt: S, endedAt: S + 5 * MIN, state: 'done' }),
    agent({ id: 'b', startedAt: S + 5 * MIN, endedAt: null }),
  ])
  const m = timelineModel({ run: r, now: S + 10 * MIN, steps: [], width: 20 })
  assert.deepEqual(m.lanes.map((l) => [l.id, l.from, l.to, l.seconds, l.slow]), [['a', 0, 10, 300, false], ['b', 10, 20, 300, false]])
  assert.equal(m.width, 20)
  const tiny = timelineModel({ run: run([agent({ startedAt: S, endedAt: S + 1000 })], { endedAt: S + 10 * MIN, status: 'completed' }), now: S + 99 * MIN, steps: [], width: 20 })
  assert.deepEqual([tiny.lanes[0].from, tiny.lanes[0].to], [0, 1])
  assert.equal(timelineModel({ run: null, now: S }), null)
})

test('timelineModel: the three slowest agents are highlighted when there are more than three', () => {
  const secs = [60, 600, 120, 900, 300]
  const r = run(secs.map((s, i) => agent({ id: 'a' + i, startedAt: S, endedAt: S + s * 1000, state: 'done' })), { endedAt: S + 900_000, status: 'completed' })
  const m = timelineModel({ run: r, now: S + 900_000, steps: [], width: 30 })
  assert.deepEqual(m.lanes.filter((l) => l.slow).map((l) => l.id), ['a1', 'a3', 'a4'])
  const few = timelineModel({ run: { ...r, agents: r.agents.slice(0, 3) }, now: S + 900_000, steps: [], width: 30 })
  assert.equal(few.lanes.some((l) => l.slow), false)
})

test('timelineModel: a sparkline of past steps of this kind, the median marked, and the time left', () => {
  const steps = [step('build', 600), step('qa', 9999), step('build', 1200), step('build', 300), step('build', 900)]
  const m = timelineModel({ run: run([agent({})]), now: S + 5 * MIN, steps, width: 20 })
  assert.deepEqual(m.spark, { bars: '▃█▁▆', median: 750, mark: 0, kind: 'build' })
  assert.equal(m.left, 'about 8 min left')
  const late = timelineModel({ run: run([agent({})]), now: S + 30 * MIN, steps, width: 20 })
  assert.equal(late.left, 'taking longer than usual')
  const thin = timelineModel({ run: run([agent({})]), now: S, steps: steps.slice(0, 2), width: 20 })
  assert.deepEqual([thin.spark.bars, thin.spark.median, thin.spark.mark, thin.left], ['▄', null, null, null])
  const none = timelineModel({ run: run([agent({})], { kind: 'researching' }), now: S, steps, width: 20 })
  assert.deepEqual([none.spark, none.left], [null, null])
  const done = timelineModel({ run: run([agent({})], { endedAt: S + MIN, status: 'completed' }), now: S + MIN, steps, width: 20 })
  assert.equal(done.left, null)
  const qa = timelineModel({ run: run([agent({})], { kind: 'verifying' }), now: S, steps: [step('qa', 60), step('qa', 60), step('qa', 60)], width: 20 })
  assert.deepEqual([qa.spark.bars, qa.spark.median, qa.spark.kind], ['▄▄▄', 60, 'qa'])
})

test('costsModel: cost per run as "about", totals per kind, the session total, bars to width', () => {
  const runs = deepFreeze([
    { kind: 'building', startedAt: S, costStart: 0.1, costEnd: 1.1 },
    { kind: 'verifying', startedAt: S + MIN, costStart: 1.1, costEnd: 1.35 },
    { kind: 'building', startedAt: S + 2 * MIN, costStart: 1.35, costEnd: 1.85 },
    { kind: 'fixing', startedAt: S + 3 * MIN, costStart: 1.85, costEnd: null },
    { kind: 'broken', costStart: 'x' }, null,
  ])
  const m = costsModel({ runs, sessionCost: 2.0, width: 20 })
  assert.deepEqual(m.runs.map((r) => [r.name, r.text, r.bar]), [
    ['building 1', 'about $1.00', 20], ['verifying 1', 'about $0.25', 5], ['building 2', 'about $0.50', 10], ['fixing 1', 'about $0.15', 3],
  ])
  assert.deepEqual(m.kinds, [
    { kind: 'building', runs: 2, cost: 1.5, text: 'about $1.50' },
    { kind: 'verifying', runs: 1, cost: 0.25, text: 'about $0.25' },
    { kind: 'fixing', runs: 1, cost: 0.15, text: 'about $0.15' },
  ])
  assert.equal(m.session, 'This session: $2.00')
  const empty = costsModel({ runs: [], sessionCost: null })
  assert.deepEqual(empty, { runs: [], kinds: [], session: 'The session cost is not available.', width: 30 })
  assert.deepEqual(costsModel(null), empty)
})

test('renderNow: phase columns of framed cards; pressing a card asks to select it', () => {
  const m = nowModel({ run: run([agent({ id: 'a1', phase: 'Build', state: 'done', tokens: 2000, activity: { kind: 'tool', text: 'editing x.js' } })]), now: S + MIN, selected: 'a1' })
  const acts = []
  const tree = renderNow(UI, m, (a) => acts.push(a))
  const card = find(tree, (n) => n.type === 'Box' && n.props.borderColor === 'green')
  assert.ok(card, 'a green-framed card')
  assert.equal(card.props.borderStyle, 'round')
  const btn = find(card, (n) => n.type === 'Button' && n.props.key === 'card:a1')
  assert.equal(btn.props.label, 'dev P55.1')
  btn.props.onPress({ surface: 'terminal' })
  assert.deepEqual(acts, [{ select: 'a1' }])
  const texts = collect(tree)
  for (const t of ['Build', 'editing x.js', '2k tokens', 'building · running · 1 min', 'Model: sonnet', 'Elapsed: 1 min']) assert.ok(texts.some((x) => x.includes(t)), t + ' in ' + JSON.stringify(texts))
  assert.doesNotThrow(() => renderNow(UI, m).children[0])
  assert.ok(collect(renderNow(UI, null)).join(' ').includes('No VBW workflow'))
})

test('renderTimeline and renderCosts draw lanes, sparkline and bars', () => {
  const r = run([agent({ id: 'a', startedAt: S, endedAt: S + 5 * MIN, state: 'done' }), agent({ id: 'b', role: 'qa', label: 'P55', startedAt: S + 5 * MIN })])
  const tl = renderTimeline(UI, timelineModel({ run: r, now: S + 10 * MIN, steps: [step('build', 600), step('build', 1200), step('build', 300)], width: 10 }))
  const texts = collect(tl)
  assert.ok(texts.includes('█'.repeat(5)) && texts.includes('     ' + '█'.repeat(5)), JSON.stringify(texts))
  assert.ok(texts.some((t) => t.includes('▃█▁')) && texts.some((t) => t.includes('median 10 min')) && texts.some((t) => t.includes('taking longer than usual')))
  let rows = 0
  walk(tl, (n) => { if (n.type === 'Box' && n.props.flexDirection === 'row') rows++ })
  assert.equal(rows, 2)
  const cs = collect(renderCosts(UI, costsModel({ runs: [{ kind: 'building', startedAt: S, costStart: 0, costEnd: 0.5 }], sessionCost: 0.7, width: 8 })))
  for (const t of ['building 1', 'about $0.50', '█'.repeat(8), 'This session: $0.70']) assert.ok(cs.some((x) => x.includes(t)), t)
  assert.ok(collect(renderTimeline(UI, null)).length > 0)
  assert.ok(collect(renderCosts(UI, null)).length > 0)
})
