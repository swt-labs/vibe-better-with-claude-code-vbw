// The VBW Stage (mods_4_vbw.md §3.1, §3.2, §3.8): the band above the prompt.
// plugin/hooks/panel-stage.js turns the run model, the last `vbw next` and the
// session's health into a model (tested by value) and draws it with h() (tested
// by tree shape). Pure: no Claude Code needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, next, deepFreeze, walk, find, collect } from './helpers/fake-mod.mjs'

const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
const NOW = 1_800_000_000_000
const S = 1000
const UI = { Box: Object.freeze({ element: 'Box' }), Text: Object.freeze({ element: 'Text' }), Button: Object.freeze({ element: 'Button' }) }
const len = (s) => [...s].length

const agent = (over = {}) => ({
  id: 'a1', role: 'architect', label: 'scope', model: 'opus', state: 'working',
  activity: { kind: 'tool', text: 'reading .vbw/spec.md' },
  startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 41_200, result: null, ...over,
})
const run = (agents, over = {}) => ({
  runId: 'wf_1', kind: 'planning', phase: 'wave 1 of 2', startedAt: NOW - 604 * S, endedAt: null, status: 'running', agents, ...over,
})
const model = (input) => stage.stageModel({ now: NOW, maxRows: 12, columns: 100, motion: 'full', ...input })
const gate = (action, detail = {}, over = {}) => next({ action, gate: true, instruction: 'Do the ' + action, detail, ...over })
const fills = (m) => m.buttons.filter((b) => b.action.fill).map((b) => b.action.fill)

// --- nothing to show ---------------------------------------------------------

test('nothing runs and nothing is needed: the band draws nothing (the hint line covers it)', () => {
  assert.equal(model({ run: null, next: next() }), null)
  assert.equal(model({}), null)
  assert.equal(stage.stageModel(), null)
  assert.equal(stage.stageModel(null), null)
  assert.equal(model({ run: run([]), next: next() }), null, 'a run without agents yet has no crew to show')
})

test('garbage in never throws and gives null or a model', () => {
  const bad = [42, 'x', [], { run: 'x' }, { run: { agents: 'x' } }, { run: run([null, 7, 'a', {}]) },
    { next: { gate: true, action: 7, detail: 'x' } }, { run: run([agent({ activity: 5, tokens: 'x', startedAt: 'y' })]) },
    { next: gate('accept', { requirements: 'R1' }), health: 'x' }, { health: { contextPct: 'x' }, next: next() }]
  for (const b of bad) assert.doesNotThrow(() => stage.stageModel(typeof b === 'object' && b && !Array.isArray(b) ? { now: NOW, ...b } : b))
  const m = model({ run: run([null, 7, {}, agent()]) })
  assert.equal(m.rows.length, 1, 'only the well-formed agent is drawn')
})

test('the input is never changed', () => {
  const input = deepFreeze({ run: run([agent(), agent({ id: 'a2', state: 'done', endedAt: NOW - 5 * S, result: 'ok' })]), next: gate('approve'),
    now: NOW, maxRows: 12, columns: 100, motion: 'full', health: { contextPct: 90, weekPct: 85 } })
  assert.doesNotThrow(() => stage.stageModel(input))
})

// --- the gate card -----------------------------------------------------------

test('approve: VBW needs you, with Review plan, Approve…, Discuss and Later', () => {
  const m = model({ next: gate('approve') })
  assert.equal(m.kind, 'gate')
  assert.match(m.title, /^⚑ VBW needs you · \S/)
  assert.match(m.title, /plan/i)
  assert.deepEqual(m.buttons, [
    { key: '1', label: 'Review plan', action: { open: 'mission', tab: 'plan' } },
    { key: '2', label: 'Approve…', action: { fill: '/vbw:approve' } },
    { key: '3', label: 'Discuss', action: { fill: '/vbw:discuss' } },
    { key: '4', label: 'Later', action: { collapse: true } },
  ])
})

test('approve of test files edited since the approval names the files', () => {
  const m = model({ next: gate('approve', { files: ['tests/a.bats', 'tests/b.bats'] }) })
  assert.match(m.title, /tests\/a\.bats, tests\/b\.bats/)
  assert.ok(fills(m).includes('/vbw:approve'))
})

test('every human gate has a plain sentence and buttons that only fill, open or collapse', () => {
  const cases = {
    approve: [{}, '/vbw:approve'], accept: [{ requirements: ['R1', 'R2'] }, '/vbw:verify'], ship: [{}, '/vbw:vibe'],
    milestone: [{}, '/vbw:vibe'], spec: [{}, '/vbw:vibe'], escalate: [{ fixes: ['F1'] }, '/vbw:vibe'],
    unblock: [{ plans: ['P5.1'] }, '/vbw:vibe'], scope: [{ violations: [] }, '/vbw:vibe'], convert: [{}, '/vbw:convert'],
  }
  const keys = new Set()
  for (const [action, [detail, main]] of Object.entries(cases)) {
    const m = model({ next: gate(action, detail) })
    assert.equal(m.kind, 'gate', action)
    assert.match(m.title, /^⚑ VBW needs you · [a-z]/, action)
    assert.ok(fills(m).includes(main), action + ' fills ' + main)
    for (const b of m.buttons) {
      const a = Object.keys(b.action)
      assert.ok(['fill', 'open', 'collapse'].includes(a[0]), action + ': ' + JSON.stringify(b))
      assert.ok(!('submit' in b.action), 'a human gate is never answered for the human')
      if (b.action.fill) assert.match(b.action.fill, /^\/(vbw:[a-z]+|compact)$/)
    }
    const digits = m.buttons.map((b) => b.key)
    assert.deepEqual(digits, digits.map((_, i) => String(i + 1)), action + ': hotkeys run 1..n')
    assert.deepEqual(m.buttons.at(-1), { key: String(m.buttons.length), label: 'Later', action: { collapse: true } })
    keys.add(m.key)
  }
  assert.equal(keys.size, Object.keys(cases).length, 'each gate has its own key, for "Later"')
})

test('accept, escalate and unblock name what they are about', () => {
  assert.match(model({ next: gate('accept', { requirements: ['R7', 'R8'] }) }).title, /R7, R8/)
  assert.match(model({ next: gate('escalate', { fixes: ['F3'] }) }).title, /F3/)
  assert.match(model({ next: gate('unblock', { plans: ['P5.1'] }) }).title, /P5\.1/)
  const many = model({ next: gate('accept', { requirements: ['R1', 'R2', 'R3', 'R4', 'R5'] }) }).title
  assert.match(many, /R1, R2, R3 \+2 more/)
  assert.notEqual(model({ next: gate('accept', { requirements: ['R1'] }) }).key, model({ next: gate('accept', { requirements: ['R2'] }) }).key)
})

test('an unknown gate still says something plain and offers /vbw:vibe', () => {
  const m = model({ next: gate('newthing', {}, { instruction: 'Look at the new thing' }) })
  assert.match(m.title, /Look at the new thing/)
  assert.deepEqual(fills(m), ['/vbw:vibe'])
})

// --- health nudges (§3.8) ----------------------------------------------------

test('weekly limit at 80% or more adds a line to a gate that starts a run; not below 80', () => {
  const m = model({ next: gate('approve'), health: { contextPct: 10, weekPct: 84, weekPerRun: 6 } })
  const line = m.lines.find((l) => /Weekly limit/.test(l.text))
  assert.match(line.text, /Weekly limit 84%: a run like this used about 6% last time/)
  assert.equal(line.color, 'yellow')
  assert.equal(model({ next: gate('approve'), health: { weekPct: 93 } }).lines[0].color, 'red')
  assert.match(model({ next: gate('approve'), health: { weekPct: 93 } }).lines[0].text, /^Weekly limit 93%/)
  assert.equal(model({ next: gate('approve'), health: { weekPct: 79 } }).lines.length, 0)
  assert.equal(model({ next: gate('ship'), health: { weekPct: 95 } }).lines.length, 0, 'shipping starts no run')
})

test('context at 85% or more offers /compact first, as a fill, never a compaction', () => {
  const m = model({ next: gate('approve'), health: { contextPct: 88 } })
  const c = m.buttons.find((b) => b.key === 'c')
  assert.deepEqual(c, { key: 'c', label: '/compact first', action: { fill: '/compact' } })
  assert.equal(m.buttons.at(-2).label, 'Later', 'Later keeps its digit; c comes after')
  assert.equal(model({ next: gate('approve'), health: { contextPct: 84 } }).buttons.find((b) => b.key === 'c'), undefined)
  assert.equal(model({ next: gate('accept', { requirements: ['R1'] }), health: { contextPct: 95 } }).buttons.find((b) => b.key === 'c'), undefined)
})

test('a run about to start without a gate shows a nudge only when health asks for it', () => {
  const m = model({ next: next({ action: 'build' }), health: { contextPct: 90, weekPct: 50 } })
  assert.equal(m.kind, 'nudge')
  assert.doesNotMatch(m.title, /needs you/)
  assert.match(m.title, /build/)
  assert.ok(m.buttons.some((b) => b.action.fill === '/compact'))
  assert.ok(m.buttons.some((b) => b.action.collapse === true))
  assert.equal(model({ next: next({ action: 'build' }), health: { contextPct: 50, weekPct: 50 } }), null)
  assert.equal(model({ next: next({ action: 'prove' }), health: { contextPct: 99 } }), null, 'prove starts no workflow')
})

// --- the crew (§3.1) ---------------------------------------------------------

test('the header: kind, phase, elapsed, cost when known, and Mission Control on p', () => {
  const m = model({ run: run([agent()]), cost: 3.2 })
  assert.equal(m.kind, 'crew')
  assert.equal(m.header.text, 'VBW ▸ planning · wave 1 of 2 · 10m04s · ≈$3.20 this run')
  assert.deepEqual(m.header.button, { key: 'p', label: 'Mission Control', action: { open: 'mission' } })
  assert.equal(model({ run: run([agent()], { phase: null }) }).header.text, 'VBW ▸ planning · 10m04s')
  assert.equal(model({ run: run([agent()], { startedAt: NOW - 3725 * S }) }).header.text, 'VBW ▸ planning · wave 1 of 2 · 1h02m')
})

test('a running crew wins over a stale gate in next.json (the kernel holds the lease)', () => {
  assert.equal(model({ run: run([agent()]), next: gate('approve') }).kind, 'crew')
})

test('an agent row: role dot in its colour, role, label, activity, elapsed and tokens', () => {
  const r = model({ run: run([agent()]) }).rows[0]
  assert.equal(r.glyph, '●')
  assert.equal(r.glyphColor, 'magenta')
  assert.equal(r.role, 'architect')
  assert.equal(r.label, 'scope')
  assert.match(r.activity, /reading \.vbw\/spec\.md/)
  assert.equal(r.elapsed, '2m10s')
  assert.equal(r.tokens, '41k')
  const colours = { architect: 'magenta', lead: 'blue', dev: 'green', qa: 'yellow', scout: 'cyan', debugger: 'red', docs: '#ff87d7', agent: 'gray', mystery: 'gray' }
  for (const [role, c] of Object.entries(colours)) assert.equal(model({ run: run([agent({ role })]) }).rows[0].roleColor, c, role)
})

test('streamed text is quoted; tokens read as k or M; none is blank', () => {
  const rows = model({ run: run([
    agent({ id: 'a', activity: { kind: 'text', text: 'Splitting R69 into two plans' }, tokens: 950 }),
    agent({ id: 'b', tokens: 1_250_000 }), agent({ id: 'c', tokens: null, activity: null }),
  ]) }).rows
  assert.equal(rows[0].activity, '"Splitting R69 into two plans"')
  assert.equal(rows[0].tokens, '950')
  assert.equal(rows[1].tokens, '1.3M')
  assert.equal(rows[2].tokens, '')
  assert.equal(rows[2].activity, 'working')
})

test('the spinner cycles with time unless motion is off (where no sprite moves instead)', () => {
  const at = (now, motion) => stage.stageModel({ run: run([agent()]), now, maxRows: 5, columns: 100, motion }).rows[0].spin
  const frames = new Set([0, 1, 2, 3, 4, 5].map((i) => at(NOW + i * 250, 'full')))
  assert.ok(frames.size > 1, 'full motion moves')
  assert.equal(new Set([0, 1, 2, 3].map((i) => at(NOW + i * 1000, 'off'))).size, 1, 'motion off stands still')
})

test('quiet: no sign of life for 45 s is marked quiet in grey, told apart from slow', () => {
  const r = model({ run: run([agent({ lastSeenAt: NOW - 46 * S })]) }).rows[0]
  assert.match(r.activity, /^quiet/)
  assert.equal(r.activityColor, 'gray')
  assert.equal(r.spin, '')
  assert.match(model({ run: run([agent({ state: 'quiet' })]) }).rows[0].activity, /^quiet/)
  assert.doesNotMatch(model({ run: run([agent({ lastSeenAt: NOW - 44 * S })]) }).rows[0].activity, /quiet/)
})

test('done: ✓ in green with its result for 60 s, then counted in the tally', () => {
  const done = (ago) => agent({ id: 'd', role: 'scout', state: 'done', endedAt: NOW - ago * S, result: '4 findings' })
  const m = model({ run: run([agent(), done(30)]) })
  const r = m.rows.find((x) => x.id === 'd')
  assert.equal(r.glyph, '✓')
  assert.equal(r.glyphColor, 'green')
  assert.equal(r.activity, 'done · 4 findings')
  assert.equal(m.tally, null)
  const later = model({ run: run([agent(), done(61), done(90)]) })
  assert.equal(later.rows.length, 1)
  assert.equal(later.tally, '2 done')
})

test('failed: ✗ in red with its reason and a details button; only the first takes d', () => {
  const failed = (id) => agent({ id, role: 'dev', state: 'failed', endedAt: NOW - 3 * S, result: 'bats exited 1' })
  const m = model({ run: run([failed('f1'), failed('f2')]) })
  const [a, b] = m.rows
  assert.equal(a.glyph, '✗')
  assert.equal(a.glyphColor, 'red')
  assert.equal(a.activity, 'bats exited 1')
  assert.deepEqual(a.button, { key: 'd', label: 'details', action: { open: 'mission', tab: 'now', agent: 'f1' } })
  assert.equal(b.button.key, undefined, 'one hotkey, one button')
  assert.equal(b.button.action.agent, 'f2')
  assert.equal(model({ run: run([agent({ state: 'failed', result: null })]) }).rows[0].activity, 'failed')
})

test('a finished run stays for 60 s, then a gate or nothing takes the band', () => {
  const ended = (ago) => run([agent({ state: 'done', endedAt: NOW - ago * S, result: 'ok' })], { status: 'completed', endedAt: NOW - ago * S })
  const m = model({ run: ended(10) })
  assert.equal(m.kind, 'crew')
  assert.match(m.header.text, /completed/)
  assert.equal(model({ run: ended(61) }), null)
  assert.equal(model({ run: ended(10), next: gate('approve') }).kind, 'gate', 'the gate is the news')
})

// --- shrinking and width -----------------------------------------------------

const crew = [agent({ id: 'a' }), agent({ id: 'b', role: 'lead', label: 'P53' }), agent({ id: 'c', role: 'dev', label: 'P53.2' })]

test('full rows at 8 rows of room, compact at 4, one summary line below that', () => {
  const full = model({ run: run(crew), maxRows: 8 })
  assert.equal(full.mode, 'full')
  assert.equal(full.rows.length, 3)
  assert.ok(full.rows.every((r) => r.elapsed && r.tokens))
  const compact = model({ run: run(crew), maxRows: 5 })
  assert.equal(compact.mode, 'compact')
  assert.equal(compact.rows.length, 3)
  assert.ok(compact.rows.every((r) => r.elapsed === '' && r.tokens === ''))
  const one = model({ run: run([...crew, agent({ id: 'z', state: 'done', endedAt: NOW - 120 * S })]), maxRows: 3 })
  assert.equal(one.mode, 'line')
  assert.equal(one.rows.length, 0)
  assert.equal(one.header.text, 'VBW ▸ planning · 3 working · 1 done · 10m04s')
})

test('more agents than rows: the overflow is counted, never drawn past the room', () => {
  const many = Array.from({ length: 12 }, (_, i) => agent({ id: 'x' + i }))
  const m = model({ run: run(many), maxRows: 8 })
  assert.ok(1 + m.rows.length + (m.more ? 1 : 0) + (m.tally ? 1 : 0) <= 8)
  assert.equal(m.more, 12 - m.rows.length)
})

test('every line fits the columns', () => {
  const long = agent({ activity: { kind: 'text', text: 'x'.repeat(300) }, label: 'a-very-long-label-indeed' })
  for (const columns of [30, 50, 80, 140]) {
    for (const maxRows of [3, 5, 10]) {
      const tree = stage.renderStage(UI, model({ run: run([long, ...crew]), cost: 12.5, columns, maxRows }))
      walk(tree, (n) => {
        if (n.type === 'Box' && n.props.flexDirection === 'row' && n.props.key !== 'buttons') {
          const t = collect(n).join('')
          assert.ok(len(t) <= columns, columns + 'x' + maxRows + ': ' + len(t) + ' ' + t)
        }
      })
    }
  }
  const g = model({ next: gate('accept', { requirements: Array.from({ length: 40 }, (_, i) => 'REQUIREMENT-' + i) }), columns: 40 })
  assert.ok(len(g.title) <= 40)
  assert.match(g.title, /…$/)
})

// --- rendering ---------------------------------------------------------------

test('render: nothing for nothing, and never throws on a bad model', () => {
  assert.equal(stage.renderStage(UI, null), null)
  assert.equal(stage.renderStage(UI, { kind: 'crew' }), null)
  assert.equal(stage.renderStage(null, model({ next: gate('approve') })), null)
})

test('render the gate card: the title, the health lines and one Button per choice, with hotkeys', () => {
  const pressed = []
  const tree = stage.renderStage(UI, model({ next: gate('approve'), health: { weekPct: 84, contextPct: 90 } }), (a) => pressed.push(a))
  assert.equal(tree.type, 'Box')
  assert.equal(tree.props.flexDirection, 'column')
  const texts = collect(tree)
  assert.match(texts[0], /^⚑ VBW needs you/)
  assert.ok(texts.some((t) => /Weekly limit 84%/.test(t)))
  const buttons = []
  walk(tree, (n) => n.type === 'Button' && buttons.push(n))
  assert.deepEqual(buttons.map((b) => [b.props.hotkey, b.props.label]), [['1', 'Review plan'], ['2', 'Approve…'], ['3', 'Discuss'], ['4', 'Later'], ['c', '/compact first']])
  assert.equal(new Set(buttons.map((b) => b.props.key)).size, buttons.length, 'each Button has its own key')
  buttons[1].props.onPress()
  assert.deepEqual(pressed, [{ fill: '/vbw:approve' }])
  const title = find(tree, (n) => n.type === 'Text' && /needs you/.test(collect(n)[0]))
  assert.equal(title.props.color, 'yellow')
})

test('render without a press handler still draws the buttons, with no onPress', () => {
  const tree = stage.renderStage(UI, model({ next: gate('ship') }))
  const b = find(tree, (n) => n.type === 'Button')
  assert.equal(b.props.onPress, undefined)
})

test('render the crew: the header with its button, then one row per agent, colours on Text', () => {
  const pressed = []
  const m = model({ run: run([agent(), agent({ id: 'f', role: 'dev', state: 'failed', result: 'boom', endedAt: NOW })]), cost: 1 })
  const tree = stage.renderStage(UI, m, (a) => pressed.push(a))
  const header = find(tree, (n) => n.type === 'Box' && n.props.key === 'header')
  assert.match(collect(header)[0], /^VBW ▸ planning/)
  const mc = find(header, (n) => n.type === 'Button')
  assert.equal(mc.props.hotkey, 'p')
  mc.props.onPress()
  assert.deepEqual(pressed, [{ open: 'mission' }])
  const dot = find(tree, (n) => n.type === 'Text' && collect(n)[0] === '●')
  assert.equal(dot.props.color, 'magenta')
  const cross = find(tree, (n) => n.type === 'Text' && collect(n)[0] === '✗')
  assert.equal(cross.props.color, 'red')
  const details = find(tree, (n) => n.type === 'Button' && n.props.label === 'details')
  assert.equal(details.props.hotkey, 'd')
  walk(tree, (n) => {
    if (n.type === 'Text') for (const c of n.children) assert.equal(typeof c, 'string')
  })
})

// --- the crew theme (full motion) ---------------------------------------------

const candy = await import(pathToFileURL(PLUGIN + '/hooks/panel-candy.js').href)
const RUI = { ...UI, Raster: Object.freeze({ element: 'Raster' }) }
const posed = [
  agent(), agent({ id: 'b', role: 'lead', activity: { kind: 'text', text: 'Splitting' } }),
  agent({ id: 'c', role: 'dev', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }),
  agent({ id: 'q', role: 'qa', lastSeenAt: NOW - 46 * S }),
]

test('full motion with room for them: sprites, each agent posed by what it does', () => {
  const m = model({ run: run([...posed, agent({ id: 'f', role: 'scout', state: 'failed', result: 'boom', endedAt: NOW })]), maxRows: 16 })
  assert.equal(m.sprites, true)
  assert.ok(m.rows.every((r) => r.spin === ''), 'the sprite is the motion')
  assert.deepEqual(m.rows.map((r) => r.pose), ['reading', 'streaming', 'done', 'quiet', 'failed'])
  const ed = model({ run: run([agent({ activity: { kind: 'tool', text: 'editing panel.js' } })]) })
  assert.equal(ed.rows[0].pose, 'editing')
})

test('no sprites when calm or off, after the run ended, or without three rows of room per agent', () => {
  for (const motion of ['calm', 'off', undefined]) assert.ok(!model({ run: run(posed), maxRows: 16, motion }).sprites, String(motion))
  assert.ok(!model({ run: run(posed, { status: 'completed', endedAt: NOW - 5 * S }), maxRows: 16 }).sprites, 'a finished run')
  const tight = model({ run: run(posed), maxRows: 12 })
  assert.equal(tight.mode, 'full')
  assert.ok(!tight.sprites, '1 + 4 x 3 rows do not fit in 12')
  assert.ok(tight.rows.every((r) => r.pose === undefined))
})

test('render sprites: one 5x3 Raster per agent in place of its dot and spinner; a table without Raster draws dots', () => {
  const m = model({ run: run(posed), maxRows: 16, columns: 60 })
  const tree = stage.renderStage(RUI, m)
  const rasters = []
  walk(tree, (n) => n.type === 'Raster' && rasters.push(n))
  assert.deepEqual(rasters.map((r) => r.props.key), ['vbw-sprite-a1', 'vbw-sprite-b', 'vbw-sprite-c', 'vbw-sprite-q'])
  assert.deepEqual([rasters[0].props.columns, rasters[0].props.rows], [5, 3])
  assert.equal(rasters[0].props.cells, candy.encodeCells(candy.spriteFrame({ role: 'architect', pose: 'reading', frame: 0 })))
  const texts = collect(tree)
  assert.ok(!texts.some((t) => t === '●' || /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/.test(t)), texts.join('|'))
  const long = [agent({ activity: { kind: 'tool', text: 'x'.repeat(200) } }), agent({ id: 'c', state: 'done', endedAt: NOW - 5 * S, result: 'y'.repeat(200) })]
  for (const columns of [40, 60, 100]) {
    walk(stage.renderStage(RUI, model({ run: run(long), maxRows: 16, columns })), (n) => {
      if (n.type === 'Box' && /^agent-/.test(n.props.key || '')) assert.ok(len(collect(n).join('')) + 5 <= columns, columns + ': ' + collect(n).join(''))
    })
  }
  const plain = stage.renderStage(UI, m)
  assert.ok(collect(plain).includes('●'))
  assert.equal(find(plain, (n) => n.type === 'Raster'), undefined)
})

test('render the tally and the overflow as dim lines', () => {
  const many = Array.from({ length: 12 }, (_, i) => agent({ id: 'x' + i }))
  const done = agent({ id: 'd', state: 'done', endedAt: NOW - 120 * S })
  const tree = stage.renderStage(UI, model({ run: run([...many, done]), maxRows: 8 }))
  const dims = []
  walk(tree, (n) => n.type === 'Text' && n.props.dimColor && dims.push(collect(n)[0]))
  assert.ok(dims.some((t) => /^\+\d+ more$/.test(t)), dims.join('|'))
  assert.ok(dims.some((t) => t === '1 done'), dims.join('|'))
})

test('colour off: the band reads state from the palette marks, running, done and failed apart', async () => {
  const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
  const m = model({ run: run([agent({ id: 'w' }), agent({ id: 'd', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }), agent({ id: 'f', state: 'failed', endedAt: NOW - 5 * S, result: 'boom' })]), maxRows: 16, columns: 80 })
  const glyph = (id) => m.rows.find((r) => r.id === id).glyph
  assert.deepEqual([glyph('w'), glyph('d'), glyph('f')], [P.STATE_MARKS.running, P.STATE_MARKS.done, P.STATE_MARKS.failed])
  assert.equal(new Set([glyph('w'), glyph('d'), glyph('f')]).size, 3)
})
