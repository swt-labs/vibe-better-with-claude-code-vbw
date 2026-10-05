// Honest time estimates for the VBW panel (R58). Pure: finished steps in, an
// estimate out. The usual time of a kind of step is the median of the last 10
// finished steps of that kind; fewer than MIN_STEPS means no basis, and no number.
export const MIN_STEPS = 3
const WINDOW = 10

const ok = (s) => s !== null && typeof s === 'object' && typeof s.kind === 'string' && Number.isFinite(s.seconds) && s.seconds > 0

// The usual time of a kind of step in seconds, or null without enough history.
function usual(steps, kind) {
  const secs = steps.filter((s) => ok(s) && s.kind === kind).slice(-WINDOW).map((s) => s.seconds).sort((a, b) => a - b)
  if (secs.length < MIN_STEPS) return null
  const m = secs.length >> 1
  return secs.length % 2 ? secs[m] : (secs[m - 1] + secs[m]) / 2
}

// input: { steps, lease: {kind, started_at} | null, phasesLeft, now (ms) }
export function estimate(input) {
  const { lease, now } = input || {}
  const steps = Array.isArray(input && input.steps) ? input.steps : []
  const phasesLeft = Number.isFinite(input && input.phasesLeft) ? Math.max(0, input.phasesLeft) : 0
  const started = lease && typeof lease.started_at === 'string' ? Date.parse(lease.started_at) : NaN
  const elapsed = Number.isFinite(started) && Number.isFinite(now) ? Math.max(0, (now - started) / 1000) : 0

  // What the running step has left: a number of seconds, 0 once it runs long, null without a basis.
  const own = lease ? usual(steps, lease.kind) : null
  const left = own === null ? null : Math.max(0, own - elapsed)

  let step = null
  if (lease) {
    step = own === null || !Number.isFinite(started) ? { state: 'none' } : left > 0 ? { state: 'approx', seconds: Math.round(left) } : { state: 'longer' }
  }

  let milestone = null
  if (phasesLeft > 0) {
    const build = usual(steps, 'build')
    const check = usual(steps, 'qa')
    if (build === null || check === null) milestone = { state: 'none' }
    else {
      const phase = build + check
      const counts = lease && (lease.kind === 'build' || lease.kind === 'qa')
      const running = left === null ? 0 : left
      const whole = counts ? phasesLeft - 1 : phasesLeft
      milestone = { state: 'approx', seconds: Math.round(running + whole * phase) }
    }
  }
  return { step, milestone }
}
