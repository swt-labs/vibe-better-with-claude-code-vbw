// Delight that respects the user (mods_4_vbw.md §3.1 crew theme, §3.7): the
// motion setting, the crew sprites, the confetti burst, the VBW Wrapped card
// and which celebration a record change earns. Pure functions, tested by value
// (L1); nothing here draws in a real terminal.
import test from 'node:test'
import assert from 'node:assert/strict'
import { PLUGIN, deepFreeze, collect } from './helpers/fake-mod.mjs'

const candy = await import(PLUGIN + '/hooks/panel-candy.js')
const { motionOf, spriteFrame, poseOf, encodeCells, confettiFrames, wrappedModel, renderWrapped, celebration, POSES } = candy
const DEFAULT = 0x01000000
const E = (name) => Object.freeze({ element: name })
const ui = { Box: E('Box'), Text: E('Text'), Button: E('Button') }

test('motion: test mode is off whatever the setting; a setting wins; else the interview level picks', () => {
  assert.equal(motionOf({ setting: 'full', level: 'never', testMode: true }), 'off')
  assert.equal(motionOf({ setting: 'off', level: 'never' }), 'off')
  assert.equal(motionOf({ setting: 'calm', level: 'never' }), 'calm')
  assert.equal(motionOf({ setting: 'full', level: 'senior engineer' }), 'full')
  assert.equal(motionOf({ level: 'never' }), 'full')
  assert.equal(motionOf({ level: 'small scripts or no-code' }), 'full')
  assert.equal(motionOf({ level: 'professionally' }), 'calm')
  assert.equal(motionOf({ level: 'senior engineer' }), 'calm')
  assert.equal(motionOf({ setting: 'wild', level: 'never' }), 'full', 'an unknown setting is ignored')
  assert.equal(motionOf({}), 'calm')
  assert.equal(motionOf(undefined), 'calm')
  assert.equal(motionOf(null), 'calm')
})

test('every pose has at least two frames of 5x3 cells, painted in the role colour, using half-blocks', () => {
  for (const pose of POSES) {
    const a = spriteFrame({ role: 'dev', pose, frame: 0 })
    const b = spriteFrame({ role: 'dev', pose, frame: 1 })
    assert.equal(a.cols, 5)
    assert.equal(a.rows, 3)
    assert.equal(a.cells.length, 15)
    assert.notDeepEqual(a.cells, b.cells, pose + ' animates')
    assert.ok(a.cells.some((c) => c.fg === ROLE_COLORS.dev), pose + ' wears the role colour')
    assert.ok(a.cells.some((c) => /[▀▄▌▐█]/.test(c.ch)), pose + ' is drawn in half-blocks')
    for (const c of a.cells) {
      assert.equal([...c.ch].length, 1)
      assert.equal(c.bg, DEFAULT)
      if (c.ch === ' ') assert.equal(c.fg, DEFAULT)
    }
  }
  assert.deepEqual(spriteFrame({ role: 'qa', pose: 'reading', frame: 2 }), spriteFrame({ role: 'qa', pose: 'reading', frame: 0 }), 'frames cycle')
})

test('each role has its own colour; an unknown role is the neutral grey; docs is pink', () => {
  const fig = (role) => spriteFrame({ role, pose: 'reading', frame: 0 }).cells[1].fg
  assert.equal(fig('docs'), 0xff87d7)
  assert.equal(fig('nobody'), 0x808080)
  const roles = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs', 'nobody']
  assert.equal(new Set(roles.map(fig)).size, roles.length)
})

test('poses differ: the done pose shows a check mark and the quiet pose sleeps', () => {
  const chars = (pose) => spriteFrame({ role: 'lead', pose, frame: 0 }).cells.map((c) => c.ch).join('')
  assert.match(chars('done'), /✓/)
  assert.match(chars('quiet'), /z/i)
  assert.match(chars('failed'), /✗/)
  assert.equal(new Set(POSES.map(chars)).size, POSES.length)
})

test('bad sprite input never throws', () => {
  assert.equal(spriteFrame({ role: 'dev', pose: 'dancing', frame: 0 }), null)
  assert.equal(spriteFrame(undefined), null)
  assert.ok(spriteFrame({ role: 'dev', pose: 'reading', frame: -3 }))
  assert.ok(spriteFrame({ role: 'dev', pose: 'reading', frame: NaN }))
})

test('poseOf maps the feed activity and agent state to a pose', () => {
  assert.equal(poseOf(null, 'done'), 'done')
  assert.equal(poseOf({ kind: 'tool', text: 'reading spec.md' }, 'quiet'), 'quiet')
  assert.equal(poseOf(null, 'failed'), 'failed')
  assert.equal(poseOf({ kind: 'tool', text: 'reading .vbw/spec.md' }, 'working'), 'reading')
  assert.equal(poseOf({ kind: 'tool', text: 'searching for lease' }, 'working'), 'reading')
  assert.equal(poseOf({ kind: 'tool', text: 'editing panel.js' }, 'working'), 'editing')
  assert.equal(poseOf({ kind: 'tool', text: 'writing tests/x.bats' }, 'working'), 'editing')
  assert.equal(poseOf({ kind: 'tool', text: 'running bats tests/prove.bats' }, 'working'), 'shell')
  assert.equal(poseOf({ kind: 'text', text: 'Splitting R69 into…' }, 'working'), 'streaming')
  assert.equal(poseOf(null, 'working'), 'streaming', 'working with nothing to show: thinking')
  assert.equal(poseOf({ kind: 'tool', text: 'something new' }, 'working'), 'shell')
  assert.equal(poseOf(undefined, undefined), 'quiet')
})

test('encodeCells packs little-endian u32 triplets as padded base64, as a Raster takes them', () => {
  assert.equal(encodeCells({ cols: 1, rows: 1, cells: [{ ch: '█', fg: 0xff8800, bg: DEFAULT }] }), Buffer.from(new Uint32Array([0x2588, 0xff8800, DEFAULT]).buffer).toString('base64'))
  const g = spriteFrame({ role: 'scout', pose: 'shell', frame: 1 })
  const words = new Uint32Array(Uint8Array.from(Buffer.from(encodeCells(g), 'base64')).buffer)
  assert.equal(words.length, 45)
  assert.equal(words[3 * 7], g.cells[7].ch.codePointAt(0))
  assert.equal(words[3 * 7 + 1], g.cells[7].fg)
  assert.equal(encodeCells(null), '')
})

test('confetti: about 1.5 s at 10 fps, the same every time for a seed, inside the box', () => {
  const a = confettiFrames({ cols: 40, rows: 4 })
  assert.equal(a.length, 15)
  assert.deepEqual(confettiFrames({ cols: 40, rows: 4 }), a)
  assert.notDeepEqual(confettiFrames({ cols: 40, rows: 4, seed: 2 }), a)
  for (const f of a) {
    assert.equal(f.cols, 40)
    assert.equal(f.rows, 4)
    assert.equal(f.cells.length, 160)
  }
  const lit = (f) => f.cells.filter((c) => c.ch !== ' ').length
  assert.ok(lit(a[2]) > 0, 'it shows confetti')
  assert.equal(lit(a[a.length - 1]), 0, 'it ends clear')
  assert.notDeepEqual(a[1].cells, a[2].cells, 'it moves')
  assert.equal(confettiFrames({ cols: 10, rows: 2, n: 4 }).length, 4)
  assert.deepEqual(confettiFrames({ cols: 0, rows: 4 }), [])
  assert.deepEqual(confettiFrames(undefined), [])
})

const iso = (s) => new Date(Date.UTC(2026, 9, 6, 0, 0, s)).toISOString().replace(/\.\d+Z$/, 'Z')
const shippedRecord = () =>
  deepFreeze({
    milestone: { id: 'M11', title: 'Faster, safer', status: 'shipped' },
    shipped: [{ id: 'M10', at: iso(100) }, { id: 'M11', title: 'Faster, safer', at: iso(10000) }],
    requirements: [
      { id: 'R1', milestone: 'M10', status: 'proven' },
      { id: 'R2', milestone: 'M11', status: 'proven' },
      { id: 'R3', milestone: 'M11', status: 'proven' },
      { id: 'R4', milestone: 'M11', status: 'open' },
    ],
    checks: [{ id: 'C1', req: 'R1' }, { id: 'C2', req: 'R2' }, { id: 'C3', req: 'R3' }, { id: 'C4', req: 'R3' }],
    evidence: { passed: true, checks: { C2: { status: 'pass' }, C3: { status: 'pass' }, C4: { status: 'fail' } } },
    phases: [
      { id: 'P1', milestone: 'M10', outcome: { fix_rounds: 5 } },
      { id: 'P2', milestone: 'M11', outcome: { fix_rounds: 2 } },
      { id: 'P3', milestone: 'M11', outcome: { fix_rounds: 1 } },
      { id: 'P4', milestone: 'M11' },
    ],
  })
const steps = [
  { kind: 'plan', run: 'plan-0', started_at: iso(10), ended_at: iso(90), seconds: 80 },
  { kind: 'plan', run: 'plan-1', started_at: iso(200), ended_at: iso(500), seconds: 300 },
  { kind: 'build', run: 'build-1', started_at: iso(600), ended_at: iso(2400), seconds: 1800 },
  { kind: 'qa', run: 'qa-1', started_at: iso(2500), ended_at: iso(2560), seconds: 60 },
  { kind: 'qa', run: 'qa-2', started_at: iso(20000), ended_at: iso(20100), seconds: 100 },
]
const runs = [
  { runId: 'wf_1', startedAt: Date.parse(iso(200)), agents: [{ id: 'a' }, { id: 'b' }], cost: 1.25 },
  { runId: 'wf_2', startedAt: Date.parse(iso(600)), agents: [{ id: 'c' }], cost: 2 },
  { runId: 'wf_0', startedAt: Date.parse(iso(50)), agents: [{ id: 'z' }], cost: 9 },
]

test('Wrapped counts this milestone only: requirements, checks, agents, fix rounds, time, cost, fastest and slowest step', () => {
  const m = wrappedModel({ record: shippedRecord(), runs, steps })
  assert.deepEqual(m, {
    milestone: { id: 'M11', title: 'Faster, safer' },
    requirements: { proven: 2, total: 3 },
    checks: { passing: 2, total: 3 },
    agents: 3,
    fixRounds: 3,
    seconds: 2160,
    cost: 3.25,
    fastest: { kind: 'qa', run: 'qa-1', seconds: 60 },
    slowest: { kind: 'build', run: 'build-1', seconds: 1800 },
  })
})

test('Wrapped without runs or steps says unknown instead of inventing numbers; nothing shipped is no card', () => {
  const m = wrappedModel({ record: shippedRecord() })
  assert.equal(m.agents, null)
  assert.equal(m.cost, null)
  assert.equal(m.seconds, null)
  assert.equal(m.fastest, null)
  assert.equal(wrappedModel({ record: { ...shippedRecord(), shipped: [] } }), null)
  assert.equal(wrappedModel({ record: null }), null)
  assert.equal(wrappedModel(undefined), null)
})

test('renderWrapped draws the card in plain words', () => {
  const tree = renderWrapped(ui, wrappedModel({ record: shippedRecord(), runs, steps }))
  const text = collect(tree).join('\n')
  for (const want of [/VBW Wrapped/, /M11/, /Faster, safer/, /2 of 3 requirements proven/, /2 of 3 checks pass/, /3 agents/, /3 fix rounds/, /36m00s/, /\$3\.25/, /fastest: qa 1m00s/, /slowest: build 30m00s/]) {
    assert.match(text, want)
  }
  const bare = collect(renderWrapped(ui, wrappedModel({ record: shippedRecord() }))).join('\n')
  assert.match(bare, /cost unknown/)
  assert.doesNotMatch(bare, /null|undefined|NaN/)
  assert.equal(renderWrapped(ui, null), null)
})

test('Wrapped counts agents only from runs that list them: cost-only runs say nothing about agents', () => {
  const costOnly = runs.map(({ runId, startedAt, cost }) => ({ runId, startedAt, cost }))
  const m = wrappedModel({ record: shippedRecord(), runs: costOnly, steps })
  assert.equal(m.agents, null)
  assert.equal(m.cost, 3.25)
  const mixed = wrappedModel({ record: shippedRecord(), runs: [...costOnly, { runId: 'wf_9', startedAt: Date.parse(iso(300)), agents: [{ id: 'q' }] }], steps })
  assert.equal(mixed.agents, 1)
})

test('sweepFrames: one green band crossing the width left to right, one row, ending clear', () => {
  const { sweepFrames } = candy
  const frames = sweepFrames({ cols: 40, n: 10 })
  assert.equal(frames.length, 10)
  const heads = []
  for (const f of frames) {
    assert.equal(f.cols, 40)
    assert.equal(f.rows, 1)
    assert.equal(f.cells.length, 40)
    const lit = f.cells.map((c, x) => (c.ch !== ' ' ? x : -1)).filter((x) => x >= 0)
    for (const x of lit) assert.equal(f.cells[x].fg, 0x5fd75f)
    heads.push(lit.length ? Math.max(...lit) : -1)
  }
  assert.ok(heads[0] >= 0 && heads[0] < 10, 'starts at the left')
  for (let i = 1; i < frames.length - 1; i++) assert.ok(heads[i] > heads[i - 1], 'moves right')
  assert.ok(heads[frames.length - 2] >= 35, 'reaches the right edge')
  assert.equal(heads[frames.length - 1], -1, 'ends clear')
  assert.deepEqual(sweepFrames({ cols: 0 }), [])
  assert.deepEqual(sweepFrames(undefined), [])
  assert.equal(sweepFrames({ cols: 900, n: 3 })[0].cols, 512, 'a Raster is at most 512 wide')
})

const rec = (over = {}) => ({ shipped: [], phases: [{ id: 'P1' }], evidence: { passed: false, at: 't0' }, ...over })

test('celebration: a ship beats a QA pass beats all green; no change, no celebration', () => {
  const before = rec()
  assert.equal(celebration({ before, after: before }), null)
  assert.equal(celebration({ before, after: rec({ evidence: { passed: true, at: 't1' } }) }), 'all-green')
  assert.equal(celebration({ before, after: rec({ phases: [{ id: 'P1', qa: { result: 'pass', at: 'q1' } }] }) }), 'qa-pass')
  assert.equal(celebration({ before, after: rec({ shipped: [{ id: 'M1', at: 's1' }], phases: [{ id: 'P1', qa: { result: 'pass', at: 'q1' } }], evidence: { passed: true, at: 't1' } }) }), 'shipped')
})

test('celebration ignores what was already true, a failing QA and broken input', () => {
  const green = rec({ evidence: { passed: true, at: 't1' }, phases: [{ id: 'P1', qa: { result: 'pass', at: 'q1' } }] })
  assert.equal(celebration({ before: green, after: green }), null)
  assert.equal(celebration({ before: green, after: { ...green, evidence: { passed: true, at: 't2' } } }), 'all-green', 'a fresh green proof')
  assert.equal(celebration({ before: green, after: { ...green, evidence: { passed: false, at: 't2' } } }), null)
  assert.equal(celebration({ before: rec(), after: rec({ phases: [{ id: 'P1', qa: { result: 'fail', at: 'q1' } }] }) }), null)
  assert.equal(celebration({ before: green, after: { ...green, phases: [{ id: 'P1', qa: { result: 'pass', at: 'q2' } }] } }), 'qa-pass', 'a phase passed QA again')
  assert.equal(celebration({ before: null, after: green }), null, 'no earlier snapshot: the first read is not news')
  assert.equal(celebration({ before: green, after: null }), null)
  assert.equal(celebration(undefined), null)
})
