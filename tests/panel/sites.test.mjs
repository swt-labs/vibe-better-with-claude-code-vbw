// VBW's one-line surfaces, transcript rows and instant commands (mods_4_vbw.md
// §2, §3.4-§3.6), wired: each render hook has a matcher, draws from what the
// timer gathered, and leaves the engine's own drawing when it has nothing to say
// or anything fails. Driven through the stand-in for Claude Code's mods API (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, lease, collect, find, walk, PLUGIN, ROOT, T0 } from './helpers/fake-mod.mjs'
import { ENV, writeRun, finish, launch } from './helpers/run.mjs'

async function started(options = {}, rec = record(), nxt = next()) {
  const h = await mount({ env: ENV, ...options })
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return h
}
const text = (tree) => collect(tree).join('\n')
const isEngine = (x, component) => x && x.type === 'engine' && x.ref === component
async function running(rec = record({ lease: lease('plan', T0) })) {
  const h = await started({}, rec, next({ action: 'run' }))
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
  return h
}

// ---- spinner, hint, footer ----

const SPINNER = { word: 'Sauteing', message: null, suffix: '…', mode: 'responding' }

test('spinner: while a VBW run is live its suffix says what VBW does; otherwise the engine\'s', async () => {
  const idle = await started()
  assert.equal((await idle.draw('Spinner', SPINNER)).props.suffix, '…')
  const h = await running()
  assert.equal((await h.draw('Spinner', SPINNER)).props.suffix, ' · VBW planning · Plan…')
})

test('hint line: the run and its time, the gate, or the next step', async () => {
  const hint = async (h) => (await h.draw('PromptHint', { isDraft: false, isWorking: false, hint: '? for shortcuts' })).props.tail
  assert.equal(await hint(await started()), 'VBW next: /vbw:vibe')
  assert.equal(await hint(await started({}, record(), next({ action: 'approve', gate: true }))), 'VBW needs you: /vbw:approve')
  assert.match(await hint(await running()), /^VBW: planning \d+s$/)
})

test('footer: an armed autonomous run shows its steps, else the profile in plain words', async () => {
  const modes = async (h) => (await h.draw('SessionMode', { modes: ['accept edits'] })).props.modes
  assert.deepEqual(await modes(await started()), ['accept edits', 'VBW standard'])
  const h = await started({ files: { [ROOT + '/.vbw/runtime/auto.sess-1.json']: JSON.stringify({ session: 'sess-1', steps: 3, cap: 10 }) } })
  assert.deepEqual(await modes(h), ['accept edits', 'VBW auto ⟳ 3/10'])
  h.remove(ROOT + '/.vbw/runtime/auto.sess-1.json')
  await h.advance(2000)
  assert.deepEqual(await modes(h), ['accept edits', 'VBW standard'], 'disarmed: back to the profile')
})

// ---- startup notice and questions ----

test('startup notice: one VBW line under the first notice only', async () => {
  const h = await started()
  const first = await h.draw('InfoNotice', { text: 'Using Opus', command: null }, { requestId: 'n1' })
  assert.match(text(first), /VBW M9 · 0\/0 · next: \/vbw:vibe/)
  assert.ok(find(first, (n) => n.type === 'engine'), 'the engine\'s notice stays')
  assert.ok(isEngine(await h.draw('InfoNotice', { text: 'Other', command: null }, { requestId: 'n2' }), 'InfoNotice'))
  assert.match(text(await h.draw('InfoNotice', { text: 'Using Opus', command: null }, { requestId: 'n1' })), /VBW M9/, 'the same notice drawn again keeps it')
})

test('question dialog: a VBW header above it, the engine\'s dialog kept exactly once', async () => {
  const h = await started()
  const tree = await h.draw('AskUserQuestion', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] })
  assert.match(text(tree), /VBW · a decision for M9/)
  let engines = 0
  walk(tree, (n) => { if (n.type === 'engine') engines++ })
  assert.equal(engines, 1)
})

// ---- receipts in the transcript ----

test('turn receipt: a turn that moved VBW on says what moved; any other turn keeps the engine\'s line', async () => {
  const h = await started()
  await h.fire('prompt.submit', { text: '/vbw:vibe' })
  h.project(record({ plans: [{ id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'done' }] }))
  const tree = await h.draw('TurnDuration', { word: 'Baked', durationMs: 3000 }, { requestId: 't1' })
  assert.equal(text(tree), 'VBW · P44.1 done · 3s')
  await h.fire('prompt.submit', { text: 'hello' })
  assert.ok(isEngine(await h.draw('TurnDuration', { word: 'Baked', durationMs: 2000 }, { requestId: 't2' }), 'TurnDuration'))
  assert.equal(text(await h.draw('TurnDuration', { word: 'Baked', durationMs: 3000 }, { requestId: 't1' })), 'VBW · P44.1 done · 3s', 'kept for its own row')
})

test('Workflow row: a VBW run draws as a run card; another workflow keeps its row', async () => {
  const h = await running()
  const card = await h.draw('ToolUse', { tool_use_id: 'tu-wf-1', tool: 'Workflow', input: { name: 'vbw:planning' }, isRunning: false, isErrored: false, isInterrupted: false })
  assert.match(text(card), /^VBW planning · started \d\d:\d\d · \[p\] watch live$/)
  const other = await h.draw('ToolUse', { tool_use_id: 'x', tool: 'Workflow', input: { name: 'mine' }, isRunning: false, isErrored: false, isInterrupted: false })
  assert.ok(isEngine(other, 'ToolUse'))
})

test('vbw rows draw as what VBW did; other commands and failed calls keep their row', async () => {
  const h = await started()
  const row = (command, isErrored = false) => h.draw('ToolUse', { tool_use_id: 'b', tool: 'Bash', input: { command }, isRunning: false, isErrored, isInterrupted: false })
  assert.equal(text(await row('"' + PLUGIN + '/bin/vbw" plan done P44.1')), 'VBW · recorded P44.1 done')
  assert.ok(isEngine(await row('ls -la'), 'ToolUse'))
  assert.ok(isEngine(await row('vbw plan done P44.1', true), 'ToolUse'))
})

test('run receipt: the notification of a finished VBW run says what it produced; expanded rows stay whole', async () => {
  const h = await running()
  finish(h, h.now() - 840000)
  await h.advance(2000)
  const props = { text: 'Workflow finished', origin: { kind: 'task-notification' }, isExpanded: false, task: { toolUseId: 'tu-wf-1', status: 'completed', type: 'local_workflow' } }
  assert.match(text(await h.draw('UserMessage', props)), /^✓ VBW planning finished · 5 phases · 2 plans · 0 checks · 14m/)
  assert.ok(isEngine(await h.draw('UserMessage', { ...props, isExpanded: true }), 'UserMessage'))
  assert.ok(isEngine(await h.draw('UserMessage', { ...props, origin: { kind: 'composer' } }), 'UserMessage'))
})

// ---- instant commands ----

test('/vbw-status, /vbw-why and /vbw-todo are registered next to /vbw-panel and /vbw-sound, all instant', async () => {
  const h = await started()
  const regs = h.callsOf('command.register').map((a) => a[0])
  for (const name of ['vbw-panel', 'vbw-sound', 'vbw-status', 'vbw-why', 'vbw-todo']) {
    const r = regs.find((x) => x.name === name)
    assert.ok(r, name)
    assert.equal(r.immediate, true, name)
  }
})

test('/vbw-status and /vbw-why answer from the record at once', async () => {
  const h = await started()
  assert.match((await h.cmd('vbw-status')).text, /Working on M9: Live VBW panel\./)
  assert.equal((await h.cmd('vbw-why')).text, 'Nothing is running and nothing is blocked.')
})

test('/vbw-todo parks the idea through the kernel and says what it said', async () => {
  const h = await started()
  const out = await h.cmd('vbw-todo', 'try a dark theme')
  assert.deepEqual(h.callsOf('process.run').at(-1), [[PLUGIN + '/bin/vbw', 'todo', 'add', 'try a dark theme'], { cwd: ROOT }])
  assert.equal(out.text, 'added T1: try a dark theme')
})

test('/vbw-todo with no text takes the selection; with neither it explains and runs nothing', async () => {
  const sel = await started({ selection: { text: 'cache the map' } })
  await sel.cmd('vbw-todo')
  assert.equal(sel.callsOf('process.run').at(-1)[0].at(-1), 'cache the map')
  const none = await started()
  const out = await none.cmd('vbw-todo')
  assert.match(out.text, /Usage: \/vbw-todo TEXT/)
  assert.equal(none.count('process.run'), 0)
})

test('/vbw-todo reports a kernel failure plainly', async () => {
  const h = await started({ process: () => ({ exitCode: 1, stdout: '', stderr: 'vbw: no project\n' }) })
  assert.equal((await h.cmd('vbw-todo', 'x')).text, 'vbw: no project')
  const k = await started({ process: () => { throw new Error('cannot start') } })
  assert.match((await k.cmd('vbw-todo', 'x')).text, /could not run/i)
})

// ---- staying out of the way ----

test('every site leaves the engine\'s drawing outside a VBW project, and on garbage', async () => {
  const sites = [['Spinner', SPINNER], ['PromptHint', { hint: '' }], ['SessionMode', { modes: [] }], ['InfoNotice', { text: 'x', command: null }],
    ['AskUserQuestion', { tool: 'AskUserQuestion', questions: [] }], ['TurnDuration', { durationMs: 1 }],
    ['ToolUse', { tool: 'Bash', input: { command: 'vbw next' } }], ['UserMessage', { origin: { kind: 'task-notification' }, isExpanded: false }]]
  const out = await mount({ env: ENV })
  out.write(ROOT + '/README.md', 'x')
  await out.start()
  for (const [c, p] of sites) {
    const drawn = await out.draw(c, p)
    assert.ok(isEngine(drawn, c), c)
    assert.deepEqual(drawn.props, p, c + ' props untouched')
  }
  const bad = await started()
  bad.write(ROOT + '/.vbw/record.json', '{"milestone": 7, "plans": "x"}')
  await bad.advance(4000)
  for (const [c, p] of sites) await bad.draw(c, { ...p, input: null, origin: null })
  assert.deepEqual(bad.errors, [])
})

test('a run in this session is never mistaken for another: the receipt needs this session\'s run', async () => {
  const h = await started()
  const props = { text: 'done', origin: { kind: 'task-notification' }, isExpanded: false, task: { toolUseId: 'unknown', type: 'local_workflow' } }
  assert.ok(isEngine(await h.draw('UserMessage', props), 'UserMessage'))
})
