// Delight wired into the panel (mods_4_vbw.md §3.1 crew theme, §3.7): the motion
// level from the setting or the interview level, the crew's sprites blitted while
// a run works, confetti when a phase passes QA, the all-green sweep and line, the
// Wrapped card at ship and the VBW portrait. Driven through the stand-in for
// Claude Code's mods API (L1): nothing here draws in a real terminal.
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { mount, record, next, lease, collect, find, walk, ROOT, T0, PLUGIN, PANE } from './helpers/fake-mod.mjs'
import { ENV, ARCH, LEAD, writeRun, finish, launch, band } from './helpers/run.mjs'

const TEST_MODE = ROOT + '/.vbw/runtime/test-mode'
const BAND = 'AbovePrompt-1'

async function started(options = {}, rec = record(), nxt = next()) {
  const h = await mount({ env: ENV, ...options })
  h.project(rec, nxt)
  await h.start()
  await h.settle()
  return h
}
const text = (tree) => collect(tree).join('\n')
const rasters = (tree) => {
  const out = []
  walk(tree, (n) => n.type === 'Raster' && out.push(n))
  return out
}
const keys = (tree) => rasters(tree).map((r) => r.props.key)
const blits = (h, key) => h.callsOf('ui.blit').map((a) => a[0]).filter((b) => !key || b.key === key)
const full = (over = {}) => record({ lease: lease('plan', T0), settings: { motion: 'full' }, ...over })
const running = async (h) => {
  writeRun(h, h.now())
  await launch(h)
  await h.advance(2000)
}
const SPRITES = ['vbw-sprite-' + ARCH, 'vbw-sprite-' + LEAD]

// ---- the motion level ----

test('motion: the setting wins; unset, the interview level picks; a test session is always still', async () => {
  const cases = [
    ['setting full', {}, full(), next({ action: 'run' }), true],
    ['interview: never coded (from vbw next)', {}, record({ lease: lease('plan', T0) }), next({ action: 'run', profile: { level: 'never', interviewed: true } }), true],
    ['interview: senior', {}, record({ lease: lease('plan', T0) }), next({ action: 'run', profile: { level: 'senior engineer', interviewed: true } }), false],
    ['no interview yet: vbw next fills a neutral level, which picks nothing', {}, record({ lease: lease('plan', T0) }), next({ action: 'run', profile: { level: 'small scripts or no-code', interviewed: false } }), false],
    ['interview kept in the project', {}, record({ lease: lease('plan', T0), project: { name: 'demo', interview: { level: 'never' } } }), next({ action: 'run' }), true],
    ['setting calm beats the level', {}, record({ lease: lease('plan', T0), settings: { motion: 'calm' } }), next({ action: 'run', profile: { level: 'never', interviewed: true } }), false],
    ['test mode beats setting full', { files: { [TEST_MODE]: '1' } }, full(), next({ action: 'run' }), false],
  ]
  for (const [name, opts, rec, nxt, sprites] of cases) {
    const h = await started(opts, rec, nxt)
    await running(h)
    const tree = await band(h)
    assert.deepEqual(keys(tree), sprites ? SPRITES : [], name)
    assert.match(text(tree), /architect/, name)
    assert.deepEqual(h.errors, [], name)
  }
})

// ---- the crew's sprites ----

test('full: the sprites are blitted at 10 frames a second while the run works, and stop when it ends', async () => {
  const h = await started({}, full(), next({ action: 'run' }))
  await running(h)
  await band(h)
  const n0 = blits(h).length
  await h.advance(1000)
  const shown = blits(h).slice(n0)
  assert.ok(shown.length >= 16 && shown.length <= 22, 'two agents at about 10 fps: ' + shown.length)
  for (const b of shown) {
    assert.equal(b.requestId, BAND)
    assert.ok(SPRITES.includes(b.key), b.key)
    assert.equal(typeof b.cells, 'string')
  }
  assert.ok(new Set(shown.filter((b) => b.key === SPRITES[0]).map((b) => b.cells)).size > 1, 'the sprite moves')
  finish(h, h.now() - 1000)
  await h.advance(2000)
  const n1 = blits(h).length
  await h.advance(2000)
  assert.equal(blits(h).length, n1, 'no run works: no blit')
  assert.deepEqual(keys(await band(h)), [], 'the finished crew stands still')
  assert.deepEqual(h.errors, [])
})

test('calm and off draw dots and blit nothing', async () => {
  for (const motion of ['calm', 'off']) {
    const h = await started({}, record({ lease: lease('plan', T0), settings: { motion } }), next({ action: 'run' }))
    await running(h)
    const tree = await band(h)
    assert.deepEqual(keys(tree), [], motion)
    assert.ok(collect(tree).includes('●'), motion)
    await h.advance(3000)
    assert.equal(blits(h).length, 0, motion)
  }
})

test('the band yielding (a survey) or refusing a blit stops the sprites', async () => {
  const h = await started({}, full(), next({ action: 'run' }))
  await running(h)
  await band(h)
  await band(h, { hasSurvey: true })
  const n = blits(h).length
  await h.advance(1000)
  assert.equal(blits(h).length, n, 'a band not shown is not blitted')

  const d = await started({ blit: () => ({ deny: 'not mounted' }) }, full(), next({ action: 'run' }))
  await running(d)
  await band(d)
  await d.advance(1000)
  assert.ok(blits(d).length <= 2, 'one refused frame stops the loop: ' + blits(d).length)
  assert.deepEqual(d.errors, [])
})

// ---- celebrations ----

const passed = (rec) => ({ ...rec, phases: rec.phases.map((p) => (p.id === 'P44' ? { ...p, qa: { result: 'pass', at: '2026-10-07T10:00:00Z' } } : p)) })

test('a phase passing QA bursts confetti in the band for about 1.5 s, at full motion only', async () => {
  const h = await started({}, record({ settings: { motion: 'full' } }))
  h.project(passed(record({ settings: { motion: 'full' } })))
  await h.advance(2000)
  const tree = await band(h)
  const c = rasters(tree).find((r) => r.props.key === 'vbw-confetti')
  assert.ok(c, 'confetti drawn: ' + keys(tree))
  assert.deepEqual([c.props.columns, c.props.rows], [100, 3])
  await h.advance(1000)
  const n = blits(h, 'vbw-confetti').length
  assert.ok(n >= 8 && n <= 11, 'frames blitted: ' + n)
  assert.ok(blits(h, 'vbw-confetti').every((b) => b.requestId === BAND))
  await h.advance(1000)
  assert.equal(blits(h, 'vbw-confetti').length, 14, 'one burst of 15 frames: the first drawn, 14 blitted')
  assert.equal(rasters(await band(h)).length, 0, 'the burst is over')
  await h.advance(2000)
  assert.equal(blits(h).length, 14)

  const calm = await started({}, record({ settings: { motion: 'calm' } }))
  calm.project(passed(record({ settings: { motion: 'calm' } })))
  await calm.advance(2000)
  assert.equal(rasters(await calm.draw('AbovePrompt', { hasSurvey: false, isWorking: false, maxRows: 12, bodyColumns: 100 })).length, 0)
  await calm.advance(2000)
  assert.equal(blits(calm).length, 0)
})

const green = (rec) => ({ ...rec, evidence: { passed: true, at: '2026-10-07T10:00:00Z', checks: {} } })

test('all checks green: full sweeps the Proof grid once; full and calm say it in one ✓ line; off says nothing', async () => {
  const h = await started({}, record({ settings: { motion: 'full' } }))
  await h.press('tab-proof')
  h.project(green(record({ settings: { motion: 'full' } })))
  await h.advance(2000)
  assert.match(text(await band(h)), /✓ All checks pass/)
  const sweep = rasters(await h.render()).find((r) => r.props.key === 'vbw-sweep')
  assert.ok(sweep, 'the sweep is drawn over the proof grid')
  assert.deepEqual([sweep.props.columns, sweep.props.rows], [50, 1])
  await h.advance(1500)
  const b = blits(h, 'vbw-sweep')
  assert.ok(b.length >= 10, 'the sweep crosses: ' + b.length)
  assert.ok(b.every((x) => x.requestId === PANE))
  assert.equal(rasters(await h.render()).length, 0, 'one sweep, then gone')
  await h.advance(60000)
  assert.doesNotMatch(text(await band(h)) || '', /All checks pass/, 'the line leaves after a minute')

  const calm = await started({}, record({ settings: { motion: 'calm' } }))
  await calm.press('tab-proof')
  calm.project(green(record({ settings: { motion: 'calm' } })))
  await calm.advance(2000)
  assert.match(text(await band(calm)), /✓ All checks pass/)
  assert.equal(rasters(await calm.render()).length, 0)

  const off = await started({ files: { [TEST_MODE]: '1' } })
  off.project(green(record()))
  await off.advance(2000)
  assert.doesNotMatch(text(await band(off)) || '', /All checks pass/)
})

test('a milestone shipped opens the pane on VBW Wrapped at every motion level, with the cost of the runs this session saw', async () => {
  const h = await started({ files: { [TEST_MODE]: '1' }, usage: { cost: { usd: 1 } } })
  h.project(record({ lease: lease('build', h.now()) }))
  await h.advance(2000)
  h.setUsage({ cost: { usd: 3.5 } })
  h.project(record())
  await h.advance(2000)
  const opens = h.opens.length
  h.project(record({ shipped: [{ id: 'M9', title: 'Live VBW panel', at: new Date(h.now()).toISOString() }] }))
  await h.advance(2000)
  assert.equal(h.opens.length, opens + 1, 'the pane opens')
  const t = text(await h.render())
  assert.match(t, /VBW Wrapped · M9 Live VBW panel/)
  assert.match(t, /\$2\.50/)
  assert.doesNotMatch(t, /agent/, 'no workflow run seen: agents are not guessed')
  assert.match(t, /Now/, 'the tabs stay')
  await h.press('tab-now')
  assert.doesNotMatch(text(await h.render()), /VBW Wrapped/)
  assert.deepEqual(h.errors, [])
})

// ---- the portrait ----

test('Mission Control wears the VBW portrait (a shipped PNG) where the terminal draws images, alt VBW', async () => {
  const h = await started()
  const img = find(await h.render(), (n) => n.type === 'Image')
  assert.ok(img)
  assert.equal(img.props.alt, 'VBW')
  assert.deepEqual(img.props.source, { file: PLUGIN + '/assets/portrait.png', format: 'png' })
  assert.ok(fs.statSync(PLUGIN + '/assets/portrait.png').size < 32 * 1024, 'a small portrait')
  assert.equal(find(await h.render({ surface: 'desktop' }), (n) => n.type === 'Image'), undefined)
})
