// R53: where the panel cannot run it does nothing at all: on Claude Code older
// than 2.1.287, outside a VBW project, and when Claude Code's own calls fail.
// No panel, no command, no timer, no error (L1, stand-in for the mods API).
import test from 'node:test'
import assert from 'node:assert/strict'
import { mount, record, next, ROOT } from './helpers/fake-mod.mjs'

const NOTHING = ['command.register', 'clock.every', 'clock.after', 'ui.open', 'audio.play', 'ui.toast', 'ui.log', 'ui.status']

async function assertInert(h) {
  await h.start()
  await h.advance(10000)
  await h.cmd('vbw-panel')
  await h.cmd('vbw-sound', 'off')
  for (const name of NOTHING) assert.equal(h.count(name), 0, name + ' was called')
  assert.deepEqual(await h.render(), { type: 'engine', ref: 'default' }, 'no pane is drawn')
  assert.deepEqual(h.errors, [], 'no hook failed')
}

test('on Claude Code older than 2.1.287 the panel does nothing at all', async () => {
  for (const version of ['2.1.286', '2.0.5', '1.0.0']) {
    const h = await mount({ version })
    h.project(record(), next())
    await assertInert(h)
    assert.equal(h.count('fs.read'), 0, 'no project file was read on ' + version)
  }
})

test('a version that cannot be read is treated as one without mods', async () => {
  const h = await mount({ version: 'garbage' })
  h.project(record(), next())
  await assertInert(h)
})

test('on 2.1.287 and newer, in a VBW project, the panel starts', async () => {
  for (const version of ['2.1.287', '2.1.289', '2.2.0']) {
    const h = await mount({ version })
    h.project(record(), next())
    await h.start()
    assert.ok(h.count('command.register') >= 1, 'commands registered on ' + version)
    assert.ok(h.count('clock.every') >= 1, 'a refresh timer on ' + version)
  }
})

test('outside a VBW project (no .vbw folder) there is no panel, no command and no error', async () => {
  const h = await mount()
  h.write(ROOT + '/README.md', 'hello')
  await assertInert(h)
})

test('a folder with a VBW 1 plan but no VBW 2 record is not a VBW 2 project', async () => {
  const h = await mount()
  h.write(ROOT + '/.vbw-planning/STATE.md', 'old')
  await assertInert(h)
})

test('when Claude Code answers with failures the panel stays quiet', async () => {
  const h = await mount({ usageError: true })
  h.project(record(), next())
  await h.start()
  await h.advance(10000)
  await h.render()
  assert.deepEqual(h.errors, [])
})

test('garbage in the project files never makes a hook fail', async () => {
  for (const bad of ['{"phases": 7, "milestone": []}', '[]', '"x"', '\u0000\u0001', '{"lease": {"kind": 5}, "milestone": {"id": 1}}']) {
    const h = await mount()
    h.write(ROOT + '/.vbw/record.json', bad)
    h.write(ROOT + '/.vbw/runtime/next.json', bad)
    await h.start()
    await h.advance(6000)
    await h.render()
    assert.deepEqual(h.errors, [], JSON.stringify(bad))
  }
})

// A first session starts in a folder with no project; /vbw:vibe sets it up
// mid-session and asks its first question. No timer runs before the project exists
// (R53): the panel checks again on the hooks it already has.
test('a project set up during the session turns the panel on at the next question or prompt', async () => {
  const h = await mount()
  await h.start()
  await h.fire('prompt.submit', { text: '/vbw:vibe a greeting script' })
  await h.advance(4000)
  for (const name of NOTHING) assert.equal(h.count(name), 0, name + ' before the project exists')
  h.project(record(), next())
  await h.fire('tool.call', { tool: 'AskUserQuestion', questions: [{ question: 'Which?' }] }, async () => ({ result: 'x' }))
  await h.settle()
  assert.ok(h.count('command.register') >= 1, 'the commands are registered')
  assert.equal(h.count('clock.every') >= 1, true, 'the panel timer runs')
  assert.notDeepEqual(await h.render(), { type: 'engine', ref: 'default' }, 'the pane is drawn')
  assert.deepEqual(h.errors, [])
})

test('a prompt sent after the project appeared turns the panel on too', async () => {
  const h = await mount()
  await h.start()
  h.project(record(), next())
  await h.fire('prompt.submit', { text: 'carry on' })
  await h.settle()
  assert.ok(h.count('command.register') >= 1)
})
