// The VBW panel (R51, R53, R55): a Claude Code mod that draws the project's state
// in a pane. It only reads (the record and the last `vbw next`), never writes,
// and does nothing at all where it cannot run: Claude Code older than 2.1.287, or
// a folder that is not a VBW 2 project. Every hook is wrapped: an error here must
// never reach the user's session.
import { panelView, supports } from './panel-view.js'
import { SOUNDS } from './panel-sounds.js'

const PANE = 'vbw-panel'
const TICK_MS = 2000
// The user's choice lives in Claude Code's per-user store, never in the project.
const CLOSED_KEY = 'vbw-panel.closed'
const SOUND_KEY = 'vbw-panel.sound'
// One of the plugin's shipped sounds (assets/audio/<character>/), picked at random
// for each request for the user; with none shipped, the panel is silent.
const pick = () => (SOUNDS.length ? { asset: SOUNDS[Math.floor(Math.random() * SOUNDS.length)] } : null)
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)

// Parse a project file; null when it is not a JSON object (half written, invalid).
function parse(text) {
  try {
    const v = JSON.parse(text)
    return isObj(v) ? v : null
  } catch {
    return null
  }
}

// What the panel knows: the last good state of both files, what is drawn, what is asked.
function fresh() {
  return { live: false, timer: null, busy: false, question: null, sound: true, alerted: null, record: null, next: null, history: null, cost: null, stepsPath: null, steps: null, shown: '', seen: {} }
}

const view = (st, now) => panelView({ record: st.record, next: st.next, question: st.question, now, cost: st.cost, steps: st.steps })

// Read a file only when its size or time changed; keep the old state when it cannot be used.
async function refresh($, st, path, key) {
  let sig
  try {
    const f = await $.fs.stat(path)
    sig = f.size + ':' + f.mtimeMs
  } catch {
    return
  }
  if (st.seen[path] === sig) return
  st.seen[path] = sig
  let text
  try {
    text = await $.fs.read(path)
  } catch {
    return
  }
  const v = parse(text)
  if (v) st[key] = v
}

// Where this clone keeps steps.json: its git directory, also from a linked worktree
// (whose .git file names a directory with a `commondir` pointer). Null when unknown.
const norm = (p) => {
  const out = []
  for (const s of p.split('/')) {
    if (s === '..') out.pop()
    else if (s !== '' && s !== '.') out.push(s)
  }
  return '/' + out.join('/')
}
const place = (base, p) => norm(p.startsWith('/') ? p : base + '/' + p)

async function stepsPath($, root) {
  try {
    const dot = root + '/.git'
    if ((await $.fs.stat(dot)).kind === 'dir') return dot + '/vbw/steps.json'
    const m = /^gitdir:\s*(.+?)\s*$/m.exec(await $.fs.read(dot))
    if (!m) return null
    const dir = place(root, m[1])
    let common = dir
    try {
      const c = (await $.fs.read(dir + '/commondir')).trim()
      if (c) common = place(dir, c)
    } catch {
      // not a linked worktree: this is the git directory
    }
    return common + '/vbw/steps.json'
  } catch {
    return null
  }
}

// The session cost so far: a number, or null when it cannot be read (never a guess).
async function readCost($, st) {
  try {
    const u = await $.session.usage()
    const usd = isObj(u) && isObj(u.cost) ? u.cost.usd : null
    st.cost = typeof usd === 'number' && Number.isFinite(usd) ? usd : null
  } catch {
    st.cost = null
  }
}

// Everything the panel shows, read afresh: each file only when it changed, never written.
async function gather($, st, root) {
  await refresh($, st, root + '/.vbw/record.json', 'record')
  await refresh($, st, root + '/.vbw/runtime/next.json', 'next')
  if (st.stepsPath) {
    await refresh($, st, st.stepsPath, 'history')
    st.steps = isObj(st.history) && Array.isArray(st.history.steps) ? st.history.steps : null
  }
  await readCost($, st)
}

// Play the sound once when a need appears; the same need never plays it again.
// A missing file or player is silent.
async function alert($, st, need) {
  const key = need ? need.key : null
  if (key === st.alerted) return
  st.alerted = key
  const clip = key && st.sound ? pick() : null
  if (!clip) return
  try {
    await $.audio.play(clip)
  } catch {
    // no file or no player: nothing to say
  }
}

async function redrawIfChanged($, st) {
  const v = view(st, await $.clock.now())
  await alert($, st, v.need)
  const sig = JSON.stringify([v, st.sound])
  if (sig === st.shown) return
  st.shown = sig
  $.ui.invalidate()
}

async function tick($, st, root) {
  if (st.busy) return
  st.busy = true
  try {
    await gather($, st, root)
    await redrawIfChanged($, st)
  } catch {
    // keep the last good state
  } finally {
    st.busy = false
  }
}

// Switch the sound and keep the choice in the user's store; the panel redraws.
async function setSound($, st, on) {
  st.sound = on
  try {
    await $.store.set(SOUND_KEY, on)
  } catch {
    // the choice holds for this session
  }
  try {
    await redrawIfChanged($, st)
  } catch {
    // the next tick draws it
  }
}

async function open($, extra) {
  try {
    await $.ui.open({ id: PANE, title: 'VBW', placement: 'dock', ...extra })
  } catch {
    // where Claude Code keeps the pane closed, it stays closed
  }
}

export function register(on) {
  const st = fresh()

  on('session.start', async ($, e, next) => {
    const out = await next(e)
    try {
      if (st.live) return out
      const ver = await $.session.version()
      if (!supports(isObj(ver) ? ver.version : ver)) return out
      const root = await $.session.root()
      if (typeof root !== 'string' || !(await $.fs.exists(root + '/.vbw/record.json'))) return out
      st.live = true
      st.stepsPath = await stepsPath($, root)
      await gather($, st, root)
      st.sound = (await $.store.get(SOUND_KEY)) !== false
      const v0 = view(st, await $.clock.now())
      st.alerted = v0.need ? v0.need.key : null // a need already standing at start is not announced
      st.shown = JSON.stringify([v0, st.sound])
      if (st.timer && st.timer.cancel) st.timer.cancel()
      st.timer = $.clock.every(TICK_MS, () => tick($, st, root))
      $.command.register({ name: 'vbw-panel', description: 'Open the VBW panel', immediate: true })
      $.command.register({ name: 'vbw-sound', description: "Turn the 'needs you' sound on or off", immediate: true })
      if ((await $.store.get(CLOSED_KEY)) !== true) await open($)
    } catch {
      // the panel stays out of the way
    }
    return out
  })

  on('command.run', async ($, e, next) => {
    if (st.live && isObj(e) && e.command === 'vbw-panel') {
      try {
        await $.store.set(CLOSED_KEY, false)
      } catch {
        // the panel still opens
      }
      await open($, { focus: true })
      return { text: 'The VBW panel is open.' }
    }
    if (st.live && isObj(e) && e.command === 'vbw-sound') {
      const word = String(e.args ?? '').trim().toLowerCase()
      if (word === '' || word === 'on' || word === 'off') await setSound($, st, word === '' ? !st.sound : word === 'on')
      return { text: "The 'needs you' sound is " + (st.sound ? 'on' : 'off') + '.' }
    }
    return next(e)
  })

  // Remember a close made by the user only; every close is passed on.
  on('ui.close', async ($, e, next) => {
    if (st.live && isObj(e) && e.id === PANE && isObj(e.origin) && e.origin.kind === 'person') {
      try {
        await $.store.set(CLOSED_KEY, true)
      } catch {
        // the close still goes through
      }
    }
    return next(e)
  })

  // A question to the user is a need while it is open.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (!st.live) return next(e)
    st.question = { id: String(Date.now()) + Math.random() }
    try {
      await redrawIfChanged($, st)
    } catch {
      // the next tick draws it
    }
    try {
      return await next(e)
    } finally {
      st.question = null
      try {
        await redrawIfChanged($, st)
      } catch {
        // nothing to redraw
      }
    }
  })

  on('ui.render', async ($, e, next) => {
    if (!st.live || !isObj(e) || e.requestId !== PANE) return next(e)
    try {
      const { Box, Text, Button } = await $.ui.resolve()
      const v = view(st, await $.clock.now())
      const rows = v.rows.map((r) =>
        Box({
          key: r.id,
          flexDirection: 'column',
          marginBottom: 1,
          children: [
            Text({ children: [String(r.text)], color: r.id === 'need' && v.need ? 'yellow' : undefined }),
            Text({ children: [String(r.term)], dimColor: true }),
          ],
        }))
      rows.push(Box({
        key: 'sound',
        flexDirection: 'row',
        children: [
          Text({ children: ['Sound is ' + (st.sound ? 'on' : 'off') + '. '] }),
          Button({ key: 'sound-toggle', label: st.sound ? 'Turn off' : 'Turn on', onPress: () => setSound($, st, !st.sound) }),
        ],
      }))
      return Box({ flexDirection: 'column', children: rows })
    } catch {
      return next(e)
    }
  })
}
