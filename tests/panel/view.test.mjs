// R51: what the panel says. plugin/hooks/panel-view.js turns the project's record
// and its last `vbw next` into plain sentences, each with its technical term
// beside it (D107). Pure data in, rows out: no Claude Code needed (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease, deepFreeze } from './helpers/fake-mod.mjs'

const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const NOW = Date.parse('2026-10-05T15:00:00Z')
const iso = (ms) => new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z')
const row = (v, id) => v.rows.find((r) => r.id === id)
const show = (input) => view.panelView({ now: NOW, ...input })

// Requirements of the current milestone and their states, as the kernel stores them.
const reqs = (...xs) => xs.map(([id, milestone, status]) => ({ id, text: id + ' holds', proof: 'auto', status, milestone }))

test('the milestone and its progress are plain sentences: requirements done of total', () => {
  const r = record({ requirements: reqs(['R1', 'M1', 'proven'], ['R2', 'M9', 'proven'], ['R3', 'M9', 'accepted'],
    ['R4', 'M9', 'failing'], ['R5', 'M9', 'open'], ['R6', 'M9', 'rejected']) })
  const v = show({ record: r, next: next() })
  assert.match(row(v, 'milestone').text, /M9/)
  assert.match(row(v, 'milestone').text, /Live VBW panel/)
  // R2 is proven and R3 accepted; R4, R5 and R6 are not done; R1 belongs to another milestone.
  assert.equal(row(v, 'progress').text, '2 of 5 requirements done.')
  assert.equal(row(v, 'progress').term, 'requirements')
})

test('M11 defect: progress counts requirements as the status line does, not phases ("1 of 1 phase" beside "1/15")', () => {
  const list = reqs(['R1', 'M9', 'proven'], ...Array.from({ length: 14 }, (_, i) => ['R' + (i + 2), 'M9', 'open']))
  const r = record({ phases: [{ id: 'P1', title: 'A', milestone: 'M9', qa: { result: 'pass' } }], requirements: list })
  assert.equal(row(show({ record: r, next: next() }), 'progress').text, '1 of 15 requirements done.')
})

test('progress counts a single requirement in the singular and says when none is set', () => {
  const one = record({ requirements: reqs(['R1', 'M9', 'accepted']) })
  assert.equal(row(show({ record: one, next: next() }), 'progress').text, '1 of 1 requirement done.')
  for (const requirements of [[], undefined, 'x', [null, 5]]) {
    assert.match(row(show({ record: record({ requirements }), next: next() }), 'progress').text, /no requirements/i)
  }
})

test('what VBW is doing: idle, planning, building (naming the parts), checking, fixing, mapping', () => {
  const doing = (l) => row(show({ record: record({ lease: l }), next: next() }), 'doing').text
  assert.match(doing(null), /idle|nothing is running/i)
  assert.match(doing(lease('plan', NOW - 5000)), /planning/i)
  assert.match(doing(lease('qa', NOW - 5000)), /checking/i)
  assert.match(doing(lease('fix', NOW - 5000)), /fixing/i)
  assert.match(doing(lease('map', NOW - 5000)), /mapping|reading the project/i)
  const building = record({
    lease: lease('build', NOW - 5000),
    plans: [
      { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'building' },
      { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'building' },
      { id: 'P44.3', phase: 'P44', title: 'Write the docs', status: 'planned' },
    ],
  })
  const text = row(show({ record: building, next: next() }), 'doing').text
  assert.match(text, /building/i)
  assert.match(text, /Show the cost/)
  assert.match(text, /Show the estimate/)
  assert.doesNotMatch(text, /Write the docs/)
})

test('how long the current run has gone on is told in whole minutes', () => {
  const t = (ms) => row(show({ record: record({ lease: lease('build', NOW - ms) }), next: next() }), 'doing').text
  assert.match(t(4 * 60000 + 20000), /4 min/)
  assert.match(t(5000), /just started|less than a minute/i)
})

test('when nothing needs the user it says so, and the need is empty', () => {
  const v = show({ record: record(), next: next() })
  assert.equal(v.need, null)
  assert.match(row(v, 'need').text, /nothing is needed/i)
})

test('when VBW needs the user it says what for', () => {
  const need = (n) => show({ record: record(), next: next(n) })
  assert.match(need({ action: 'approve', gate: true }).need.text, /approve/i)
  assert.match(need({ action: 'approve', gate: true }).need.text, /plan/i)
  const accept = need({ action: 'accept', gate: true, detail: { requirements: ['R54'] } })
  assert.match(accept.need.text, /check/i)
  assert.match(accept.need.text, /R54/)
  assert.match(need({ action: 'ship', gate: true }).need.text, /ship/i)
  assert.match(need({ action: 'spec', gate: true }).need.text, /requirements|what to build/i)
  assert.match(need({ action: 'escalate', gate: true, detail: { fixes: ['F3'] } }).need.text, /decision|decide/i)
  const v = need({ action: 'approve', gate: true })
  assert.equal(row(v, 'need').text, v.need.text)
})

test('a question the user has to answer is a need', () => {
  const v = show({ record: record(), next: next(), question: { id: 'q1' } })
  assert.match(v.need.text, /question/i)
  assert.match(v.need.key, /^question/)
})

test('a need has a stable key: the same need keeps it, another need changes it', () => {
  const key = (n) => show({ record: record(), next: next(n) }).need.key
  const a = key({ action: 'accept', gate: true, detail: { requirements: ['R54'] } })
  assert.equal(a, key({ action: 'accept', gate: true, detail: { requirements: ['R54'] } }))
  assert.notEqual(a, key({ action: 'accept', gate: true, detail: { requirements: ['R55'] } }))
  assert.notEqual(a, key({ action: 'approve', gate: true }))
})

test('while a run is open VBW is busy, not waiting for the user', () => {
  const v = show({ record: record({ lease: lease('build', NOW - 60000) }), next: next({ action: 'approve', gate: true }) })
  assert.equal(v.need, null)
})

test('D107: every row is a plain sentence with its technical term beside it', () => {
  const rec = record({ lease: lease('qa', NOW - 90000) })
  const inputs = [
    { record: record(), next: next() },
    { record: rec, next: next() },
    { record: record(), next: next({ action: 'approve', gate: true }) },
    { record: record(), next: next(), question: { id: 'q' } },
  ]
  for (const input of inputs) {
    for (const r of show(input).rows) {
      assert.ok(r.text && r.text.length > 8, 'text of ' + r.id)
      assert.ok(r.term && r.term.length > 0 && r.term.split(/\s+/).length <= 4, 'term of ' + r.id)
      assert.notEqual(r.text, r.term)
      assert.doesNotMatch(r.text, /\b(QA|lease|gate|contract|workflow|vbw run|record\.json)\b/i, 'jargon in the plain text of ' + r.id)
    }
  }
  assert.equal(row(show({ record: rec, next: next() }), 'doing').term.toLowerCase(), 'qa')
})

test('a missing, empty or invalid project state gives one neutral line and never throws', () => {
  for (const input of [{ record: null, next: null }, { record: {}, next: null }, { record: 'x', next: 5 }, { record: { milestone: null, phases: 3 }, next: [] }, {}]) {
    const v = show(input)
    assert.equal(v.need, null)
    assert.equal(v.rows.length, 1)
    assert.equal(v.rows[0].id, 'neutral')
    assert.ok(v.rows[0].text.length > 8 && v.rows[0].term.length > 0)
  }
})

test('a record without a next step still shows the milestone and progress', () => {
  const v = show({ record: record(), next: null })
  assert.match(row(v, 'milestone').text, /Live VBW panel/)
  assert.equal(v.need, null)
})

test('building the view changes nothing in its input', () => {
  const input = deepFreeze({ record: record({ lease: lease('build', NOW - 5000) }), next: next({ action: 'accept', gate: true, detail: { requirements: ['R1'] } }), question: { id: 'q' }, now: NOW })
  assert.doesNotThrow(() => view.panelView(input))
})

test('the Claude Code versions with mods start at 2.1.287', () => {
  const ok = (v) => view.supports(v)
  for (const v of ['2.1.287', '2.1.289', '2.1.1000', '2.2.0', '3.0.0', '2.1.287-dev.20261001.t1.sha1']) assert.equal(ok(v), true, v)
  for (const v of ['2.1.286', '2.1.99', '2.0.999', '1.9.9', '', undefined, null, 'garbage', '2.1']) assert.equal(ok(v), false, String(v))
  assert.equal(view.MIN_VERSION, '2.1.287')
})
