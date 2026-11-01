// Mission Control's Settings tab (batch 2.1.11, A2; evidence level L1: pure functions and
// the pane's tree, with a stand-in kernel behind a stubbed $.process.run). Every setting
// `vbw config set` accepts, and rigor, the sound and the status line, is one row
// `name  value  [controls]`; a press runs the kernel's own command, the tab is read again
// from `vbw config` and `vbw statusline status`, the new value shows with a `✓ saved`
// flash for about 2 s, and a refusal shows the kernel's words in amber under its row while
// the value stays. The tab never touches .vbw/record.json. The glue below is the one
// panel.js runs (`settings($, st, choice)`); the reviewer wires it there.
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, walk, collect } from './helpers/fake-mod.mjs'
import { screen, widest } from './r189/helpers/screen.mjs'

const S = await import(pathToFileURL(PLUGIN + '/hooks/panel-settings.js').href)
const pane = await import(pathToFileURL(PLUGIN + '/hooks/panel-pane.js').href)
const view = await import(pathToFileURL(PLUGIN + '/hooks/panel-view.js').href)
const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = Date.parse('2026-10-24T15:00:00Z')
const SID = 'session-1'

// A stand-in kernel: `vbw config` prints its lines as cmd-config.sh does; `config set`,
// `config rigor` and `statusline on|off` change it and print 'KEY = VALUE'; a value the
// kernel refuses exits 2 with its usage line on stderr.
function kernel() {
  const k = {
    profile: 'balanced', autonomy: 'balanced', autonomy_cap: '25', rigor: 'auto', motion: 'default', check_jobs: '6',
    command_timeout: '3600', check_budget: '120', sound: 'default', statusline: 'off', mcp: 'none',
    models: { architect: 'opus', lead: 'opus', dev: 'sonnet', qa: 'sonnet', scout: 'sonnet', debugger: 'sonnet', docs: 'sonnet' },
    interview: { kept: 'private', interviewed: true, level: 'professionally', depth: 'technical and brief', involvement: 'options with a recommendation', pending: null },
    workflows: 'default', auto: null, efforts: {},
  }
  const calls = []
  const out = (stdout) => ({ exitCode: 0, stdout, stderr: '' })
  const refuse = (stderr) => ({ exitCode: 2, stdout: '', stderr })
  const run = (argv) => {
    calls.push(argv)
    const [a, b, c, d] = argv
    if (a === 'config' && argv.length === 1) {
      return out(['check_jobs: ' + k.check_jobs + ' (default: three quarters of the processor cores)',
        'machine limit: 6 (three quarters of this computer\'s processor cores (8), rounded down, at least 1 and at most 64; shared by every VBW project on this computer; not a setting)',
        'profile: ' + k.profile, 'autonomy: ' + k.autonomy, 'autonomy_cap: ' + k.autonomy_cap, 'rigor: ' + k.rigor, 'motion: ' + k.motion,
        'sound: ' + k.sound, 'command_timeout: ' + k.command_timeout + ' seconds', 'check_budget: ' + k.check_budget + ' seconds a unit (reported, never enforced)', 'mcp: ' + k.mcp,
        ...Object.entries(k.models).map(([r, m]) => 'model.' + r + ': ' + m),
        ...Object.keys(k.models).map((r) => 'effort.' + r + ': ' + (k.efforts[r] || 'default'))].join('\n') + '\n')
    }
    if (a === 'interview' && b === '--json') return out(JSON.stringify(k.interview) + '\n')
    if (a === 'interview' && b === 'set') { k.interview[c] = d; return out(c + ' = ' + d + '\n') }
    if (a === 'interview' && b === 'keep') { k.interview.kept = c; return out('the interview answers are kept ' + c + '\n') }
    if (a === 'workflows' && b === 'status') {
      return out({ on: 'on: Dynamic workflows are enabled', default: 'default: Claude Code decides (off on some plans; vbw workflows on turns them on)',
        disabled: 'off: Dynamic workflows are disabled on purpose (disableWorkflows or CLAUDE_CODE_DISABLE_WORKFLOWS); VBW needs them to plan and build' }[k.workflows] + '\n')
    }
    if (a === 'workflows' && b === 'on') { if (k.workflows === 'default') k.workflows = 'on'; return out('on: Dynamic workflows turned on\n') }
    if (a === 'auto' && b === 'status' && c === SID) return out(k.auto ? 'armed: step ' + k.auto.steps + ' of ' + k.auto.cap + ', since 2026-10-24T15:00:00Z\n' : 'off\n')
    if (a === 'auto' && b === 'on' && c === SID) { k.auto = { steps: 0, cap: Number(k.autonomy_cap) }; return out('autonomous run armed for this session\n') }
    if (a === 'auto' && b === 'off' && c === SID) { k.auto = null; return out('autonomous run off\n') }
    if (a === 'statusline' && b === 'status') return out(k.statusline === 'on' ? 'on: the VBW status line\n' : 'off: no status line is set (vbw statusline on)\n')
    if (a === 'statusline') { k.statusline = b; return out(b + ': done\n') }
    if (a === 'config' && b === 'rigor') { k.rigor = c; return out('rigor = ' + c + '\n') }
    if (a === 'config' && b === 'set') {
      if (c === 'autonomy_cap' && d === '7777') return refuse('vbw: autonomy_cap must be a number of steps\n')
      if (c.startsWith('model.')) k.models[c.slice(6)] = d === 'default' ? 'sonnet' : d
      else if (c.startsWith('effort.')) { if (d === 'default') delete k.efforts[c.slice(7)]; else k.efforts[c.slice(7)] = d }
      else k[c] = d
      return out(c + ' = ' + d + '\n')
    }
    return refuse('vbw: usage\n')
  }
  return { k, calls, run }
}

// What panel.js does on a press or when the tab opens (its settings($, st, choice)).
async function settings(st, kn, choice, now = NOW) {
  const argv = choice ? S.settingArgv(choice, SID) : null
  const result = argv ? kn.run(argv) : null
  const reads = S.readArgv(SID).map((r) => kn.run(r))
  st.settings = S.settingsState({ before: st.settings, choice, result, reads, now })
}

const state_ = (over = {}) => state(over)
const state = (over = {}) => ({ tab: 'settings', record: record(), run: null, steps: [], leases: [], cost: 1, sound: true, agent: null, phase: null, check: null, settings: null, ...over })
const draw = (st, now = NOW, width = 80) => pane.renderPane(UI, { st, v: view.panelView({ record: st.record, now, cost: 1 }), now, width, scroll: { offset: 0, bodyRows: 200 } },
  { act: (a) => st.pressed.push(a), sound: () => st.pressed.push('sound') })
const buttons = (tree) => { const out = []; walk(tree, (n) => { if (n.type === 'Button') out.push(n) }); return out }
const rowOf = (tree, key) => { let hit = null; walk(tree, (n) => { if (!hit && n.props && n.props.key === 'setting:' + key) hit = n }); return hit }
const texts = (n) => { const out = []; walk(n, (x) => { if (x.type === 'Text') out.push({ text: collect(x).join(''), props: x.props }) }); return out }

// Every key cmd-config.sh's `config set` accepts (its case labels), and rigor, sound, statusline.
function kernelKeys() {
  const src = fs.readFileSync(PLUGIN + '/lib/cmd-config.sh', 'utf8')
  const set = src.slice(src.indexOf('    set)\n      local key'))
  const keys = new Set()
  for (const m of set.matchAll(/^ {8}([a-z_.|]+)\)/gm)) for (const k of m[1].split('|')) keys.add(k)
  return keys
}

test('every key `vbw config set` accepts has a row, with rigor and the status line beside them', () => {
  const rows = new Set(S.ROWS.map((r) => r.key))
  for (const k of kernelKeys()) assert.ok(rows.has(k), 'no Settings row for ' + k)
  for (const k of ['rigor', 'statusline', 'sound']) assert.ok(rows.has(k), k)
  assert.deepEqual(S.ROWS.filter((r) => r.key.startsWith('model.')).map((r) => r.key.slice(6)), S.ROLES)
  assert.ok(!S.ROWS.find((r) => r.key === 'model.qa').choices.includes('haiku'), 'QA is never offered Haiku')
})

test('the interview answers, the autonomous run and Dynamic workflows run their own kernel commands', () => {
  assert.deepEqual(S.settingArgv({ key: 'interview.level', value: 'senior engineer' }, SID), ['interview', 'set', 'level', 'senior engineer'])
  assert.deepEqual(S.settingArgv({ key: 'interview.involvement', value: 'I make the calls' }, SID), ['interview', 'set', 'involvement', 'I make the calls'])
  assert.deepEqual(S.settingArgv({ key: 'interview.kept', value: 'project' }, SID), ['interview', 'keep', 'project'])
  assert.deepEqual(S.settingArgv({ key: 'auto', value: 'on' }, SID), ['auto', 'on', SID])
  assert.deepEqual(S.settingArgv({ key: 'auto', value: 'off' }, SID), ['auto', 'off', SID])
  assert.deepEqual(S.settingArgv({ key: 'workflows', value: 'on' }, SID), ['workflows', 'on'])
  for (const bad of [{ key: 'auto', value: 'on' }, { key: 'auto', value: 'maybe' }, { key: 'interview.level', value: 'wizard' }, { key: 'interview.kept', value: 'cloud' }, { key: 'workflows', value: 'off' }]) {
    assert.equal(S.settingArgv(bad, bad.key === 'auto' && bad.value === 'on' ? null : SID), null, JSON.stringify(bad))
  }
})

test('the interview rows offer exactly the answers the kernel accepts, in its order', () => {
  const answers = JSON.parse(fs.readFileSync(PLUGIN + '/lib/interview.json', 'utf8'))
  for (const k of ['level', 'depth', 'involvement']) assert.deepEqual(S.ROWS.find((r) => r.key === 'interview.' + k).choices, answers[k], k)
  assert.deepEqual(S.ROWS.find((r) => r.key === 'interview.kept').choices, ['private', 'project'])
})

test('Dynamic workflows: on is a green ✓; Claude Code\'s default is amber with a turn on button; off on purpose is amber with no button', async () => {
  for (const [state, mark, button] of [['on', '✓', false], ['default', '⚠', true], ['disabled', '⚠', false]]) {
    const kn = kernel()
    kn.k.workflows = state
    const st = state_({ pressed: [] })
    await settings(st, kn, null)
    const row = rowOf(draw(st), 'workflows')
    const v = texts(row).find((t) => t.props.key === 'value')
    assert.ok(v && v.text.startsWith(mark), state + ': ' + (v && v.text))
    assert.equal(v.props.color, state === 'on' ? P.stateColor('done') : P.NEED, state)
    assert.equal(buttons(row).some((b) => b.props.label === 'turn on'), button, state + ': turn on button')
  }
  const kn = kernel()
  const st = state_({ pressed: [] })
  await settings(st, kn, null)
  buttons(rowOf(draw(st), 'workflows')).find((b) => b.props.label === 'turn on').props.onPress({ surface: 'terminal' })
  await settings(st, kn, st.pressed[0].setting)
  assert.ok(texts(rowOf(draw(st), 'workflows')).find((t) => t.props.key === 'value').text.startsWith('✓'), 'turned on')
})

test('the autonomous run row is this chat\'s: armed shows on with its steps, and with no session id there is no row', async () => {
  const kn = kernel()
  kn.k.auto = { steps: 2, cap: 25 }
  const st = state_({ pressed: [] })
  await settings(st, kn, null)
  const row = rowOf(draw(st), 'auto')
  assert.equal(texts(row).find((t) => t.props.key === 'value').text, 'on')
  assert.match(collect(row).join(' '), /this chat · step 2 of 25/)
  const none = S.settingsState({ reads: S.readArgv(null).map((r) => kernel().run(r)), now: NOW })
  assert.ok(!rowOf(S.renderSettings(UI, S.settingsModel({ settings: none, now: NOW })), 'auto'), 'no row without a session')
})

test('a press runs only the kernel command its row offers: config set, config rigor, statusline on|off; anything else runs nothing', () => {
  assert.deepEqual(S.settingArgv({ key: 'profile', value: 'quality' }), ['config', 'set', 'profile', 'quality'])
  assert.deepEqual(S.settingArgv({ key: 'rigor', value: 'deep' }), ['config', 'rigor', 'deep'])
  assert.deepEqual(S.settingArgv({ key: 'statusline', value: 'on' }), ['statusline', 'on'])
  assert.deepEqual(S.settingArgv({ key: 'autonomy_cap', value: 30 }), ['config', 'set', 'autonomy_cap', '30'])
  assert.deepEqual(S.settingArgv({ key: 'sound', value: 'darth' }), ['config', 'set', 'sound', 'darth'])
  for (const bad of [null, {}, { key: 'profile', value: 'turbo' }, { key: 'nosuch', value: 'x' }, { key: 'check_jobs', value: '65' }, { key: 'model.qa', value: 'haiku' }, { key: 'profile', value: 'quality; rm -rf /' }]) {
    assert.equal(S.settingArgv(bad), null, JSON.stringify(bad))
  }
})

test('the tab reads the values from vbw config: each row its value, check_jobs with the machine limit dim beside it', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  assert.match(collect(draw(st)).join('\n'), /Reading the settings/, 'before the first read the tab says so')
  await settings(st, kn, null)
  assert.deepEqual(kn.calls, [['config'], ['statusline', 'status'], ['interview', '--json'], ['workflows', 'status'], ['auto', 'status', SID]])
  assert.deepEqual(S.readArgv(null), [['config'], ['statusline', 'status'], ['interview', '--json'], ['workflows', 'status']], 'no session id: no autonomous run row to read')
  const tree = draw(st)
  for (const [key, value] of [['interview.level', 'professionally'], ['interview.kept', 'private'], ['auto', 'off'], ['profile', 'balanced'], ['model.lead', 'opus'], ['autonomy_cap', '25'], ['rigor', 'auto'], ['motion', 'default'], ['sound', 'default'], ['statusline', 'off'], ['check_jobs', '6']]) {
    const row = rowOf(tree, key)
    assert.ok(row, 'no row ' + key)
    const v = texts(row).find((t) => t.props.key === 'value')
    assert.ok(v && v.text.startsWith(value), key + ' shows ' + (v && v.text))
    assert.equal(v.props.color, P.ACCENT, key + ': the value is in the accent')
  }
  assert.match(collect(rowOf(tree, 'check_jobs')).join(' '), /machine limit 6/)
  assert.match(collect(rowOf(tree, 'sound')).join(' '), /this clone/)
  // A role's model row is named in the role's colour.
  assert.equal(texts(rowOf(tree, 'model.dev')).find((t) => t.props.key === 'name').props.color, P.roleColor('dev'))
})

test('one change per row: the kernel command runs, the tab is read again and the new value shows with ✓ saved, gone after about 2 s', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  const picks = { profile: 'quality', autonomy: 'guided', rigor: 'deep', motion: 'calm', sound: 'darth', statusline: 'on' }
  Object.assign(picks, { 'interview.level': 'senior engineer', 'interview.depth': 'plain words', 'interview.involvement': 'I make the calls', 'interview.kept': 'project', auto: 'on' })
  for (const r of S.ROLES) picks['model.' + r] = 'opus'
  for (const r of S.ROLES) picks['effort.' + r] = 'xhigh'
  for (const r of S.ROWS.filter((x) => !x.status)) {
    st.pressed = []
    const tree = draw(st)
    let b
    if (r.choices) b = buttons(rowOf(tree, r.key)).find((x) => x.props.label === picks[r.key])
    else b = buttons(rowOf(tree, r.key)).find((x) => x.props.label === '+')
    assert.ok(b, r.key + ': no control to press')
    b.props.onPress({ surface: 'terminal' })
    assert.equal(st.pressed.length, 1, r.key)
    const choice = st.pressed[0].setting
    kn.calls.length = 0
    await settings(st, kn, choice)
    assert.deepEqual(kn.calls.slice(1), S.readArgv(SID), r.key + ': the tab is read again after the change')
    const after = draw(st, NOW + 500)
    const want = r.choices ? picks[r.key] : String(Number(choice.value))
    assert.ok(texts(rowOf(after, r.key)).find((t) => t.props.key === 'value').text.startsWith(want), r.key + ' shows ' + want)
    const saved = texts(rowOf(after, r.key)).find((t) => t.props.key === 'saved')
    assert.ok(saved && saved.text === '✓ saved' && saved.props.color === P.stateColor('done'), r.key + ': ✓ saved in green')
    assert.ok(!texts(rowOf(draw(st, NOW + S.SAVED_MS + 1), r.key)).some((t) => t.props.key === 'saved'), r.key + ': the flash settles')
  }
})

test('a refused change shows the kernel\'s words in amber under its row; the value stays as the kernel reads it', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  await settings(st, kn, { key: 'autonomy_cap', value: '7777' })
  const row = rowOf(draw(st), 'autonomy_cap')
  const refused = texts(row).find((t) => t.props.key === 'refused')
  assert.ok(refused, 'no refusal under the row')
  assert.equal(refused.text, 'vbw: autonomy_cap must be a number of steps')
  assert.equal(refused.props.color, P.NEED)
  assert.ok(texts(row).find((t) => t.props.key === 'value').text.startsWith('25'), 'the value stays')
  assert.ok(!texts(row).some((t) => t.props.key === 'saved'))
  // The next press that works clears it.
  await settings(st, kn, { key: 'autonomy_cap', value: '20' })
  assert.ok(!texts(rowOf(draw(st), 'autonomy_cap')).some((t) => t.props.key === 'refused'))
})

test('when vbw config cannot run, the tab says so in amber, never a silent nothing', () => {
  const s = S.settingsState({ before: null, choice: null, result: null, reads: [{ exitCode: 1, stdout: '', stderr: 'vbw: not a VBW project\n' }, null], now: NOW })
  const st = state({ pressed: [], settings: s })
  const t = texts(draw(st)).find((x) => /could not read the settings/.test(x.text))
  assert.ok(t && t.props.color === P.NEED, JSON.stringify(t))
})

test('every role offers Fable, Opus, Sonnet and default; all but QA offer Haiku', () => {
  for (const r of S.ROLES) {
    const want = r === 'qa' ? ['fable', 'opus', 'sonnet', 'default'] : ['fable', 'opus', 'sonnet', 'haiku', 'default']
    assert.deepEqual(S.ROWS.find((x) => x.key === 'model.' + r).choices, want, r)
  }
})

test('each helper has an effort row under Effort, in its role colour: low to max, or default for the profile\'s choice', async () => {
  assert.deepEqual(S.ROWS.filter((r) => r.key.startsWith('effort.')).map((r) => r.key.slice(7)), S.ROLES)
  for (const r of S.ROLES) {
    const row = S.ROWS.find((x) => x.key === 'effort.' + r)
    assert.deepEqual(row.choices, ['low', 'medium', 'high', 'xhigh', 'max', 'default'], r)
    assert.equal(row.group, 'Effort', r)
  }
  assert.deepEqual(S.settingArgv({ key: 'effort.dev', value: 'max' }, SID), ['config', 'set', 'effort.dev', 'max'])
  assert.equal(S.settingArgv({ key: 'effort.dev', value: 'turbo' }, SID), null)
  const kn = kernel()
  kn.k.efforts.qa = 'max'
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  const tree = draw(st)
  assert.equal(texts(rowOf(tree, 'effort.qa')).find((t) => t.props.key === 'value').text, 'max')
  assert.equal(texts(rowOf(tree, 'effort.dev')).find((t) => t.props.key === 'value').text, 'default')
  assert.equal(texts(rowOf(tree, 'effort.qa')).find((t) => t.props.key === 'name').props.color, P.roleColor('qa'))
  // A model chosen by the user marks its model row, never the role's effort row.
  const mine = S.renderSettings(UI, S.settingsModel({ settings: st.settings, record: { settings: { models: { qa: 'opus' } } }, now: NOW }))
  assert.ok(texts(rowOf(mine, 'model.qa')).some((t) => t.props.key === 'mine'))
  assert.ok(!texts(rowOf(mine, 'effort.qa')).some((t) => t.props.key === 'mine'))
})

test('the sound row offers off, each sound folder and default, and is this clone\'s own', async () => {
  assert.deepEqual(S.ROWS.find((r) => r.key === 'sound').choices, ['off', ...S.SOUND_FOLDERS, 'default'])
  assert.ok(S.SOUND_FOLDERS.length > 0 && S.SOUND_FOLDERS.every((f) => /^[a-z]+$/.test(f)), JSON.stringify(S.SOUND_FOLDERS))
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  const row = rowOf(draw(st), 'sound')
  assert.deepEqual(buttons(row).map((b) => b.props.label), ['off', ...S.SOUND_FOLDERS, 'default'])
  assert.equal(buttons(row).find((b) => b.props.label === 'default').props.variant, 'primary', 'the current value is the pressed-in button')
})

test('every choice is a button a click presses, also where the surface has a Select (keyboard only in the terminal); each value is drawn once, on one line with its name', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  const tree = S.renderSettings({ ...UI, Select: EL('Select') }, S.settingsModel({ settings: st.settings, now: NOW }), (a) => st.pressed.push(a))
  let selects = 0
  walk(tree, (n) => { if (n.type === 'Select') selects++ })
  assert.equal(selects, 0, 'no Select: a terminal Select opens from the keyboard only')
  for (const r of S.ROWS.filter((x) => x.choices)) {
    const row = rowOf(tree, r.key)
    assert.deepEqual(buttons(row).map((b) => b.props.label), r.choices, r.key)
    assert.equal(texts(row).filter((t) => t.props.key === 'value').length, 1, r.key + ': the value once')
  }
  for (const w of [80, 100]) {
    const lines = screen(S.renderSettings(UI, S.settingsModel({ settings: st.settings, now: NOW })), w)
    assert.ok(lines.some((l) => /^ *dev +○ fable +○ opus +● sonnet +○ haiku +○ default$/.test(l)), w + ': name and choices on one line')
  }
})

test('a row\'s name never shrinks: wide choices wrap under themselves and the name keeps its column and its gap', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  const tree = draw(st)
  for (const r of S.ROWS) {
    const line = rowOf(tree, r.key)
    if (!line) continue
    let cell = null
    walk(line, (n) => { if (!cell && n.type === 'Box' && n.children && n.children.some((c) => c && c.type === 'Text' && c.props.key === 'name')) cell = n })
    assert.ok(cell && cell.props.flexShrink === 0, r.key + ': the name sits in a box that does not shrink')
  }
})

test('the rows fit at 80, 100 and 140 columns: no line wider than the pane', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  for (const w of [80, 100, 140]) {
    const lines = screen(draw(st, NOW, w), w)
    assert.ok(widest(lines) <= w, w + ' columns: a line is ' + widest(lines) + ' wide')
  }
})

test('the tab never reads or writes the record file: panel-settings.js reaches nothing but its inputs', () => {
  const src = fs.readFileSync(PLUGIN + '/hooks/panel-settings.js', 'utf8')
  assert.doesNotMatch(src, /record\.json|\$\.|fetch\(|require\(|node:/)
})

// R241 (#694): the MCP tool list (record.settings.mcp, `vbw config set mcp`) is a row of the tab:
// its value is the kernel's `mcp:` line as written (or none), shown read-only with the command
// to change it; no press runs anything for it.
test('R241: the mcp row shows the setting as vbw config prints it, read-only, with vbw config set mcp named beside it', async () => {
  const kn = kernel()
  const st = state({ pressed: [] })
  await settings(st, kn, null)
  let row = rowOf(draw(st), 'mcp')
  assert.ok(row, 'no row mcp')
  let v = texts(row).find((t) => t.props.key === 'value')
  assert.ok(v && v.text.startsWith('none'), 'with no setting the row shows none, got ' + (v && v.text))
  assert.equal(v.props.color, P.ACCENT, 'the value is in the accent')
  assert.equal(buttons(row).length, 0, 'the mcp row has no controls')
  assert.match(collect(row).join(' '), /vbw config set mcp/, 'the row names the command that changes it')
  assert.equal(S.settingArgv({ key: 'mcp', value: 'github:read-only' }, SID), null, 'no press changes the MCP list')
  kn.k.mcp = 'github:read-only ctx:read-only=search,get_context playwright'
  await settings(st, kn, null)
  row = rowOf(draw(st, NOW, 140), 'mcp')
  v = texts(row).find((t) => t.props.key === 'value')
  assert.ok(v && v.text.startsWith('github:read-only ctx:read-only=search,get_context playwright'), 'the row shows the setting as written, got ' + (v && v.text))
})
