// Panel cost driver (tools/bench-panel.sh runs it). Mounts plugin/hooks/panel.js
// on the test stand-in for Claude Code and measures the CPU time (user + system,
// not waiting time) of two refreshes, averaged over VBW_BENCH_RUNS:
//   tick: the timer fires and finds nothing new (files unchanged, only checked);
//   refresh: the timer fires, a file changed, the panel reads it, redraws and
//   the draw is rendered.
//   sound: a need for the user appears and the sound is played (the next tick it ends).
//   glance: the cost changed and a step history changed: both are read, both estimates worked out, drawn.
// Prints "tick <ms>", "refresh <ms>" and "sound <ms>". The stand-in's own work is included,
// so the numbers are an upper bound on the panel's cost.
import { mount, record, next } from '../tests/panel/helpers/fake-mod.mjs'

const RUNS = Number(process.env.VBW_BENCH_RUNS || 200)
const TICK_MS = 2000
const ROOT = '/proj'

const cpu = () => {
  const u = process.cpuUsage()
  return (u.user + u.system) / 1000
}

async function measure(step) {
  const h = await mount()
  h.project(record(), next())
  h.git()
  await h.start()
  await h.advance(5000)
  await h.render()
  for (let i = 0; i < 20; i++) await step(h, i) // warm up
  const t0 = cpu()
  for (let i = 0; i < RUNS; i++) await step(h, i)
  return (cpu() - t0) / RUNS
}

const tick = await measure(async (h) => {
  await h.advance(TICK_MS)
})
const refresh = await measure(async (h, i) => {
  h.write(ROOT + '/.vbw/runtime/next.json', next({ action: i % 2 ? 'build' : 'ship', gate: i % 2 === 0 }))
  await h.advance(TICK_MS)
  await h.render()
})
// sound: a need appears (the sound is asked to play), then goes away
const sound = await measure(async (h, i) => {
  h.write(ROOT + '/.vbw/runtime/next.json', next(i % 2 === 0 ? { action: 'approve', gate: true } : {}))
  await h.advance(TICK_MS)
})
// glance: a refresh that also reads the session cost and works out both estimates
const STEPS = ROOT + '/.git/vbw/steps.json'
const steps = (kind, secs) => secs.map((s, i) => ({ kind, run: kind + '-' + i, seconds: s }))
const glance = await measure(async (h, i) => {
  h.write(STEPS, { steps: [...steps('build', [600, 900, 1200 + i]), ...steps('qa', [100, 200, 300])] })
  h.setUsage({ cost: { usd: 1 + i / 100 } })
  await h.advance(TICK_MS)
  await h.render()
})
console.log('tick ' + tick.toFixed(3))
console.log('refresh ' + refresh.toFixed(3))
console.log('sound ' + sound.toFixed(3))
console.log('glance ' + glance.toFixed(3))
