// The run feed (mods_build_plan.md, run model contract): plugin/hooks/panel-feed.js
// reads a Claude Code workflow run's files (journal, agent metas and transcripts,
// the final json) and turns them into the run model every view draws. Parsers are
// pure and tested by value; the readers run against a virtual file system and are
// tested for what they read and what they never read (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN, deepFreeze } from './helpers/fake-mod.mjs'
import { SESSION, T0, fakeFs, line, usage, jsonl } from './helpers/feed-fs.mjs'

const feed = await import(pathToFileURL(PLUGIN + '/hooks/panel-feed.js').href)
const RUN = 'wf_0669fe8d-c12'
const DIR = SESSION + '/subagents/workflows/' + RUN
const FINAL = SESSION + '/workflows/' + RUN + '.json'
const A = 'afef95f2cac0b6259'
const B = 'a532b1cefce660d83'
const last = (rows) => feed.parseTranscript(jsonl(rows)).activity

// ---- the journal ----

test('the journal gives started and result events, skipping launched, bad and half-written lines', () => {
  const text = jsonl([
    { type: 'launched' },
    { type: 'started', key: 'v2:1', agentId: A, label: 'dev P21.2', phase: 'Build' },
    'not json',
    { type: 'result', key: 'v2:1', agentId: A, result: { status: 'done', summary: 'Triggers raise a tier.' } },
  ]) + '{"type":"started","agentId":"a5'
  assert.deepEqual(feed.parseJournal(text), [
    { type: 'started', agentId: A, label: 'dev P21.2', phase: 'Build' },
    { type: 'result', agentId: A, result: { status: 'done', summary: 'Triggers raise a tier.' }, error: null },
  ])
})

test('a result line carrying an error keeps it', () => {
  const ev = feed.parseJournal(jsonl([{ type: 'result', agentId: A, error: 'Agent crashed: API overloaded' }]))
  assert.deepEqual(ev, [{ type: 'result', agentId: A, result: null, error: 'Agent crashed: API overloaded' }])
})

test('the journal parser never throws on garbage', () => {
  for (const x of [null, undefined, 42, '', '[]\n"x"\n{}', { a: 1 }]) assert.deepEqual(feed.parseJournal(x), [])
})

// ---- agent metas ----

test('a meta gives the role from the agent type, the label without the role word, and the model', () => {
  const m = (o) => feed.parseMeta(JSON.stringify({ spawnDepth: 1, requestShape: 'foreground', ...o }))
  assert.deepEqual(m({ agentType: 'vbw:qa', description: 'qa P55', workflowPhase: 'Verify', model: 'sonnet' }), { role: 'qa', label: 'P55', model: 'sonnet' })
  assert.deepEqual(m({ agentType: 'vbw:dev', description: 'dev P53.2', model: 'sonnet' }), { role: 'dev', label: 'P53.2', model: 'sonnet' })
  assert.deepEqual(m({ agentType: 'vbw:architect', description: 'architect scope', model: 'opus' }), { role: 'architect', label: 'scope', model: 'opus' })
  assert.deepEqual(m({ agentType: 'vbw:docs', description: 'docs', model: 'claude-haiku-5-5' }), { role: 'docs', label: '', model: 'haiku' })
})

test('an agent type that is not a VBW role is an agent, its whole description the label', () => {
  assert.deepEqual(feed.parseMeta('{"agentType":"general-purpose","description":"Check the map"}'), { role: 'agent', label: 'Check the map', model: null })
})

test('a meta that is not a JSON object gives null', () => {
  for (const x of ['', '{', '[]', null, 7]) assert.equal(feed.parseMeta(x), null)
})

// ---- agent transcripts ----

test('the activity is the intention of the last tool called', () => {
  const t = (name, input) => last([line.tool(T0, name, input)])
  assert.deepEqual(t('Read', { file_path: '/proj/.vbw/spec.md', offset: 48 }), { kind: 'tool', text: 'reading spec.md' })
  assert.deepEqual(t('Bash', { command: 'cd "/proj/my app" && bats tests/prove.bats' }), { kind: 'tool', text: 'running tests' })
  assert.deepEqual(t('bash', { command: 'vbw show plan P21.3' }), { kind: 'tool', text: 'showing plan P21.3' })
  assert.deepEqual(t('Bash', { command: 'cd /proj; git status --short;\n  grep -rn "predicted" plugin/lib plugin/bin' }), { kind: 'tool', text: 'running a command' })
  assert.deepEqual(t('Edit', { file_path: '/proj/plugin/lib/record.sh', old_string: 'a', new_string: 'b' }), { kind: 'tool', text: 'editing record.sh' })
  assert.deepEqual(t('Write', { file_path: '/proj/plugin/hooks/approve-answer.sh', content: '#!/usr/bin/env bash' }), { kind: 'tool', text: 'editing approve-answer.sh' })
  assert.deepEqual(t('Grep', { pattern: 'lease', path: '/proj' }), { kind: 'tool', text: 'searching lease' })
  assert.deepEqual(t('Glob', { pattern: 'plugin/**/*.js' }), { kind: 'tool', text: 'searching plugin/**/*.js' })
  assert.deepEqual(t('WebSearch', { query: 'claude code mods panel' }), { kind: 'tool', text: 'researching claude code mods panel' })
  assert.deepEqual(t('WebFetch', { url: 'https://code.claude.com/docs/en/mods', prompt: 'Explain mods' }), { kind: 'tool', text: 'researching code.claude.com' })
  assert.deepEqual(t('StructuredOutput', { status: 'done', summary: 'P21.3 is done' }), { kind: 'tool', text: 'reporting' })
  assert.deepEqual(t('Monitor', { command: 'until [ -s out ]; do :; done' }), { kind: 'tool', text: 'Monitor' })
  assert.deepEqual(t('Read', {}), { kind: 'tool', text: 'reading' })
})

test('streamed text gives its last 70 characters on one line, marked when cut', () => {
  assert.deepEqual(last([line.text(T0, '  Splitting R69\ninto two plans.  ')]), { kind: 'text', text: 'Splitting R69 into two plans.' })
  const long = 'I read the spec first. Splitting R69 into two plans: the runner and the reporter, because each touches different files.'
  const a = last([line.text(T0, long)])
  assert.equal(a.kind, 'text')
  assert.equal(a.text, '…' + long.slice(-70).trim())
})

test('the activity comes from the last assistant line, after tool results and attachments', () => {
  const rows = [line.user(T0), line.tool(T0 + 1000, 'Read', { file_path: '/p/a.md' }), line.result(T0 + 2000), line.text(T0 + 3000, 'Now the checks.'), line.tool(T0 + 4000, 'Bash', { command: 'bats tests' }), line.result(T0 + 5000), line.attachment(T0 + 5001)]
  assert.deepEqual(last(rows), { kind: 'tool', text: 'running tests' })
})

test('an agent thinking shows that it thinks', () => {
  assert.deepEqual(last([line.tool(T0, 'Read', { file_path: '/p/a.md' }), line.result(T0 + 1), line.thinking(T0 + 2)]), { kind: 'tool', text: 'thinking' })
})

test('tokens are the context of the last usage: input plus cache read plus cache creation', () => {
  const rows = [line.tool(T0, 'Read', { file_path: '/p/a' }, usage(5, 1000, 50)), line.result(T0 + 1), line.tool(T0 + 2, 'StructuredOutput', {}, usage(2, 66671, 224)), line.result(T0 + 3)]
  assert.deepEqual(feed.parseTranscript(jsonl(rows)), { activity: { kind: 'tool', text: 'reporting' }, tokens: 66897, firstAt: T0, lastAt: T0 + 3 })
})

test('a half-written last line is ignored; an empty or broken transcript gives nothing', () => {
  const text = jsonl([line.user(T0), line.tool(T0 + 10, 'Read', { file_path: '/p/spec.md' }, usage(1, 2, 3))]) + '{"type":"assistant","timest'
  assert.deepEqual(feed.parseTranscript(text), { activity: { kind: 'tool', text: 'reading spec.md' }, tokens: 6, firstAt: T0, lastAt: T0 + 10 })
  for (const x of ['', 'garbage', null, 3]) assert.deepEqual(feed.parseTranscript(x), { activity: null, tokens: null, firstAt: null, lastAt: null })
})

// ---- the one-line result ----

test('a result reads as one line of at most 80 characters: summary, then verdict, then status', () => {
  assert.equal(feed.resultLine({ status: 'done', summary: 'Triggers now raise a tier.\nMore.' }), 'Triggers now raise a tier. More.')
  assert.equal(feed.resultLine({ verdict: 'fail', checks: [] }), 'fail')
  assert.equal(feed.resultLine({ status: 'blocked', notes: [] }), 'blocked')
  const long = feed.resultLine({ summary: 'x'.repeat(200) })
  assert.equal(long.length, 80)
  assert.ok(long.endsWith('…'))
})

test('a result without those fields reads as a short sketch of its fields', () => {
  assert.equal(feed.resultLine({ decisions: [{ question: 'Q' }, { question: 'R' }] }), 'decisions: 2')
  assert.equal(feed.resultLine({ notes: ['a'], phases: [1, 2, 3], ok: true }), 'notes: 1, phases: 3, ok: true')
  assert.equal(feed.resultLine('## Stack and commands\n\n- VBW 2.0.8'), 'Stack and commands')
  assert.equal(feed.resultLine(null), null)
  assert.equal(feed.resultLine({}), null)
})

// ---- the run model ----

const NOW = T0 + 600_000
const journal = (...rows) => jsonl([{ type: 'launched' }, ...rows])
const started = (id, label, phase) => ({ type: 'started', key: 'k' + id, agentId: id, label, phase })
const result = (id, r) => ({ type: 'result', key: 'k' + id, agentId: id, result: r })
const meta = (role, label, model = 'sonnet', spawnedAt = T0) => ({ role, label, model, spawnedAt })
const tx = (o) => ({ activity: null, tokens: null, firstAt: null, lastAt: null, ...o })

test('a run with one agent working and one done', () => {
  const run = feed.runModel(deepFreeze({
    runId: RUN, kind: 'building', now: NOW, final: null,
    journal: journal(started(A, 'dev P53.1', 'Build'), started(B, 'dev P53.2', 'Build'), result(B, { status: 'done', summary: 'P53.2 done.' })),
    metas: { [A]: meta('dev', 'P53.1', 'sonnet', T0 + 5), [B]: meta('dev', 'P53.2', 'sonnet', T0 + 6) },
    transcripts: {
      [A]: tx({ activity: { kind: 'tool', text: 'reading spec.md' }, tokens: 41000, firstAt: T0 + 10, lastAt: NOW - 1000 }),
      [B]: tx({ activity: { kind: 'tool', text: 'reporting' }, tokens: 18000, firstAt: T0 + 20, lastAt: T0 + 300_000 }),
    },
  }))
  assert.deepEqual(run, {
    runId: RUN, kind: 'building', phase: 'Build', phases: ['Build'], startedAt: T0 + 10, endedAt: null, status: 'running',
    agents: [
      { id: A, role: 'dev', label: 'P53.1', phase: 'Build', model: 'sonnet', state: 'working', activity: { kind: 'tool', text: 'reading spec.md' }, startedAt: T0 + 10, endedAt: null, lastSeenAt: NOW - 1000, tokens: 41000, result: null },
      { id: B, role: 'dev', label: 'P53.2', phase: 'Build', model: 'sonnet', state: 'done', activity: { kind: 'tool', text: 'reporting' }, startedAt: T0 + 20, endedAt: T0 + 300_000, lastSeenAt: T0 + 300_000, tokens: 18000, result: 'P53.2 done.' },
    ],
  })
})

test('a working agent with no new line for 45 s is quiet; at 45 s it still works', () => {
  const at = (lastAt) => feed.runModel({ runId: RUN, kind: 'verifying', now: NOW, journal: journal(started(A, 'qa P55', 'Verify')), metas: {}, transcripts: { [A]: tx({ lastAt }) } }).agents[0].state
  assert.equal(feed.QUIET_MS, 45_000)
  assert.equal(at(NOW - 45_000), 'working')
  assert.equal(at(NOW - 45_001), 'quiet')
})

test('without a meta the role and label come from the journal label; without a transcript the spawn time stands', () => {
  const run = feed.runModel({ runId: RUN, kind: 'verifying', now: T0 + 30_000, journal: journal(started(A, 'qa P55', 'Verify')), metas: { [A]: { spawnedAt: T0 + 7 } }, transcripts: {} })
  assert.deepEqual(run.agents[0], { id: A, role: 'qa', label: 'P55', phase: 'Verify', model: null, state: 'working', activity: null, startedAt: T0 + 7, endedAt: null, lastSeenAt: T0 + 7, tokens: null, result: null })
  assert.equal(run.startedAt, T0 + 7)
})

test('an agent with an error result failed, with the error as its line', () => {
  const run = feed.runModel({ runId: RUN, kind: 'building', now: NOW, journal: journal(started(A, 'dev P1.1', 'Build'), { type: 'result', agentId: A, error: 'API overloaded' }), metas: {}, transcripts: {} })
  assert.equal(run.agents[0].state, 'failed')
  assert.equal(run.agents[0].result, 'API overloaded')
})

test('the final json ends the run: status, end time, and agents without a result failed', () => {
  const final = { runId: RUN, workflowName: 'building', status: 'completed', startTime: T0, durationMs: 455_178, workflowProgress: [{ type: 'workflow_phase', index: 1, title: 'Build' }, { type: 'workflow_agent', agentId: A, agentType: 'vbw:dev', model: 'claude-sonnet-5-5', state: 'done', startedAt: T0 + 44, durationMs: 1000, tokens: 66921 }] }
  const run = feed.runModel({ runId: RUN, kind: null, now: NOW, final, journal: journal(started(A, 'dev P21.2', 'Build'), result(A, { status: 'done', summary: 'ok' }), started(B, 'dev P21.3', 'Build')), metas: {}, transcripts: {} })
  assert.equal(run.kind, 'building')
  assert.equal(run.status, 'completed')
  assert.equal(run.startedAt, T0)
  assert.equal(run.endedAt, T0 + 455_178)
  assert.deepEqual(run.agents.map((a) => [a.state, a.model, a.startedAt, a.endedAt, a.tokens]), [['done', 'sonnet', T0 + 44, T0 + 1044, 66921], ['failed', null, null, null, null]])
})

test('each agent carries its phase; the run lists phases in the order the journal first shows them', () => {
  const run = feed.runModel({ runId: RUN, kind: 'verifying', now: NOW, metas: { c: { role: 'qa', label: 'X' } }, transcripts: {},
    journal: journal(started(A, 'scout map', 'Research'), started(B, 'qa P55', 'Verify'), started('a3', 'scout more', 'Research')) })
  assert.deepEqual(run.phases, ['Research', 'Verify'])
  assert.equal(run.phase, 'Research')
  assert.deepEqual(run.agents.map((a) => a.phase), ['Research', 'Verify', 'Research', null])
})

test('the final json phase titles are the run\'s phases when present', () => {
  const final = { status: 'running', phases: [{ title: 'Plan', detail: 'a' }, { title: 'Review' }, 'bad', { title: '' }] }
  const run = feed.runModel({ runId: RUN, kind: 'planning', now: NOW, final, journal: journal(started(A, 'lead P1', 'Review')), metas: {}, transcripts: {} })
  assert.deepEqual(run.phases, ['Plan', 'Review'])
})

test('final statuses map onto the contract', () => {
  const st = (status) => feed.runModel({ runId: RUN, kind: 'x', now: NOW, final: { status }, journal: '', metas: {}, transcripts: {} }).status
  assert.equal(st('running'), 'running')
  assert.equal(st('completed'), 'completed')
  assert.equal(st('failed'), 'failed')
  assert.equal(st('cancelled'), 'stopped')
  assert.equal(st('killed'), 'stopped')
})

test('the run model never throws: no run id gives null, garbage gives an empty run', () => {
  assert.equal(feed.runModel({}), null)
  assert.equal(feed.runModel(null), null)
  const run = feed.runModel({ runId: RUN, journal: 5, metas: 'x', transcripts: [1], final: 'y', now: NOW })
  assert.deepEqual(run, { runId: RUN, kind: null, phase: null, phases: [], startedAt: null, endedAt: null, status: 'running', agents: [] })
})

// ---- reading a run from disk ----

function runFiles(over = {}) {
  return {
    [DIR + '/journal.jsonl']: journal(started(A, 'architect scope', 'Plan'), started(B, 'scout linux', 'Plan'), result(B, { findings: ['a', 'b', 'c', 'd'] })),
    [DIR + '/agent-' + A + '.meta.json']: { agentType: 'vbw:architect', description: 'architect scope', workflowPhase: 'Plan', model: 'opus' },
    [DIR + '/agent-' + B + '.meta.json']: { agentType: 'vbw:scout', description: 'scout linux', workflowPhase: 'Plan', model: 'haiku' },
    [DIR + '/agent-' + A + '.jsonl']: jsonl([line.user(T0 - 5000), line.tool(T0 - 1000, 'Read', { file_path: '/proj/.vbw/spec.md' }, usage(3, 40000, 997))]),
    [DIR + '/agent-' + B + '.jsonl']: jsonl([line.user(T0 - 4000), line.tool(T0 - 2000, 'StructuredOutput', {}, usage(0, 12000, 0))]),
    ...over,
  }
}

test('gatherRun reads a live run into the run model', async () => {
  const f = fakeFs({ files: runFiles() })
  const run = await feed.gatherRun(f.$, {}, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(run.kind, 'planning')
  assert.equal(run.status, 'running')
  assert.equal(run.phase, 'Plan')
  assert.deepEqual(run.agents.map((a) => [a.role, a.label, a.model, a.state, a.activity?.text, a.tokens, a.result]), [
    ['architect', 'scope', 'opus', 'working', 'reading spec.md', 41000, null],
    ['scout', 'linux', 'haiku', 'done', 'reporting', 12000, 'findings: 4'],
  ])
})

test('gatherRun reads nothing again while no file changed', async () => {
  const f = fakeFs({ files: runFiles() })
  const cache = {}
  await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  const before = f.readCount()
  const again = await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(f.readCount(), before)
  assert.equal(again.agents.length, 2)
})

test('gatherRun reads only the transcript that changed', async () => {
  const f = fakeFs({ files: runFiles() })
  const cache = {}
  await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  const before = f.readCount()
  f.advance(3000)
  f.write(DIR + '/agent-' + A + '.jsonl', jsonl([line.user(T0 - 5000), line.text(f.now(), 'Splitting R69 into two plans.', usage(1, 50000, 0))]))
  const run = await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(f.readCount(), before + 1)
  assert.equal(f.reads(DIR + '/agent-' + A + '.jsonl'), 2)
  assert.deepEqual(run.agents[0].activity, { kind: 'text', text: 'Splitting R69 into two plans.' })
  assert.equal(run.agents[0].tokens, 50001)
})

test('gatherRun reads a done agent\'s transcript once after it is done, never again', async () => {
  const f = fakeFs({ files: runFiles() })
  const cache = {}
  const T = DIR + '/agent-' + B + '.jsonl'
  await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  f.write(T, jsonl([line.user(T0), line.text(T0 + 1, 'late line')]))
  await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(f.reads(T), 1)
})

test('gatherRun reads the final json and the run ends', async () => {
  const f = fakeFs({ files: runFiles({ [FINAL]: { runId: RUN, workflowName: 'planning', status: 'completed', startTime: T0 - 6000, durationMs: 9000, workflowProgress: [] } }) })
  const run = await feed.gatherRun(f.$, {}, { sessionDir: SESSION, runId: RUN })
  assert.equal(run.kind, 'planning')
  assert.equal(run.status, 'completed')
  assert.equal(run.endedAt, T0 + 3000)
  assert.equal(run.agents[0].state, 'failed')
})

test('gatherRun never reads a file over 4 MiB and still draws the agent', async () => {
  const f = fakeFs({ files: runFiles() })
  f.huge(DIR + '/agent-' + A + '.jsonl')
  const run = await feed.gatherRun(f.$, {}, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(f.reads(DIR + '/agent-' + A + '.jsonl'), 0)
  assert.equal(run.agents[0].activity, null)
  assert.equal(run.agents[0].state, 'working')
})

test('gatherRun gives null, never throws, when the run cannot be read', async () => {
  assert.equal(await feed.gatherRun(fakeFs().$, {}, { sessionDir: SESSION, runId: RUN }), null)
  assert.equal(await feed.gatherRun(fakeFs({ files: runFiles(), listFails: true }).$, {}, { sessionDir: SESSION, runId: RUN }), null)
  assert.equal(await feed.gatherRun(null, null, null), null)
  assert.equal(await feed.gatherRun({}, {}, { sessionDir: SESSION, runId: RUN }), null)
})

test('a cache from another run is not reused', async () => {
  const f = fakeFs({ files: runFiles() })
  const cache = {}
  await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: 'wf_other' }), null)
  const run = await feed.gatherRun(f.$, cache, { sessionDir: SESSION, runId: RUN, kind: 'planning' })
  assert.equal(run.agents.length, 2)
})

// ---- finding a run after a reload ----

const W = SESSION + '/subagents/workflows/'
const S = SESSION + '/workflows/scripts/'

test('findRun finds the newest run that has not ended, its kind from the script name', async () => {
  const f = fakeFs()
  f.write(W + 'wf_old/journal.jsonl', '', T0)
  f.write(SESSION + '/workflows/wf_old.json', { workflowName: 'planning', status: 'completed' }, T0 + 10)
  f.write(S + 'planning-wf_old.js', 'x', T0)
  f.write(W + 'wf_new/journal.jsonl', '', T0 + 100)
  f.write(S + 'fixing-wf_new.js', 'x', T0 + 100)
  assert.deepEqual(await feed.findRun(f.$, {}, SESSION), { runId: 'wf_new', kind: 'fixing' })
})

test('findRun passes over ended runs; a final json still running counts, its kind from workflowName', async () => {
  const f = fakeFs()
  f.write(W + 'wf_a/journal.jsonl', '', T0)
  f.write(S + 'building-wf_a.js', 'x', T0)
  f.write(SESSION + '/workflows/wf_a.json', { workflowName: 'verifying', status: 'running' }, T0 + 1)
  f.write(W + 'wf_b/journal.jsonl', '', T0 + 50)
  f.write(S + 'planning-wf_b.js', 'x', T0 + 50)
  f.write(SESSION + '/workflows/wf_b.json', { workflowName: 'planning', status: 'completed' }, T0 + 60)
  assert.deepEqual(await feed.findRun(f.$, {}, SESSION), { runId: 'wf_a', kind: 'verifying' })
})

test('findRun without a script orders runs by their folder time; kind null when unknown', async () => {
  const f = fakeFs()
  f.write(W + 'wf_x/journal.jsonl', '', T0 + 500)
  f.write(W + 'wf_y/journal.jsonl', '', T0 + 100)
  assert.deepEqual(await feed.findRun(f.$, {}, SESSION), { runId: 'wf_x', kind: null })
})

test('findRun gives null when every run ended, when there is none, and on any failure', async () => {
  const f = fakeFs()
  f.write(W + 'wf_b/journal.jsonl', '', T0)
  f.write(SESSION + '/workflows/wf_b.json', { workflowName: 'planning', status: 'completed' }, T0 + 1)
  assert.equal(await feed.findRun(f.$, {}, SESSION), null)
  assert.equal(await feed.findRun(fakeFs().$, {}, SESSION), null)
  assert.equal(await feed.findRun(fakeFs({ files: { [W + 'wf_c/journal.jsonl']: '' }, listFails: true }).$, {}, SESSION), null)
  assert.equal(await feed.findRun(null, null, null), null)
})

test('findRun reads an ended run\'s final json once, not on every call', async () => {
  const f = fakeFs()
  f.write(W + 'wf_b/journal.jsonl', '', T0)
  f.write(SESSION + '/workflows/wf_b.json', { workflowName: 'planning', status: 'completed' }, T0 + 1)
  const cache = {}
  await feed.findRun(f.$, cache, SESSION)
  await feed.findRun(f.$, cache, SESSION)
  assert.equal(f.reads(SESSION + '/workflows/wf_b.json'), 1)
})
