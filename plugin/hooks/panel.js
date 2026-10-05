// The VBW panel (R51, R53, R55): a Claude Code mod that draws the project's state
// in a pane. It only reads (the record and the last `vbw next`), never writes,
// and does nothing at all where it cannot run: Claude Code older than 2.1.287, or
// a folder that is not a VBW 2 project. Every hook is wrapped: an error here must
// never reach the user's session.
import { panelView, supports } from './panel-view.js'

const PANE = 'vbw-panel'
const TICK_MS = 2000
// The user's choice lives in Claude Code's per-user store, never in the project.
const CLOSED_KEY = 'vbw-panel.closed'
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
  return { live: false, timer: null, busy: false, question: null, record: null, next: null, shown: '', seen: {} }
}

const view = (st, now) => panelView({ record: st.record, next: st.next, question: st.question, now })

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

async function redrawIfChanged($, st) {
  const sig = JSON.stringify(view(st, await $.clock.now()))
  if (sig === st.shown) return
  st.shown = sig
  $.ui.invalidate()
}

async function tick($, st, root) {
  if (st.busy) return
  st.busy = true
  try {
    await refresh($, st, root + '/.vbw/record.json', 'record')
    await refresh($, st, root + '/.vbw/runtime/next.json', 'next')
    await redrawIfChanged($, st)
  } catch {
    // keep the last good state
  } finally {
    st.busy = false
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
      await refresh($, st, root + '/.vbw/record.json', 'record')
      await refresh($, st, root + '/.vbw/runtime/next.json', 'next')
      st.shown = JSON.stringify(view(st, await $.clock.now()))
      if (st.timer && st.timer.cancel) st.timer.cancel()
      st.timer = $.clock.every(TICK_MS, () => tick($, st, root))
      $.command.register({ name: 'vbw-panel', description: 'Open the VBW panel', immediate: true })
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
      const { Box, Text } = await $.ui.resolve()
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
      return Box({ flexDirection: 'column', children: rows })
    } catch {
      return next(e)
    }
  })
}
