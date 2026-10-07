// The instant mod commands (/vbw-status, /vbw-why, /vbw-todo; mods_4_vbw.md §3.6):
// plugin/hooks/panel-commands.js turns the record and the last `vbw next` into
// their text, and an idea into the kernel's argv. Pure data in, value out (L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, next, lease, deepFreeze } from './helpers/fake-mod.mjs'

const cmd = await import(pathToFileURL(PLUGIN + '/hooks/panel-commands.js').href)
const NOW = Date.parse('2026-10-05T15:00:00Z')
const SID = '7f3a9c21-55aa-4d2e-9b1c-0123456789ab'
const REQS = [['R1', 'M9', 'proven'], ['R2', 'M9', 'open'], ['R3', 'M9', 'open']]
  .map(([id, milestone, status]) => ({ id, text: id, proof: 'auto', status, milestone }))
const rec = (over = {}) => record({ requirements: REQS, ...over })
const lines = (s) => s.split('\n')

test('/vbw-status: the milestone, its progress and what VBW is doing, one per line, in the panel\'s words', () => {
  const s = cmd.statusText({ record: rec({ lease: lease('qa', NOW - 4 * 60000) }), next: next({ action: 'run' }), now: NOW })
  assert.deepEqual(lines(s), ['Working on M9: Live VBW panel.', '1 of 3 requirements done.', 'VBW is checking the results (4 min so far).'])
})

test('/vbw-status: when idle it names the next step, or what is needed from the user', () => {
  const idle = lines(cmd.statusText({ record: rec(), next: next({ action: 'build' }), now: NOW }))
  assert.equal(idle[2], 'VBW is idle: nothing is running.')
  assert.equal(idle[3], 'Next: build the plan (/vbw:vibe carries on).')
  const gate = lines(cmd.statusText({ record: rec(), next: next({ action: 'approve', gate: true }), now: NOW }))
  assert.equal(gate[3], 'Please approve the plan before VBW builds it.')
  const none = lines(cmd.statusText({ record: rec(), next: null, now: NOW }))
  assert.equal(none[3], 'Next: run /vbw:vibe.')
  assert.equal(lines(cmd.statusText({ record: rec(), next: next({ action: 'teleport' }), now: NOW }))[3], 'Next: teleport (/vbw:vibe carries on).')
})

test('/vbw-status without a project says so in one line and never throws', () => {
  for (const input of [{}, { record: null }, { record: 'x', next: 5 }, undefined, null]) {
    assert.equal(cmd.statusText(input), 'No VBW project is open here yet.')
  }
})

test('/vbw-why: a run held by this session names it, its short id, when it started, its kind and how many files it may write', () => {
  const l = lease('build', Date.parse('2026-10-05T14:52:00Z'), { session: SID, files: ['a.js', 'b.js', 'c.js'] })
  const s = cmd.whyText({ record: rec({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: SID })
  assert.equal(lines(s)[0], 'A build run is open, held by this session (7f3a9c21) since 14:52 UTC (8 min ago); its agents may write 3 files.')
})

test('/vbw-why: a run of another session says so and to wait, never to end it', () => {
  const l = lease('qa', NOW - 30000, { session: SID, files: [] })
  const s = cmd.whyText({ record: rec({ lease: l }), next: next({ action: 'run' }), now: NOW, sessionId: 'other-session' })
  assert.match(s, /^A qa run is open, held by another session \(7f3a9c21\) since 14:59 UTC \(just started\); its agents write no files\./)
  assert.match(s, /wait/i)
  assert.doesNotMatch(s, /run end|end it/i)
})

test('/vbw-why: files the run may write: any, one, none; and a run with no session named', () => {
  const why = (files, extra = {}) => lines(cmd.whyText({ record: rec({ lease: lease('fix', NOW - 120000, { files, ...extra }) }), next: null, now: NOW, sessionId: SID }))[0]
  assert.match(why(null), /its agents may write any file\.$/)
  assert.match(why(['x']), /its agents may write 1 file\.$/)
  assert.match(why(null), /held by a session VBW cannot name/)
})

test('/vbw-why: a run older than 24 hours no longer holds the project', () => {
  const s = cmd.whyText({ record: rec({ lease: lease('build', NOW - 25 * 3600000, { session: SID }) }), next: null, now: NOW, sessionId: SID })
  assert.match(s, /older than 24 hours/)
})

test('/vbw-why: with no run, what blocks the next step: the user\'s turn, and every blocked plan with its reason', () => {
  const plans = [
    { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'blocked', note: 'no API key' },
    { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'blocked' },
    { id: 'P44.3', phase: 'P44', title: 'Docs', status: 'planned' },
  ]
  const s = cmd.whyText({ record: rec({ plans }), next: next({ action: 'unblock', gate: true, detail: { plans: ['P44.1', 'P44.2'] } }), now: NOW, sessionId: SID })
  assert.deepEqual(lines(s), [
    'Nothing is running.',
    'Work is blocked and needs you: P44.1, P44.2.',
    'P44.1 (Show the cost) is blocked: no API key.',
    'P44.2 (Show the estimate) is blocked: no reason given.',
  ])
  const gate = cmd.whyText({ record: rec(), next: next({ action: 'approve', gate: true }), now: NOW, sessionId: SID })
  assert.deepEqual(lines(gate), ['Nothing is running.', 'Please approve the plan before VBW builds it.'])
})

test('/vbw-why: nothing running and nothing blocked says exactly that', () => {
  assert.equal(cmd.whyText({ record: rec(), next: next(), now: NOW, sessionId: SID }), 'Nothing is running and nothing is blocked.')
  assert.equal(cmd.whyText({ record: null }), 'No VBW project is open here yet.')
  assert.equal(cmd.whyText(undefined), 'No VBW project is open here yet.')
})

test('/vbw-todo: the typed text, else the selection, becomes the kernel\'s argv; nothing gives a usage line', () => {
  assert.deepEqual(cmd.todoArgs({ args: '  dark mode  ', selection: 'ignored' }), { argv: ['todo', 'add', 'dark mode'], message: null })
  assert.deepEqual(cmd.todoArgs({ args: ['dark', 'mode'] }), { argv: ['todo', 'add', 'dark mode'], message: null })
  assert.deepEqual(cmd.todoArgs({ args: '', selection: 'retry\n  the upload' }), { argv: ['todo', 'add', 'retry the upload'], message: null })
  assert.deepEqual(cmd.todoArgs({ args: ' ', selection: { text: 'from a selection object' } }), { argv: ['todo', 'add', 'from a selection object'], message: null })
  for (const input of [{}, { args: '  ', selection: '\n' }, { args: 5, selection: null }, undefined]) {
    const r = cmd.todoArgs(input)
    assert.equal(r.argv, null)
    assert.match(r.message, /^Usage: \/vbw-todo TEXT/)
  }
})

test('the command models change nothing in their input', () => {
  const input = deepFreeze({ record: rec({ lease: lease('build', NOW - 5000, { session: SID }) }), next: next({ action: 'unblock', gate: true }), now: NOW, sessionId: SID, args: 'x', selection: 'y' })
  assert.doesNotThrow(() => { cmd.statusText(input); cmd.whyText(input); cmd.todoArgs(input) })
})
