// The running step as the panel says it (R190): one pure wording of the kernel's
// note (.vbw/runtime/step.json) at a moment, so Mission Control, its Timeline and
// Comms read alike. The panel never works a step's time out itself: the note
// carries the end, and this file only words it.
//   about 12 min, until around 14:20
//   less than a minute, until around 14:20
//   until around 14:35, later than usual      (parts; the kernel moved the end)
//   until around 14:20, 6 min late            (no parts; the first end stays)
//   until around tomorrow 00:20               (an end on another day)
//   No end time yet: VBW has timed fewer than 3 steps like this here
// Pure: data in, text out; never throws.

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const str = (x) => (typeof x === 'string' ? x : '')
const MIN_MS = 60000
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

export const NO_END = 'No end time yet: VBW has timed fewer than 3 steps like this here'

const two = (n) => String(n).padStart(2, '0')
const stamp = (d) => two(d.getHours()) + ':' + two(d.getMinutes())
const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()

// Every moment the panel prints (design rule 5): the kernel's step_clock rule
// (plugin/lib/steps.sh), 'HH:MM' in local 24-hour time today, else 'yesterday HH:MM',
// 'tomorrow HH:MM' or the weekday's name; '' when `ms` is not a moment. `now` (ms) is
// the moment it is said at; without one the day is not named.
export function dayClock(ms, now) {
  if (typeof ms !== 'number' || !Number.isFinite(ms)) return ''
  const e = new Date(ms)
  const days = typeof now === 'number' && Number.isFinite(now) ? Math.round((midnight(e) - midnight(new Date(now))) / 86400000) : 0
  const day = days === 0 ? '' : days === 1 ? 'tomorrow ' : days === -1 ? 'yesterday ' : DAY_NAMES[e.getDay()] + ' '
  return day + stamp(e)
}

// A proof's note counts only while its process lives (R190.27): a killed proof leaves
// the note behind. EPERM means the process exists; no pid on the note is not a verdict.
function alive(pid) {
  if (typeof pid !== 'number') return true
  try {
    process.kill(pid, 0)
    return true
  } catch (e) {
    return !!e && e.code === 'EPERM'
  }
}

// The note a panel keeps only while it is live: its run is the record's open run, or it
// is a proof of this session (a proof holds no lease). Anything else is no step here.
export function liveStep(note, rec, sessionId) {
  if (!isObj(note) || !str(note.kind)) return null
  if (note.kind === 'proof') return sessionId && note.session === sessionId && alive(note.pid) ? note : null
  const lease = isObj(rec) && isObj(rec.lease) ? rec.lease : null
  return lease && str(note.run) && lease.run === note.run ? note : null
}

// { text, timed } for a note at `now` (ms); null when it is not a note. `timed` is
// true when the text carries an end time.
export function stepWords(note, now) {
  try {
    if (!isObj(note)) return null
    const end = Date.parse(note.end)
    if (!Number.isFinite(end)) return { text: NO_END, timed: false }
    const t = Number.isFinite(now) ? now : Date.now()
    const at = 'until around ' + dayClock(end, t)
    const lowMs = Date.parse(note.end_low)
    const highMs = Date.parse(note.end_high)
    const rg = note.rough === true && Number.isFinite(lowMs) && Number.isFinite(highMs)
    const runs = Number.isFinite(note.runs) ? note.runs : 0
    const tag = rg ? ' (rough guess from ' + runs + (runs === 1 ? ' run)' : ' runs)') : ''
    const left = end - t
    const hasParts = isObj(note.parts)
    if (hasParts && (note.late === true || left <= 0)) return { text: at + ', later than usual' + tag, timed: true }
    if (!hasParts && left <= -MIN_MS) return { text: at + ', ' + Math.floor(-left / MIN_MS) + ' min late' + tag, timed: true }
    if (left < MIN_MS) return { text: (left > 0 ? 'less than a minute, ' + at : at) + tag, timed: true }
    if (rg) {
      const lo = Math.min(lowMs, end)
      const hi = Math.max(highMs, end)
      const mins = (ms) => Math.max(1, Math.round((ms - t) / MIN_MS))
      const lm = mins(lo)
      const hm = mins(hi)
      if (lm === hm) return { text: 'roughly ' + lm + ' min, ' + at + tag, timed: true }
      const ty = Math.min(Math.max(Number.isFinite(Date.parse(note.end_typical)) ? Date.parse(note.end_typical) : end, lo), hi)
      return { text: 'usually about ' + mins(ty) + ' min (' + lm + ' to ' + hm + ' min, rough guess from ' + runs + (runs === 1 ? ' run' : ' runs') + '), until around ' + dayClock(ty, t) + ' (' + dayClock(lo, t) + ' to ' + dayClock(hi, t) + ')', timed: true }
    }
    return { text: 'about ' + Math.max(1, Math.round(left / MIN_MS)) + ' min, ' + at, timed: true }
  } catch {
    return null
  }
}
