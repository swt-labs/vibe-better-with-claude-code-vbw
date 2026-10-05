// Panel cost driver (tools/bench-panel.sh runs it). Mounts plugin/hooks/panel.js
// on the test stand-in for Claude Code and measures the CPU time (user + system,
// not waiting time) of two refreshes, averaged over VBW_BENCH_RUNS:
//   tick: the timer fires and finds nothing new (files unchanged, only checked);
//   refresh: the timer fires, a file changed, the panel reads it, redraws and
//   the draw is rendered.
// Prints "tick <ms>" and "refresh <ms>". The stand-in's own work is included,
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
console.log('tick ' + tick.toFixed(3))
console.log('refresh ' + refresh.toFixed(3))
