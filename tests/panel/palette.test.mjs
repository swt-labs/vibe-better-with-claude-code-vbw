// R84: every part of the panel (the band, Mission Control, Wrapped) takes its
// colours from one shared palette (plugin/hooks/panel-palette.js): a role has
// one colour everywhere and a state has one colour everywhere. Pure: no Claude
// Code needed (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'
import { PLUGIN, record, deepFreeze, walk, find } from './helpers/fake-mod.mjs'

const P = await import(pathToFileURL(PLUGIN + '/hooks/panel-palette.js').href)
const stage = await import(pathToFileURL(PLUGIN + '/hooks/panel-stage.js').href)
const live = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-live.js').href)
const mr = await import(pathToFileURL(PLUGIN + '/hooks/panel-mission-record.js').href)
const candy = await import(pathToFileURL(PLUGIN + '/hooks/panel-candy.js').href)

const EL = (name) => Object.freeze({ element: name })
const UI = { Box: EL('Box'), Text: EL('Text'), Button: EL('Button') }
const NOW = 1_800_000_000_000
const S = 1000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const ROLE_WANT = { architect: 'magenta', lead: 'blue', dev: 'green', qa: 'yellow', scout: 'cyan', debugger: 'red', docs: '#ff87d7' }
const STATES = ['running', 'done', 'failed', 'quiet', 'cut']
const hex = (n) => '#' + n.toString(16).padStart(6, '0')

// --- the palette itself --------------------------------------------------------

test('roles: architect magenta, lead blue, dev green, qa yellow, scout cyan, debugger red, docs pink', () => {
  for (const [role, want] of Object.entries(ROLE_WANT)) assert.equal(P.roleColor(role), want, role)
  assert.deepEqual({ ...P.ROLE_COLORS }, ROLE_WANT)
  assert.equal(new Set(ROLES.map((r) => P.roleColor(r))).size, 7, 'no two roles share a colour')
})

test('states: running amber, done green, failed red, quiet and cut off grey', () => {
  assert.equal(P.stateColor('running'), '#ffaf00')
  assert.equal(P.stateColor('done'), 'green')
  assert.equal(P.stateColor('failed'), 'red')
  assert.equal(P.stateColor('quiet'), 'gray')
  assert.equal(P.stateColor('cut'), 'gray')
  assert.notEqual(P.stateColor('running'), P.roleColor('qa'), 'amber is not the qa yellow')
})

test('an unknown role or state falls back to the neutral grey and never throws', () => {
  assert.equal(P.NEUTRAL, 'gray')
  for (const x of ['mystery', '', 'agent', undefined, null, 7, {}, [], 'constructor', '__proto__']) {
    assert.equal(P.roleColor(x), P.NEUTRAL, 'role ' + String(x))
    assert.equal(P.stateColor(x), P.NEUTRAL, 'state ' + String(x))
  }
})

test('states carry a mark and a word as well as a colour, so colour off still tells them apart', () => {
  for (const s of STATES) {
    assert.ok(typeof P.STATE_MARKS[s] === 'string' && P.STATE_MARKS[s].trim() !== '', 'mark of ' + s)
    assert.ok(typeof P.STATE_WORDS[s] === 'string' && /^[a-z ]+$/.test(P.STATE_WORDS[s]), 'word of ' + s)
  }
  assert.equal(P.STATE_WORDS.running, 'running')
  assert.equal(P.STATE_WORDS.done, 'done')
  assert.equal(P.STATE_WORDS.failed, 'failed')
  assert.equal(P.STATE_WORDS.quiet, 'quiet')
  assert.equal(new Set(STATES.map((s) => P.STATE_MARKS[s])).size, STATES.length, 'each state has its own mark')
  assert.equal(new Set(STATES.map((s) => P.STATE_WORDS[s])).size, STATES.length, 'each state has its own word')
})

test('key values: progress green, estimate amber, a need of the user yellow, cost in its own accent', () => {
  assert.equal(P.PROGRESS, 'green')
  assert.equal(P.ESTIMATE, '#ffaf00')
  assert.equal(P.NEED, 'yellow')
  const used = new Set([...ROLES.map((r) => P.roleColor(r)), ...STATES.map((s) => P.stateColor(s)), P.NEUTRAL, P.NEED])
  assert.ok(typeof P.ACCENT === 'string' && P.ACCENT !== '' && !used.has(P.ACCENT), 'the accent is a colour nothing else uses')
})

test('rgb turns any palette colour into the number a Raster cell takes', () => {
  assert.equal(P.rgb('#ff87d7'), 0xff87d7)
  for (const c of [...ROLES.map((r) => P.roleColor(r)), ...STATES.map((s) => P.stateColor(s)), P.ACCENT, P.NEED, P.NEUTRAL]) {
    const n = P.rgb(c)
    assert.ok(Number.isInteger(n) && n >= 0 && n <= 0xffffff, String(c) + ' -> ' + n)
  }
  assert.equal(new Set(ROLES.map((r) => P.rgb(P.roleColor(r)))).size, 7, 'roles stay apart as pixels too')
  assert.equal(P.rgb('no such colour'), P.rgb(P.NEUTRAL))
  assert.equal(P.rgb(undefined), P.rgb(P.NEUTRAL))
})

// --- every surface reads it ----------------------------------------------------

const agent = (over = {}) => ({
  id: 'a1', role: 'architect', label: 'scope', model: 'opus', state: 'working',
  activity: { kind: 'tool', text: 'reading spec.md' }, startedAt: NOW - 130 * S, endedAt: null, lastSeenAt: NOW - 2 * S, tokens: 4200, result: null, ...over,
})
const run = (agents, over = {}) => ({ runId: 'wf_1', kind: 'building', phase: 'wave 1', startedAt: NOW - 600 * S, endedAt: null, status: 'running', agents, ...over })

test('the band: a row wears its role colour; done, failed and quiet wear their state colours', () => {
  const agents = [...ROLES.map((role) => agent({ id: role, role })), agent({ id: 'x', role: 'mystery' }),
    agent({ id: 'd', state: 'done', endedAt: NOW - 5 * S, result: 'ok' }), agent({ id: 'f', state: 'failed', endedAt: NOW - 5 * S, result: 'boom' }),
    agent({ id: 'q', state: 'quiet', lastSeenAt: NOW - 90 * S })]
  const m = stage.stageModel({ now: NOW, maxRows: 30, columns: 100, motion: 'calm', run: deepFreeze(run(agents)) })
  const row = (id) => m.rows.find((r) => r.id === id)
  for (const role of ROLES) assert.equal(row(role).roleColor, P.roleColor(role), role)
  assert.equal(row('x').roleColor, P.NEUTRAL, 'an unknown role is neutral grey')
  assert.equal(row('d').glyphColor, P.stateColor('done'))
  assert.equal(row('f').glyphColor, P.stateColor('failed'))
  assert.equal(row('q').activityColor, P.stateColor('quiet'), 'quiet is grey, not amber')
})

test('Mission Control, Now: a card carries the role colour; an unknown role and an unknown state are neutral', () => {
  const m = live.nowModel({ run: deepFreeze(run([...ROLES.map((role) => agent({ id: role, role })), agent({ id: 'x', role: 'mystery', state: 'weird' })])), now: NOW })
  const cards = m.columns.flatMap((c) => c.cards)
  for (const role of ROLES) assert.equal(cards.find((c) => c.id === role).roleColor, P.roleColor(role), role)
  const x = cards.find((c) => c.id === 'x')
  assert.equal(x.roleColor, P.NEUTRAL)
  assert.equal(x.frame, P.NEUTRAL)
})

test('Mission Control, Timeline: a lane carries the role colour', () => {
  const m = live.timelineModel({ run: deepFreeze(run(ROLES.map((role, i) => agent({ id: role, role, startedAt: NOW - (300 - i) * S })))), now: NOW, steps: [], width: 40 })
  for (const role of ROLES) assert.equal(m.lanes.find((l) => l.id === role).color, P.roleColor(role), role)
})

test('Mission Control, Team: a role row carries the role colour', () => {
  const m = mr.teamModel({ record: deepFreeze(record()) })
  for (const role of ROLES) assert.equal(m.rows.find((r) => r.role === role).color, P.roleColor(role), role)
})

test('Mission Control, Proof: passed is the done colour, failing the failed colour, running the running colour, not run grey', () => {
  const rec = deepFreeze(record({
    requirements: [{ id: 'R2', text: 'It works', proof: 'auto', status: 'failing', milestone: 'M9' }],
    checks: ['C1', 'C2', 'C3', 'C4', 'C5'].map((id) => ({ id, req: 'R2', run: ['true'] })),
    evidence: { at: '2026-10-03T11:00:00Z', passed: false, checks: { C1: { status: 'pass', exit: 0 }, C2: { status: 'fail', exit: 1 }, C3: { status: 'pass', exit: 0 } } },
  }))
  const m = mr.proofModel({ record: rec, running: ['C3'] })
  const colour = (id) => m.cells.find((c) => c.id === id).color
  assert.equal(colour('C1'), P.stateColor('done'))
  assert.equal(colour('C2'), P.stateColor('failed'))
  assert.equal(colour('C3'), P.stateColor('running'))
  assert.equal(colour('C4'), P.stateColor('quiet'))
})

test('Wrapped: the card, its border and the confetti, sprites and sweep use palette colours', () => {
  const model = {
    milestone: { id: 'M9', title: 'Live VBW panel' }, requirements: { proven: 2, total: 2 }, checks: { passing: 3, total: 3 },
    agents: 4, fixRounds: 0, seconds: 600, cost: 1.5, fastest: null, slowest: null,
  }
  const tree = candy.renderWrapped(UI, model)
  assert.equal(tree.props.borderColor, P.stateColor('done'))
  assert.equal(find(tree, (n) => n.type === 'Text' && n.props.bold).props.color, P.stateColor('done'))

  const pieces = new Set(ROLES.map((r) => P.rgb(P.roleColor(r))))
  const fgs = new Set(candy.confettiFrames({ cols: 30, rows: 4, seed: 7 }).flatMap((f) => f.cells.filter((c) => c.ch !== ' ').map((c) => c.fg)))
  assert.ok(fgs.size > 0)
  for (const fg of fgs) assert.ok(pieces.has(fg), 'confetti piece ' + hex(fg) + ' is a role colour of the palette')

  for (const role of ROLES) {
    const fig = candy.spriteFrame({ role, pose: 'reading', frame: 0 }).cells[1].fg
    assert.equal(fig, P.rgb(P.roleColor(role)), role)
  }
  assert.equal(candy.spriteFrame({ role: 'nobody', pose: 'reading', frame: 0 }).cells[1].fg, P.rgb(P.NEUTRAL))

  const sweep = candy.sweepFrames({ cols: 20, n: 6 }).flatMap((f) => f.cells.filter((c) => c.ch !== ' ').map((c) => c.fg))
  assert.ok(sweep.length > 0)
  for (const fg of sweep) assert.equal(fg, P.rgb(P.stateColor('done')))
})

// --- no colour of its own anywhere ---------------------------------------------

const HOOKS = PLUGIN + '/hooks'
const surfaces = fs.readdirSync(HOOKS).filter((f) => /^panel.*\.js$/.test(f) && f !== 'panel-palette.js')
const code = (file) => fs.readFileSync(HOOKS + '/' + file, 'utf8').split('\n')
  .filter((l) => !/^\s*\/\//.test(l)).map((l) => l.replace(/\s\/\/.*$/, '')).join('\n')

test('the panel files are found, and the band, Mission Control and Wrapped import the palette', () => {
  for (const f of ['panel-stage.js', 'panel-mission-live.js', 'panel-mission-record.js', 'panel-pane.js', 'panel-candy.js']) {
    assert.ok(surfaces.includes(f), f)
    assert.match(code(f), /from '\.\/panel-palette\.js'/, f + ' reads its colours from the palette')
  }
})

test('no panel file but the palette holds a colour literal: no colour name, #rrggbb, 0xrrggbb or escape code', () => {
  const NAME = /(['"`])(?:black|red|green|yellow|blue|magenta|cyan|white|gray|grey|(?:bright|light|dark)[A-Za-z]*)\1/
  for (const f of surfaces) {
    const src = code(f)
    assert.doesNotMatch(src, NAME, f + ' names a colour')
    assert.doesNotMatch(src, /#[0-9a-fA-F]{6}\b/, f + ' has a #rrggbb colour')
    assert.doesNotMatch(src, /\b0x[0-9a-fA-F]{6}\b/, f + ' has a 0xrrggbb colour')
    assert.doesNotMatch(src, /\\x1b|\\u001b|\\033|\\e\[/i, f + ' writes a colour escape code')
  }
})

test('a rendered tree has no colour outside the palette: every colour prop is one the palette defines', () => {
  const defined = new Set([...Object.values(P.ROLE_COLORS), ...Object.values(P.STATE_COLORS), P.NEUTRAL, P.ACCENT, P.NEED, P.PROGRESS, P.ESTIMATE])
  const agents = ROLES.map((role) => agent({ id: role, role })).concat([agent({ id: 'd', state: 'done', result: 'ok' }), agent({ id: 'f', state: 'failed', result: 'x' }), agent({ id: 'q', state: 'quiet', lastSeenAt: NOW - 99 * S })])
  const trees = [
    stage.renderStage(UI, stage.stageModel({ now: NOW, maxRows: 30, columns: 100, motion: 'calm', run: run(agents) })),
    live.renderNow(UI, live.nowModel({ run: run(agents), now: NOW })),
    live.renderTimeline(UI, live.timelineModel({ run: run(agents), now: NOW, steps: [], width: 40 })),
    mr.renderTeam(UI, mr.teamModel({ record: record() })),
  ]
  let seen = 0
  for (const t of trees) {
    walk(t, (n) => {
      for (const k of ['color', 'borderColor', 'backgroundColor']) {
        if (n.props && n.props[k] !== undefined) {
          seen++
          assert.ok(defined.has(n.props[k]), k + ' ' + String(n.props[k]) + ' is not in the palette')
        }
      }
    })
  }
  assert.ok(seen > 20, 'colours were found to check')
})
