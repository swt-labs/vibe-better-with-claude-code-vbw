// What VBW's instant mod commands say (mods_4_vbw.md §3.6): /vbw-status, /vbw-why
// and /vbw-todo run with no model turn. Pure: data in, text or argv out; it never
// changes its input and never throws. Sentences come from panel-view.js, so the
// commands and the panel say the same thing. The kernel writes: /vbw-todo only
// builds the argv the mod hands to `vbw`.

import { panelView } from './panel-view.js'

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const NEUTRAL = 'No VBW project is open here yet.'
const LEASE_HOURS = 24 // docs/workflows.md: an older run no longer holds the project

// A non-gate next step in plain words.
const STEPS = {
  plan: 'plan the work', build: 'build the plan', fix: 'fix what the checks found',
  prove: 'run the checks', qa: 'check the results', run: 'finish the open run', map: 'map the project',
}

const clock = (n) => (Number.isFinite(n) ? n : Date.now())
const project = (input) => {
  const { record, next, now, sessionId } = isObj(input) ? input : {}
  const v = panelView({ record, next, now: clock(now) })
  return v.rows[0].id === 'neutral' ? null : { v, rec: record, nx: next, now: clock(now), sessionId }
}

// /vbw-status: the milestone, its progress, what VBW is doing, then the user's turn or the next step.
export function statusText(input) {
  const p = project(input)
  if (!p) return NEUTRAL
  const row = (id) => p.v.rows.find((r) => r.id === id).text
  const out = [row('milestone'), row('progress'), row('doing')]
  if (!isObj(p.rec.lease)) {
    if (p.v.need) out.push(p.v.need.text)
    else if (!isObj(p.nx) || !p.nx.action) out.push('Next: run /vbw:vibe.')
    else out.push('Next: ' + (STEPS[p.nx.action] || String(p.nx.action)) + ' (/vbw:vibe carries on).')
  }
  return out.join('\n')
}

function leaseLine(l, now, sessionId) {
  const start = Date.parse(l.started_at)
  const ms = now - start
  const mins = Number.isFinite(ms) ? Math.floor(ms / 60000) : NaN
  const who = typeof l.session !== 'string' || !l.session ? 'a session VBW cannot name'
    : (l.session === sessionId ? 'this session' : 'another session') + ' (' + l.session.slice(0, 8) + ')'
  const since = Number.isFinite(start)
    ? ' since ' + new Date(start).toISOString().slice(11, 16) + ' UTC (' + (mins >= 1 ? mins + ' min ago' : 'just started') + ')' : ''
  const f = l.files
  const files = f === null || f === undefined ? 'may write any file'
    : !Array.isArray(f) || f.length === 0 ? 'write no files'
      : 'may write ' + f.length + (f.length === 1 ? ' file' : ' files')
  const out = ['A ' + String(l.kind || 'VBW') + ' run is open, held by ' + who + since + '; its agents ' + files + '.']
  if (mins >= LEASE_HOURS * 60) out.push('It is older than ' + LEASE_HOURS + ' hours, so VBW no longer holds the project to it.')
  else if (l.session && l.session !== sessionId) out.push('Wait for it to finish in that session.')
  return out
}

// /vbw-why: who holds the run and since when, and what blocks the next step.
export function whyText(input) {
  const p = project(input)
  if (!p) return NEUTRAL
  const blocked = (Array.isArray(p.rec.plans) ? p.rec.plans : [])
    .filter((x) => isObj(x) && x.status === 'blocked')
    .map((x) => x.id + (x.title ? ' (' + x.title + ')' : '') + ' is blocked: ' + (x.note || 'no reason given') + '.')
  const open = isObj(p.rec.lease)
  if (!open && !p.v.need && blocked.length === 0) return 'Nothing is running and nothing is blocked.'
  const out = open ? leaseLine(p.rec.lease, p.now, p.sessionId) : ['Nothing is running.']
  if (p.v.need) out.push(p.v.need.text)
  return out.concat(blocked).join('\n')
}

const words = (x) => (typeof x === 'string' ? x : Array.isArray(x) ? x.filter((w) => typeof w === 'string').join(' ') : '')
  .replace(/\s+/g, ' ').trim()

// /vbw-todo [text]: the typed text, else the selected text, parked by `vbw todo add`.
export function todoArgs(input) {
  const { args, selection } = isObj(input) ? input : {}
  const text = words(args) || words(isObj(selection) ? selection.text : selection)
  return text
    ? { argv: ['todo', 'add', text], message: null }
    : { argv: null, message: 'Usage: /vbw-todo TEXT parks an idea for later; with no text, select the idea first.' }
}
