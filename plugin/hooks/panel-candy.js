// Delight that respects the user (mods_4_vbw.md §3.1 crew theme, §3.7): the
// motion setting, the crew's pixel sprites, the confetti burst, the VBW
// Wrapped card at ship, and which celebration a record change earns. Pure:
// values in, values or trees out; no `$`, never throws.

const DEFAULT = 0x01000000 // the terminal's own colour, in a Raster cell
export const ROLE_COLORS = {
  architect: 0xd75fd7, lead: 0x5f87ff, dev: 0x5fd75f, qa: 0xffd75f,
  scout: 0x5fd7ff, debugger: 0xff5f5f, docs: 0xff87d7, agent: 0xe4e4e4,
}
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const arr = (x) => (Array.isArray(x) ? x : [])

// motion: 'full' (sprites, celebrations), 'calm' (dots, spinners, no confetti)
// or 'off' (static text). Test mode is always off (R64); the user's setting
// wins; else users new to code get full and everyone else calm (R54).
const MOTIONS = ['full', 'calm', 'off']
const NEW_TO_CODE = ['never', 'small scripts or no-code']
export function motionOf(input) {
  const { setting, level, testMode } = isObj(input) ? input : {}
  if (testMode) return 'off'
  if (MOTIONS.includes(setting)) return setting
  return NEW_TO_CODE.includes(level) ? 'full' : 'calm'
}

// Sprites: 5 columns by 3 rows. Columns 0-2 are the figure, in the role's
// colour; columns 3-4 are the prop that tells the pose, in its own colour.
// The pose is the state: no frame is decoration only.
const SPRITES = {
  reading: { prop: 0xe4e4e4, frames: [[' ▄   ', '▐█▌▐▀', '▐ ▌  '], [' ▄   ', '▐█▌▐▄', '▐ ▌  ']] },
  editing: { prop: 0xaf875f, frames: [[' ▄  ▐', '▐█▌▀▌', '▐ ▌ ▀'], [' ▄   ', '▐█▌▄▄', '▐ ▌▐█']] },
  shell: { prop: 0x808080, frames: [[' ▄   ', '▐█▌▀ ', '▌ ▐ ▄'], [' ▄   ', '▐█▌ ▀', ' █ ▄ ']] },
  streaming: { prop: 0xe4e4e4, frames: [[' ▄ ▄▀', '▐█▌  ', '▐ ▌  '], [' ▄ ▀▄', '▐█▌▄ ', '▐ ▌  '], [' ▄ ██', '▐█▌▀ ', '▐ ▌  ']] },
  done: { prop: 0x5fd75f, frames: [[' ▄  ✓', '▐█▌  ', '▐ ▌  '], ['▄▄▄✓ ', ' █   ', '▐ ▌  ']] },
  quiet: { prop: 0xffaf00, frames: [[' ▄  z', '▐█▌  ', '▐ ▌  '], [' ▄ Z ', '▐█▌ z', '▐ ▌  ']] },
  failed: { prop: 0xff5f5f, frames: [[' ▄  ✗', '▐█▌  ', '▐ ▌  '], [' ▄ ✗ ', '▐█▌  ', '▐ ▌  ']] },
}
export const POSES = Object.keys(SPRITES)

// spriteFrame({ role, pose, frame }) -> { cols, rows, cells: [{ ch, fg, bg }] } | null
export function spriteFrame(input) {
  const { role, pose, frame } = isObj(input) ? input : {}
  const s = SPRITES[pose]
  if (!s) return null
  const n = s.frames.length
  const i = Number.isFinite(frame) ? ((Math.trunc(frame) % n) + n) % n : 0
  const body = ROLE_COLORS[role] ?? ROLE_COLORS.agent
  const cells = []
  for (const line of s.frames[i]) {
    ;[...line].forEach((ch, x) => cells.push({ ch, fg: ch === ' ' ? DEFAULT : x < 3 ? body : s.prop, bg: DEFAULT }))
  }
  return { cols: 5, rows: 3, cells }
}

// poseOf(activity, state): the feed's agent state and activity as a pose.
export function poseOf(activity, state) {
  if (state === 'done' || state === 'quiet' || state === 'failed') return state
  if (state !== 'working') return 'quiet'
  if (!isObj(activity) || activity.kind === 'text') return 'streaming'
  const t = String(activity.text || '').toLowerCase()
  if (/^(read|search|list|grep|find|look|fetch|glob)/.test(t)) return 'reading'
  if (/^(edit|writ|creat|updat|delet|mov)/.test(t)) return 'editing'
  return 'shell'
}

// encodeCells(grid): a Raster's `cells`: padded base64 of little-endian u32
// triplets [codePoint, fg, bg], row-major. Written out, as the mod's runtime
// has neither Buffer nor a guaranteed btoa.
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
export function encodeCells(grid) {
  if (!isObj(grid) || !Array.isArray(grid.cells)) return ''
  const bytes = []
  const u32 = (v) => bytes.push(v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255)
  for (const c of grid.cells) {
    u32(String(c?.ch || ' ').codePointAt(0))
    u32(Number.isFinite(c?.fg) ? c.fg : DEFAULT)
    u32(Number.isFinite(c?.bg) ? c.bg : DEFAULT)
  }
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0)
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63]
    out += i + 1 < bytes.length ? B64[(n >> 6) & 63] : '='
    out += i + 2 < bytes.length ? B64[n & 63] : '='
  }
  return out
}

// confettiFrames({ cols, rows, n, seed }): n frames (default 15: 1.5 s at
// 10 fps) of falling pieces in the crew's colours, the same for a seed, ending
// clear. Sized to a Raster's limits (512 by 256).
const PIECES = ['▀', '▄', '▌', '▐', '█', '•']
function rng(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
export function confettiFrames(input) {
  const { cols, rows, n = 15, seed = 1 } = isObj(input) ? input : {}
  if (!Number.isInteger(cols) || !Number.isInteger(rows) || !Number.isInteger(n) || cols < 1 || rows < 1 || n < 1) return []
  const w = Math.min(cols, 512)
  const ht = Math.min(rows, 256)
  const rand = rng(Number.isFinite(seed) ? seed : 1)
  const colors = Object.values(ROLE_COLORS)
  const count = Math.max(3, Math.round((w * ht) / 6))
  // Each piece starts above or in the box and falls fast enough to leave it by the last frame.
  const last = Math.max(1, n - 1)
  const pieces = Array.from({ length: count }, () => {
    const y0 = -rand() * ht
    return {
      x: Math.floor(rand() * w), drift: rand() * 2 - 1, y0,
      vy: (ht - y0 + 0.01) / last * (1 + rand()),
      ch: PIECES[Math.floor(rand() * PIECES.length)], fg: colors[Math.floor(rand() * colors.length)],
    }
  })
  const frames = []
  for (let f = 0; f < n; f++) {
    const cells = Array.from({ length: w * ht }, () => ({ ch: ' ', fg: DEFAULT, bg: DEFAULT }))
    if (f < last || n === 1) {
      for (const p of pieces) {
        const y = Math.floor(p.y0 + p.vy * f)
        const x = Math.round(p.x + p.drift * f)
        if (y >= 0 && y < ht && x >= 0 && x < w) cells[y * w + x] = { ch: p.ch, fg: p.fg, bg: DEFAULT }
      }
    }
    frames.push({ cols: w, rows: ht, cells })
  }
  return frames
}

// The VBW Wrapped card at ship: what the milestone took. A milestone's window
// runs from the ship before it to its own ship; steps and runs outside it are
// other milestones'. What VBW cannot know is null, never a guess.
const ms = (s) => (typeof s === 'string' ? Date.parse(s) : NaN)
export function wrappedModel(input) {
  const { record, runs, steps, cost } = isObj(input) ? input : {}
  if (!isObj(record)) return null
  const ships = arr(record.shipped).filter((s) => isObj(s) && typeof s.id === 'string')
  const ship = ships[ships.length - 1]
  if (!ship) return null
  const end = ms(ship.at)
  const start = ships.length > 1 ? ms(ships[ships.length - 2].at) : -Infinity
  const within = (t) => Number.isFinite(t) && t >= start && (!Number.isFinite(end) || t <= end)

  const reqs = arr(record.requirements).filter((r) => isObj(r) && r.milestone === ship.id)
  const ids = new Set(reqs.map((r) => r.id))
  const checks = arr(record.checks).filter((c) => isObj(c) && ids.has(c.req))
  const results = isObj(record.evidence) && isObj(record.evidence.checks) ? record.evidence.checks : {}
  const fixRounds = arr(record.phases)
    .filter((p) => isObj(p) && p.milestone === ship.id)
    .reduce((n, p) => n + (Number.isFinite(p.outcome?.fix_rounds) ? p.outcome.fix_rounds : 0), 0)

  const ourRuns = arr(runs).filter((r) => isObj(r) && within(r.startedAt))
  const runCosts = ourRuns.filter((r) => Number.isFinite(r.cost))
  const ourSteps = arr(steps).filter((s) => isObj(s) && Number.isFinite(s.seconds) && s.seconds >= 0 && within(ms(s.started_at)) && within(ms(s.ended_at)))
  const brief = (s) => (s ? { kind: String(s.kind), run: String(s.run), seconds: s.seconds } : null)
  const byTime = [...ourSteps].sort((a, b) => a.seconds - b.seconds)

  return {
    milestone: { id: ship.id, title: typeof ship.title === 'string' ? ship.title : record.milestone?.id === ship.id ? String(record.milestone.title || '') : '' },
    requirements: { proven: reqs.filter((r) => r.status === 'proven').length, total: reqs.length },
    checks: { passing: checks.filter((c) => results[c.id]?.status === 'pass').length, total: checks.length },
    agents: ourRuns.length ? ourRuns.reduce((n, r) => n + arr(r.agents).length, 0) : null,
    fixRounds,
    seconds: ourSteps.length ? ourSteps.reduce((n, s) => n + s.seconds, 0) : null,
    cost: Number.isFinite(cost) ? cost : runCosts.length ? Math.round(runCosts.reduce((n, r) => n + r.cost, 0) * 100) / 100 : null,
    fastest: brief(byTime[0]),
    slowest: brief(byTime[byTime.length - 1]),
  }
}

const two = (n) => String(n).padStart(2, '0')
const duration = (s) => {
  const t = Math.round(s)
  return t >= 3600 ? `${Math.floor(t / 3600)}h${two(Math.floor((t % 3600) / 60))}m` : `${Math.floor(t / 60)}m${two(t % 60)}s`
}
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`

export function renderWrapped(ui, model) {
  if (!isObj(ui) || !isObj(model)) return null
  const { Box, Text } = ui
  const m = model
  const lines = [
    `${m.requirements.proven} of ${m.requirements.total} requirements proven`,
    `${m.checks.passing} of ${m.checks.total} checks pass`,
    [m.agents === null ? null : plural(m.agents, 'agent'), plural(m.fixRounds, 'fix round')].filter(Boolean).join(' · '),
    [m.seconds === null ? 'time unknown' : duration(m.seconds), m.cost === null ? 'cost unknown' : '$' + m.cost.toFixed(2)].join(' · '),
  ]
  if (m.fastest) lines.push(`fastest: ${m.fastest.kind} ${duration(m.fastest.seconds)} · slowest: ${m.slowest.kind} ${duration(m.slowest.seconds)}`)
  return h(Box, { flexDirection: 'column', borderStyle: 'round', borderColor: 'green', paddingX: 1 },
    h(Text, { bold: true, color: 'green' }, `VBW Wrapped · ${m.milestone.id}${m.milestone.title ? ' ' + m.milestone.title : ''}`),
    lines.map((l, i) => h(Text, { key: 'w' + i }, l)))
}

// celebration({ before, after }): what a change between two record snapshots
// earns: a ship, then a phase passing QA, then a fresh all-green proof. The
// first snapshot (no before) earns nothing: it is not news.
const qaKey = (p) => (p?.qa?.result === 'pass' ? `${p.id}@${p.qa.at}` : null)
export function celebration(input) {
  const { before, after } = isObj(input) ? input : {}
  if (!isObj(before) || !isObj(after)) return null
  const shipKey = (r) => {
    const s = arr(r.shipped)
    return s.length ? `${s.length}:${s[s.length - 1]?.id}@${s[s.length - 1]?.at}` : ''
  }
  if (arr(after.shipped).length && shipKey(after) !== shipKey(before)) return 'shipped'
  const passed = new Set(arr(before.phases).map(qaKey).filter(Boolean))
  if (arr(after.phases).some((p) => qaKey(p) && !passed.has(qaKey(p)))) return 'qa-pass'
  const b = isObj(before.evidence) ? before.evidence : {}
  const a = isObj(after.evidence) ? after.evidence : {}
  if (a.passed === true && !(b.passed === true && b.at === a.at)) return 'all-green'
  return null
}
