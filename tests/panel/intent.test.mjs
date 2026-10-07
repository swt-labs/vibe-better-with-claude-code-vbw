// R87: an agent's activity is a plain intention (editing app-topbar.tsx,
// running tests, recording P6.7 done), never the raw command; a script run
// through Python, Node or another interpreter is named by the file it runs.
// plugin/hooks/panel-feed.js turns a transcript's last tool call into that
// intention. Pure: text in, value out (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN } from './helpers/fake-mod.mjs'
import { T0, line, jsonl } from './helpers/feed-fs.mjs'

const feed = await import(pathToFileURL(PLUGIN + '/hooks/panel-feed.js').href)
const say = (name, input) => feed.parseTranscript(jsonl([line.user(T0), line.tool(T0 + 1000, name, input)])).activity
const bash = (command) => say('Bash', { command })
const words = (command) => bash(command).text

test('file tools are named by the file: editing app-topbar.tsx', () => {
  assert.deepEqual(say('Edit', { file_path: '/proj/src/app-topbar.tsx' }), { kind: 'tool', text: 'editing app-topbar.tsx' })
  assert.deepEqual(say('Write', { file_path: '/proj/src/new.ts' }), { kind: 'tool', text: 'editing new.ts' })
  assert.deepEqual(say('Read', { file_path: '/proj/.vbw/spec.md' }), { kind: 'tool', text: 'reading spec.md' })
})

test('running a test suite reads as running tests, whatever the runner', () => {
  for (const c of ['bats tests/prove.bats', 'bats --jobs 4 tests', 'npm test', 'npm run test -- --watch=false', 'pnpm test', 'yarn test', 'pytest -q tests/', 'python3 -m pytest tests',
    'node --test tests/panel/*.test.mjs', 'cargo test --release', 'go test ./...', 'cd "/proj/my app" && bats tests/prove.bats']) {
    assert.equal(words(c), 'running tests', c)
  }
})

test('a vbw command reads as what VBW is doing, in the present tense', () => {
  assert.equal(words('vbw plan done P6.7'), 'recording P6.7 done')
  assert.equal(words('"/home/u/plugin/bin/vbw" plan done P6.7'), 'recording P6.7 done')
  assert.equal(words('cd /proj && vbw plan done P6.7'), 'recording P6.7 done')
  assert.equal(words('vbw prove'), 'proving the checks')
})

test('a script run through an interpreter is named by the file, not by the interpreter', () => {
  assert.equal(words('python3 scripts/fix_topbar.py --apply'), 'running fix_topbar.py')
  assert.equal(words('python scripts/fix_topbar.py'), 'running fix_topbar.py')
  assert.equal(words('node tools/gen.js --out build'), 'running gen.js')
  assert.equal(words('cd "/proj/x y" && node tools/gen.js'), 'running gen.js')
  assert.equal(words('bash scripts/release.sh patch'), 'running release.sh')
  assert.equal(words('ruby lib/seed.rb'), 'running seed.rb')
  assert.equal(words('./scripts/setup.sh'), 'running setup.sh')
})

test('an inline script has no file to name: a short generic phrase, never the code', () => {
  for (const c of ['node -e "require(\'fs\').writeFileSync(\'a.txt\', \'x\')"', 'python3 -c "import os; os.remove(\'a.txt\')"', 'python3 - <<\'EOF\'\nprint(1)\nEOF']) {
    const t = words(c)
    assert.match(t, /^running a script$/, c)
  }
})

test('an unrecognised command falls back to a short generic phrase: never empty, never the raw command, never a secret', () => {
  const secret = 'sk-live-0123456789abcdef'
  for (const c of ['frobnicate --token=' + secret + ' --now', 'curl -H "Authorization: Bearer ' + secret + '" https://api.example.com/v1/x', 'export API_KEY=' + secret + '; make deploy',
    'git status --short', 'ls -la /etc/ssl', 'grep -rn "predicted" plugin/lib plugin/bin']) {
    const t = words(c)
    assert.ok(t && t.trim() !== '', 'not empty: ' + c)
    assert.ok(t.length <= 40, 'short: ' + t)
    assert.doesNotMatch(t, new RegExp(secret), 'no secret: ' + t)
    assert.doesNotMatch(t, /--|https?:|predicted|Bearer|API_KEY|\/etc/, 'not the raw command: ' + t)
  }
  assert.match(words('frobnicate --now'), /^running /)
})

test('every command gives an intention that is one short line', () => {
  for (const c of ['', '   ', 'a'.repeat(500), 'echo hi\necho there\n', undefined, null, 7]) {
    const a = bash(c)
    assert.ok(a === null || (a.kind === 'tool' && typeof a.text === 'string' && a.text.trim() !== '' && !/\n/.test(a.text) && a.text.length <= 40), JSON.stringify(c) + ' -> ' + JSON.stringify(a))
  }
})

test('the other tools keep their plain intentions', () => {
  assert.equal(say('Grep', { pattern: 'ROLE_COLORS' }).text, 'searching ROLE_COLORS')
  assert.equal(say('WebFetch', { url: 'https://docs.example.com/a?x=1' }).text, 'researching docs.example.com')
  assert.equal(say('StructuredOutput', {}).text, 'reporting')
})
