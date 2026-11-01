// Mission Control's Settings tab: every setting `vbw config set` accepts (and rigor,
// the sound and the status line), each as one line `name  ● value  ○ choice …` under its
// heading, changed by a click. The kernel is the only reader and writer: the values are `vbw config`'s own
// lines and `vbw statusline status`'s, a press runs `vbw config set KEY VALUE` (or
// `vbw config rigor MODE`, `vbw statusline on|off`), and the tab is read again after
// it. A change flashes `✓ saved` for about 2 s; a refusal shows the kernel's own words
// in amber under its row and the value stays. panel.js runs the commands through `$`;
// everything here is pure: values in, values or trees out, never throws.

import { SOUNDS } from './panel-sounds.js'
import { newMark } from './panel-next.js'
import { ACCENT, NEED, roleColor, stateColor, STATE_MARKS } from './panel-palette.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const str = (x) => (typeof x === 'string' && x !== '' ? x : null)

export const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
// The sound folders shipped under assets/audio/ (panel-sounds.js lists their files).
export const SOUND_FOLDERS = [...new Set(SOUNDS.map((p) => p.split('/')[2]).filter(Boolean))]
export const SAVED_MS = 2000

// The rows, in the order drawn. `choices`: the values a press can set; `number`: the
// step of its − and + and its bounds (the kernel's); `scope`: who shares the value;
// `group`: the heading it sits under (GROUPS).
const MODELS = ['fable', 'opus', 'sonnet', 'haiku', 'default']
// The efforts Claude Code takes for an agent; default leaves the profile's per step.
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max', 'default']
// The interview's answers, as plugin/lib/interview.json lists them (a test holds the two equal).
export const INTERVIEW = {
  level: ['never', 'small scripts or no-code', 'professionally', 'senior engineer'],
  depth: ['plain words', 'plain with technical terms explained', 'technical and brief'],
  involvement: ['decide and tell me', 'options with a recommendation', 'I make the calls'],
}
const TALK = 'How VBW talks to you'
export const ROWS = [
  { key: 'profile', choices: ['quality', 'balanced', 'budget'], group: 'Models' },
  ...ROLES.map((r) => ({ key: 'model.' + r, choices: r === 'qa' ? MODELS.filter((m) => m !== 'haiku') : MODELS, role: r, group: 'Models' })),
  ...ROLES.map((r) => ({ key: 'effort.' + r, choices: EFFORTS, role: r, group: 'Effort' })),
  // The MCP tool list is shown as the kernel prints it and changed by the command named beside it (R241).
  { key: 'mcp', label: 'MCP tools', status: true, readonly: 'vbw config set mcp SERVER[:read-only[=TOOL,TOOL]]', group: 'Agents' },
  { key: 'interview.level', label: 'your level', choices: INTERVIEW.level, group: TALK },
  { key: 'interview.depth', label: 'wording', choices: INTERVIEW.depth, group: TALK },
  { key: 'interview.involvement', label: 'decisions', choices: INTERVIEW.involvement, group: TALK },
  { key: 'interview.kept', label: 'kept', choices: ['private', 'project'], group: TALK },
  { key: 'autonomy', choices: ['guided', 'balanced', 'hands-off'], group: 'How VBW works' },
  { key: 'autonomy_cap', number: { min: 1, max: 9999, step: 5, unset: 25 }, group: 'How VBW works' },
  { key: 'auto', label: 'autonomous run', choices: ['on', 'off'], scope: 'this chat', group: 'How VBW works' },
  { key: 'rigor', choices: ['auto', 'express', 'standard', 'deep'], group: 'How VBW works' },
  { key: 'check_jobs', number: { min: 1, max: 64, step: 1 }, scope: 'this clone', group: 'Checks' },
  { key: 'command_timeout', number: { min: 1, max: 86400, step: 60, unset: 3600 }, unit: 's', group: 'Checks' },
  { key: 'check_budget', number: { min: 1, max: 86400, step: 10, unset: 120 }, unit: 's', group: 'Checks' },
  { key: 'motion', choices: ['full', 'calm', 'off', 'default'], group: 'Look and sound' },
  { key: 'sound', choices: ['off', ...SOUND_FOLDERS, 'default'], scope: 'this clone', group: 'Look and sound' },
  { key: 'statusline', choices: ['on', 'off'], scope: 'this computer', group: 'Claude Code' },
  { key: 'workflows', label: 'Dynamic workflows', status: true, scope: 'this computer', group: 'Claude Code' },
]
const rowOf = (key) => ROWS.find((r) => r.key === key) || null

const SESSION = /^[A-Za-z0-9_-]+$/
const sessionOf = (x) => (typeof x === 'string' && SESSION.test(x) ? x : null)

// What panel.js runs to read the tab, in this order: `vbw config`, `vbw statusline status`,
// `vbw interview --json`, `vbw workflows status`, and with this chat's session id
// `vbw auto status SESSION` (no id, no autonomous run row).
export const readArgv = (session) => [['config'], ['statusline', 'status'], ['interview', '--json'], ['workflows', 'status'],
  ...(sessionOf(session) ? [['auto', 'status', session]] : [])]

// The argv (after the vbw path) a press asks for, or null when the key or value is not one a
// row offers: nothing is run that the tab does not draw. `session`: this chat's id, which the
// autonomous run's on and off name.
export function settingArgv(choice, session) {
  try {
    if (!isObj(choice) || typeof choice.key !== 'string') return null
    const row = rowOf(choice.key)
    const v = typeof choice.value === 'number' ? String(choice.value) : choice.value
    if (!row || row.readonly || typeof v !== 'string') return null
    if (row.key === 'workflows') return v === 'on' ? ['workflows', 'on'] : null
    if (row.choices && !row.choices.includes(v)) return null
    if (row.key === 'auto') return sessionOf(session) ? ['auto', v, session] : null
    if (row.key === 'interview.kept') return ['interview', 'keep', v]
    if (row.key.startsWith('interview.')) return ['interview', 'set', row.key.slice(10), v]
    if (row.number && !(v === 'default' || (/^\d+$/.test(v) && Number(v) >= row.number.min && Number(v) <= row.number.max))) return null
    if (row.key === 'rigor') return ['config', 'rigor', v]
    if (row.key === 'statusline') return ['statusline', v]
    return ['config', 'set', row.key, v]
  } catch {
    return null
  }
}

// `vbw config`'s lines as { key: { value, note } }: 'profile: balanced',
// 'check_jobs: 6 (default: ...)', 'command_timeout: 3600 seconds', 'model.dev: sonnet',
// and the machine limit line as the note of check_jobs.
export function parseConfig(text) {
  const out = {}
  for (const line of String(typeof text === 'string' ? text : '').split('\n')) {
    const m = /^([a-z_.]+): (.*)$/.exec(line.trim())
    if (!m) continue
    if (m[1] === 'machine limit') continue
    const [, key, rest] = m
    const num = key === 'mcp' ? null : /^(\d+)\b\s*(.*)$/.exec(rest)
    out[key] = num ? { value: num[1], note: num[2].replace(/^\((.*)\)$/, '$1') } : { value: rest.trim(), note: '' }
  }
  const limit = /^machine limit: (\d+)\b/m.exec(String(text || ''))
  if (limit && out.check_jobs) out.check_jobs.limit = 'machine limit ' + limit[1]
  return out
}

// `vbw statusline status`'s first line: on, off, or another status line.
function parseStatusline(text) {
  const line = String(typeof text === 'string' ? text : '').split('\n')[0].trim()
  const m = /^(on|off):\s*(.*)$/.exec(line)
  if (m) return { value: m[1], note: m[2] }
  return line ? { value: 'other', note: line } : null
}

const firstLine = (r) => {
  const t = isObj(r) ? String(r.stderr || r.stdout || '').trim() : ''
  return t.split('\n').map((l) => l.trim()).filter(Boolean)[0] || 'VBW refused the change (exit ' + (isObj(r) ? r.exitCode : '?') + ').'
}

// `vbw interview --json`'s answers as rows' values: unanswered and not kept yet are null, no choice lit.
function parseInterview(text) {
  let j
  try { j = JSON.parse(String(text || '')) } catch { return {} }
  if (!isObj(j)) return {}
  const out = {}
  for (const k of ['level', 'depth', 'involvement']) out['interview.' + k] = { value: str(j[k]) || 'not answered', note: '' }
  out['interview.kept'] = { value: str(j.kept) || 'not kept yet', note: j.kept === 'project' ? 'shared through git' : j.kept === 'private' ? 'this clone only' : '' }
  return out
}

// `vbw workflows status`'s first word: on, default (Claude Code decides) or off (disabled on purpose).
function parseWorkflows(text) {
  const m = /^(on|default|off):\s*(.*)$/.exec(String(text || '').split('\n')[0].trim())
  return m ? { workflows: { value: m[1] === 'off' ? 'disabled' : m[1], note: '' } } : {}
}

// `vbw auto status SESSION`: off, or 'armed: step N of M, since …'.
function parseAuto(text) {
  const line = String(text || '').split('\n')[0].trim()
  const m = /^armed: step (\d+) of (\d+)/.exec(line)
  if (m) return { auto: { value: 'on', note: 'step ' + m[1] + ' of ' + m[2] } }
  return line === 'off' ? { auto: { value: 'off', note: '' } } : {}
}

// The tab's state after a read (and a press): before, the earlier state or null; choice, the
// pressed { key, value } or null; result, what running settingArgv(choice) gave ({ exitCode,
// stdout, stderr }, null when it could not run); reads, the results of readArgv in order.
export function settingsState(input) {
  try {
    const { before, choice, result, reads, now } = isObj(input) ? input : {}
    const prev = isObj(before) ? before : {}
    const [cfg, line, interview, workflows, auto] = Array.isArray(reads) ? reads : []
    const ok = (r) => isObj(r) && r.exitCode === 0
    const values = ok(cfg)
      ? { ...parseConfig(cfg.stdout), ...(ok(interview) ? parseInterview(interview.stdout) : {}), ...(ok(workflows) ? parseWorkflows(workflows.stdout) : {}), ...(ok(auto) ? parseAuto(auto.stdout) : {}) }
      : isObj(prev.values) ? prev.values : null
    const status = ok(line) || (isObj(line) && str(line.stdout)) ? parseStatusline(line.stdout) : prev.statusline || null
    const state = {
      values, statusline: status, at: Number.isFinite(now) ? now : null,
      error: ok(cfg) ? null : values ? prev.error || null : 'VBW could not read the settings here' + (isObj(cfg) ? ': ' + firstLine(cfg) : '.'),
      saved: null, refused: null,
    }
    if (isObj(choice) && typeof choice.key === 'string') {
      if (ok(result)) state.saved = { key: choice.key, at: state.at }
      else state.refused = { key: choice.key, text: isObj(result) ? firstLine(result) : 'VBW could not run the change here.' }
    } else {
      // A read with no press keeps a refusal on screen until the next press; the flash runs out by itself.
      state.refused = isObj(prev.refused) ? prev.refused : null
      state.saved = isObj(prev.saved) ? prev.saved : null
    }
    return state
  } catch {
    return { values: null, statusline: null, at: null, error: 'VBW could not read the settings here.', saved: null, refused: null }
  }
}

const flashing = (s, now) => isObj(s) && isObj(s.saved) && Number.isFinite(s.saved.at) && Number.isFinite(now) && now - s.saved.at < SAVED_MS
// What the redraw check compares: the state and whether the flash still shows.
export const settingsSig = (s, now) => [isObj(s) ? s.values : null, isObj(s) ? s.statusline : null, isObj(s) ? s.refused : null, isObj(s) ? s.error : null, flashing(s, now) ? s.saved.key : null]

// settingsModel({ settings, record, now }) -> { rows: [{ key, value, note, mine, choices|number,
// saved, refused }], error, reading }. `record` only says which models the user set (record.settings.models,
// read-only); every value is the kernel's.
export function settingsModel(input) {
  try {
    const { settings, record, now, fresh, motion } = isObj(input) ? input : {}
    const marks = isObj(fresh) ? fresh : {}
    const s = isObj(settings) ? settings : null
    if (!s || !isObj(s.values)) return { rows: [], error: s && s.error ? s.error : null, reading: !s || !s.error }
    const mine = isObj(record) && isObj(record.settings) && isObj(record.settings.models) ? record.settings.models : {}
    const rows = []
    for (const r of ROWS) {
      const got = r.key === 'statusline' ? s.statusline : s.values[r.key]
      if (!isObj(got)) continue // a setting this kernel does not report has no row
      const value = String(got.value)
      const n = r.number && /^\d+$/.test(value) ? Number(value) : r.number && r.number.unset ? r.number.unset : null
      rows.push({
        key: r.key, value: value === 'null' && r.number ? 'not set' : value,
        note: [r.key === 'check_jobs' ? got.limit : null, r.readonly || null, r.scope ? r.scope : null, r.key === 'auto' || r.key === 'interview.kept' ? str(got.note) : null].filter(Boolean).join(' · '),
        mine: Boolean(r.role && r.key.startsWith('model.') && str(mine[r.role])), role: r.role || null, label: r.label || r.role || r.key, status: Boolean(r.status),
        ...(r.readonly ? { readonly: true } : {}),
        ...(r.choices ? { choices: r.choices } : {}),
        ...(r.number ? { number: { ...r.number, at: n } } : {}),
        unit: r.unit || '',
        saved: flashing(s, now) && s.saved.key === r.key,
        refused: isObj(s.refused) && s.refused.key === r.key ? s.refused.text : null,
        fresh: Object.prototype.hasOwnProperty.call(marks, 'settings:' + r.key),
      })
    }
    return { rows, error: s.error || null, reading: false, motion }
  } catch {
    return { rows: [], error: 'VBW could not read the settings here.', reading: false }
  }
}

// The headings the rows sit under, in the order drawn; each row names its own.
export const GROUPS = ['Models', 'Effort', 'Agents', 'How VBW talks to you', 'How VBW works', 'Checks', 'Look and sound', 'Claude Code']

// One line per row: the name in its colour, then its controls, the ✓ saved flash and the new
// mark; under it its note dim and the kernel's refusal in amber. A choice row is one button per
// choice, `● value` lit in the accent, the others `○ choice` dim: every choice is one click. Never
// a Select: the terminal opens one from the keyboard only. A number row is `− value +` and
// default. The controls wrap under themselves, never under the name.
export function renderSettings(ui, model, act) {
  const { Box, Text, Button } = isObj(ui) ? ui : {}
  const m = isObj(model) ? model : { rows: [] }
  const press = (key, value) => () => { if (typeof act === 'function') act({ setting: { key, value: String(value) } }) }
  if (!Array.isArray(m.rows) || !m.rows.length) {
    return h(Box, { key: 'settings', flexDirection: 'column' },
      m.error ? h(Text, { key: 'settings-error', color: NEED }, m.error) : h(Text, { key: 'settings-reading', dimColor: true }, 'Reading the settings…'))
  }
  // A model row is named by its role alone, under the Models heading, and an interview row by
  // what it asks; each group pads its names to its own longest.
  const label = (r) => r.label || r.role || r.key
  const groupOf = (r) => (rowOf(r.key) || {}).group || ''
  const widthOf = (g) => Math.max(...m.rows.filter((r) => groupOf(r) === g).map((r) => label(r).length)) + 2
  const done = stateColor('done')
  const chip = (r, c) => c === r.value
    ? h(Button, { key: 'set-' + r.key + '-' + c, label: c, plain: true, variant: 'primary', onPress: press(r.key, c) },
      h(Text, { key: 'chip' }, h(Text, { key: 'mark', color: ACCENT }, '● '), h(Text, { key: 'value', bold: true, color: ACCENT }, c)))
    : h(Button, { key: 'set-' + r.key + '-' + c, label: c, plain: true, dimColor: true, onPress: press(r.key, c) },
      h(Text, { key: 'chip', dimColor: true }, '○ ' + c))
  const kids = []
  let group = null
  for (const r of m.rows) {
    const g = groupOf(r)
    const nameW = widthOf(g)
    if (g && g !== group) {
      group = g
      kids.push(h(Text, { key: 'group:' + g, bold: true, dimColor: true }, (kids.length ? '\n' : '') + g))
    }
    const under = (k, text) => h(Box, { key: k + '-line', flexDirection: 'row' }, h(Text, { key: 'indent' }, ' '.repeat(nameW)), text)
    let controls
    if (r.readonly) {
      controls = [h(Text, { key: 'value', color: ACCENT }, r.value)]
    } else if (r.status) {
      // Dynamic workflows: on is done; Claude Code's default may be off on some plans, so it offers
      // turn on; off on purpose (disableWorkflows) is the user's, said and never overridden.
      const on = r.value === 'on'
      const text = on ? STATE_MARKS.done + ' on' : r.value === 'default' ? '⚠ Claude Code decides (off on some plans)' : '⚠ off on purpose: VBW needs them to plan and build'
      controls = [h(Text, { key: 'value', color: on ? done : NEED }, text),
        ...(r.value === 'default' ? [h(Button, { key: 'set-' + r.key + '-on', label: 'turn on', variant: 'primary', onPress: press(r.key, 'on') })] : [])]
    } else if (r.choices) {
      controls = r.choices.map((c) => chip(r, c))
    } else {
      const n = r.number
      const at = Number.isFinite(n.at) ? n.at : n.min
      const value = r.value + (r.unit && /^\d+$/.test(r.value) ? ' ' + r.unit : '')
      controls = [
        h(Button, { key: 'set-' + r.key + '-down', label: '−', onPress: press(r.key, Math.max(n.min, at - n.step)) }),
        h(Text, { key: 'value', bold: true, color: ACCENT }, value),
        h(Button, { key: 'set-' + r.key + '-up', label: '+', onPress: press(r.key, Math.min(n.max, at + n.step)) }),
        ...(r.key === 'autonomy_cap' ? [] : [h(Button, { key: 'set-' + r.key + '-default', label: 'default', plain: true, dimColor: true, onPress: press(r.key, 'default') })]),
      ]
    }
    kids.push(h(Box, { key: 'setting:' + r.key, flexDirection: 'column' },
      h(Box, { key: 'line', flexDirection: 'row' },
        // The name's box never shrinks: wide choices wrap under themselves, the name keeps its gap.
        h(Box, { key: 'name-cell', flexShrink: 0 }, h(Text, { key: 'name', ...(r.role ? { color: roleColor(r.role) } : {}) }, label(r).padEnd(nameW))),
        h(Box, { key: 'controls', flexDirection: 'row', flexWrap: 'wrap', columnGap: 2, flexShrink: 1 },
          ...controls,
          r.mine ? h(Text, { key: 'mine', dimColor: true }, '(set by you)') : null,
          r.saved ? h(Text, { key: 'saved', color: done }, STATE_MARKS.done + ' saved') : null,
          r.fresh ? newMark(Text, m.motion) : null)),
      r.note ? under('note', h(Text, { key: 'note', dimColor: true }, r.note)) : null,
      r.refused ? under('refused', h(Text, { key: 'refused', color: NEED }, r.refused)) : null))
  }
  if (m.error) kids.push(h(Text, { key: 'settings-error', color: NEED }, m.error))
  return h(Box, { key: 'settings', flexDirection: 'column' }, ...kids)
}
