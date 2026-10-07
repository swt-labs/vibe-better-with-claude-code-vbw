// The panel module wired to its views (mods_4_vbw.md §2-§4): the run feed learns a
// VBW workflow from its Workflow tool call (or finds it after a reload) and reads it
// on the panel's timer; the band above the prompt draws the Stage (crew, gate card,
// nudges) with buttons that only fill, open or collapse; the pane is Mission Control
// with seven tabs. Driven through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, collect, find, walk, ROOT, T0 } from './helpers/fake-mod.mjs'
import { ENV, SESSION_DIR, RUN, RUN_DIR, ARCH, writeRun, finish, launch, band } from './helpers/run.mjs'

const TEST_MODE = ROOT + '/.vbw/runtime/test-mode'
const approve = () => next({ action: 'approve', gate: true })

async function started(options = {}, rec = record(), nxt = next()) {
  const h = await mount({ env: ENV, ...options })
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return h
}
const texts = (tree) => collect(tree)
const text = (tree) => texts(tree).join('\n')
const buttons = (tree) => { const out = []; walk(tree, (n) => { if (n.type === 'Button') out.push(n) }); return out }
const press = async (h, tree, label) => {
  const b = buttons(tree).find((x) => x.props.label === label)
  assert.ok(b, 'no button ' + label + ' in ' + texts(tree).join(' | '))
  await b.props.onPress({ surface: 'terminal' })
  await h.settle()
}
const isEngine = (x, component) => x && x.type === 'engine' && x.ref === component

// ---- the run feed ----

test('a VBW workflow launched in this session shows its crew in the band within 2 seconds', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  const t = text(await band(h))
  assert.match(t, /VBW ▸ planning/)
  assert.match(t, /architect/)
  assert.match(t, /reading spec\.md/)
  assert.match(t, /"Splitting R69 into two plans"/)
  assert.match(t, /Mission Control/)
  assert.deepEqual(h.errors, [])
})

test('a workflow that is not VBW\'s is not followed', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h, 'someone-else')
  await h.advance(4000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'))
})

test('after a reload, a VBW run already going is found in the session folder, by the session id', async () => {
  const h = await mount({ env: ENV })
  h.project(record({ lease: lease('build', T0) }), next({ action: 'run' }))
  writeRun(h, T0)
  h.write(SESSION_DIR + '/workflows/scripts/building-' + RUN + '.js', 'export const meta = {}')
  await h.start()
  await h.advance(2000)
  assert.match(text(await band(h)), /VBW ▸ building/)
})

test('the Claude config folder follows CLAUDE_CONFIG_DIR when it is set', async () => {
  const h = await mount({ env: { HOME: '/nowhere', CLAUDE_CONFIG_DIR: '/home/u/.claude' } })
  h.project(record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, T0)
  h.write(SESSION_DIR + '/workflows/scripts/planning-' + RUN + '.js', 'export const meta = {}')
  await h.start()
  await h.advance(2000)
  assert.match(text(await band(h)), /architect/)
})

test('agent snippets come from the transcripts: no hook on every tool call or every streamed step (P2)', async () => {
  const h = await started()
  for (const x of h.handlers) {
    if (x.event === 'tool.call') assert.ok(x.matcher && x.matcher.tool, 'a tool.call hook without a tool matcher')
    assert.notEqual(x.event, 'turn.step')
    if (x.event === 'ui.render') assert.ok(x.matcher && x.matcher.component, 'a ui.render hook without a component matcher')
  }
})

test('a run that ends shows done in the band for a minute, then the band is empty', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now(), { journal: [{ type: 'result', agentId: ARCH, result: { summary: 'scope set' } }] })
  await launch(h)
  await h.advance(2000)
  finish(h, h.now() - 840000, 'completed')
  h.project(record(), next())
  await h.advance(2000)
  assert.match(text(await band(h)), /completed/)
  await h.advance(90000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'))
})

// ---- the band: gate card ----

test('an approve gate shows the card; Approve fills /vbw:approve and never sends it', async () => {
  const h = await started({}, record(), approve())
  const tree = await band(h)
  assert.match(text(tree), /VBW needs you/)
  await press(h, tree, 'Approve…')
  assert.deepEqual(h.callsOf('prompt.fill').at(-1)[0], { text: '/vbw:approve' })
  assert.equal(h.count('prompt.submit'), 0)
})

test('an approve gate suggests /vbw:approve once, however many ticks follow', async () => {
  const h = await started()
  h.project(undefined, approve())
  await h.advance(20000)
  assert.deepEqual(h.callsOf('prompt.suggest'), [[{ text: '/vbw:approve' }]])
  h.project(undefined, next({ action: 'accept', gate: true, detail: { requirements: ['R1'] } }))
  await h.advance(4000)
  assert.equal(h.count('prompt.suggest'), 1, 'only the approve gate is suggested')
})

test('Review plan opens Mission Control on its Plan tab', async () => {
  const h = await started({}, record(), approve())
  await press(h, await band(h), 'Review plan')
  const open = h.opens.at(-1)
  assert.equal(open.id, 'vbw-panel')
  assert.equal(open.focus, true)
  const pane = await h.render()
  const active = buttons(pane).find((b) => b.props.key === 'tab-plan')
  assert.equal(active.props.variant, 'primary')
  assert.match(text(pane), /P44 Cost/)
})

test('Later hides the card until the gate changes', async () => {
  const h = await started({}, record(), approve())
  await press(h, await band(h), 'Later')
  assert.ok(isEngine(await band(h), 'AbovePrompt'))
  await h.advance(10000)
  assert.ok(isEngine(await band(h), 'AbovePrompt'), 'still hidden for the same gate')
  h.project(undefined, next({ action: 'ship', gate: true }))
  await h.advance(2000)
  assert.match(text(await band(h)), /ready to ship/)
})

test('a card put off with Later comes back when the same gate is raised again later', async () => {
  const h = await started({}, record(), approve())
  await press(h, await band(h), 'Later')
  h.project(undefined, next())
  await h.advance(2000)
  h.project(undefined, approve())
  await h.advance(2000)
  assert.match(text(await band(h)), /VBW needs you/)
})

test('a survey in the band wins: VBW yields', async () => {
  const h = await started({}, record(), approve())
  assert.ok(isEngine(await band(h, { hasSurvey: true }), 'AbovePrompt'))
})

test('health: a nearly full context offers /compact first, a weekly limit past 80% warns before a run', async () => {
  const usage = { cost: { usd: 2 }, context: { window: 200000, tokens: 180000, percent: 90 }, rateLimits: [{ kind: 'seven_day', percentUsed: 85 }] }
  const h = await started({ usage }, record(), approve())
  const tree = await band(h)
  assert.match(text(tree), /Weekly limit 85%/)
  await press(h, tree, '/compact first')
  assert.deepEqual(h.callsOf('prompt.fill').at(-1)[0], { text: '/compact' })
})

test('no usage figures: the gate card shows without health lines', async () => {
  const h = await started({ usageError: true }, record(), approve())
  const t = text(await band(h))
  assert.match(t, /VBW needs you/)
  assert.doesNotMatch(t, /Weekly|compact/)
})

// ---- motion ----

const spinOf = async (h) => {
  const tree = await band(h)
  const row = find(tree, (n) => n.props && n.props.key === 'agent-' + ARCH)
  return texts(row)
}

test('motion: calm by default (a spinner), off in a test session and when the record says off (a dot)', async () => {
  const calm = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(calm, calm.now())
  await launch(calm)
  await calm.advance(2000)
  assert.ok((await spinOf(calm)).some((t) => /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/.test(t)))

  for (const opts of [{ files: { [TEST_MODE]: '1' } }, {}]) {
    const settings = Object.keys(opts).length ? {} : { motion: 'off' }
    const h = await started(opts, record({ lease: lease('plan', T0), settings }), next({ action: 'run' }))
    writeRun(h, h.now())
    await launch(h)
    await h.advance(2000)
    assert.ok((await spinOf(h)).includes('· '), JSON.stringify(opts))
  }
})

// ---- Mission Control ----

const TABS = ['Now', 'Plan', 'Proof', 'Timeline', 'Decisions', 'Team', 'Costs']

test('the pane is Mission Control: seven tabs, Now first with the panel rows and the sound switch', async () => {
  const h = await started()
  const pane = await h.render()
  assert.deepEqual(buttons(pane).filter((b) => /^tab-/.test(b.props.key)).map((b) => b.props.label), TABS)
  const t = text(pane)
  assert.match(t, /Working on M9/)
  assert.match(t, /Sound is on/)
  assert.match(t, /No VBW workflow runs/)
})

test('each tab draws its view, and the choice holds across redraws', async () => {
  const h = await started({}, record({ settings: { profile: 'quality' }, decisions: [{ id: 'D1', text: 'Which db? sqlite', at: '2026-10-01T00:00:00Z' }] }))
  const want = { Plan: /P44 Cost/, Proof: /No checks are approved/, Timeline: /No VBW workflow runs/, Decisions: /sqlite/, Team: /Profile: quality/, Costs: /This session: \$1\.42/ }
  for (const [tab, re] of Object.entries(want)) {
    await press(h, await h.render(), tab)
    assert.match(text(await h.render()), re, tab)
    await h.advance(4000)
    assert.match(text(await h.render()), re, tab + ' after a tick')
  }
})

test('Now: pressing an agent card shows its detail', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  await press(h, await h.render(), 'architect scope')
  assert.match(text(await h.render()), /Model: opus/)
})

test('a failed agent\'s details button opens Mission Control on that agent', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now(), { journal: [{ type: 'result', agentId: ARCH, error: 'Agent crashed' }] })
  await launch(h)
  await h.advance(2000)
  await press(h, await band(h), 'details')
  assert.match(text(await h.render()), /Result: Agent crashed/)
})

test('Costs: each run costs the session cost moved while its lease was open', async () => {
  const h = await started({ usage: { cost: { usd: 1 } } })
  h.project(record({ lease: lease('plan', h.now()) }), next({ action: 'run' }))
  await h.advance(2000)
  h.setUsage({ cost: { usd: 3.5 } })
  h.project(record(), next())
  await h.advance(2000)
  await press(h, await h.render(), 'Costs')
  const t = text(await h.render())
  assert.match(t, /plan 1/)
  assert.match(t, /about \$2\.50/)
})

test('the crew header shows the cost of the open run', async () => {
  const h = await started({ usage: { cost: { usd: 1 } } }, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  h.setUsage({ cost: { usd: 4.2 } })
  await h.advance(2000)
  assert.match(text(await band(h)), /≈\$3\.20 this run/)
})

test('the plan\'s Ask field is not drawn until it is wired', async () => {
  const h = await started()
  await press(h, await h.render(), 'Plan')
  assert.equal(find(await h.render(), (n) => n.type === 'Input'), undefined)
})

// ---- staying out of the way ----

test('outside a VBW project, or on an old Claude Code, the band and pane draw nothing of VBW', async () => {
  for (const opts of [{}, { version: '2.1.200' }]) {
    const h = await mount({ env: ENV, ...opts })
    if (opts.version) h.project(record(), approve())
    await h.start()
    await launch(h)
    await h.advance(4000)
    assert.ok(isEngine(await band(h), 'AbovePrompt'))
    assert.equal(h.count('prompt.suggest'), 0)
    assert.deepEqual(h.errors, [])
  }
})

test('outside the project it reads only this session\'s own folder, and never settings or credentials', async () => {
  const h = await started({}, record({ lease: lease('plan', T0) }), next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(6000)
  const paths = [...h.callsOf('fs.read'), ...h.callsOf('fs.stat'), ...h.callsOf('fs.exists'), ...h.callsOf('fs.list')].map((a) => a[0])
  for (const p of paths) {
    assert.ok(p === ROOT || p.startsWith(ROOT + '/') || p.startsWith(SESSION_DIR) || p === '/home/u/.config/claude-code', 'outside: ' + p)
    assert.doesNotMatch(p, /credentials|settings\.json|\.ssh/)
  }
  assert.ok(paths.some((p) => p.startsWith(RUN_DIR)), 'the run was read')
})
