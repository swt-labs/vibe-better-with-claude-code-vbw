// A stand-in for Claude Code's mods API, enough to drive VBW's panel module
// (plugin/hooks/panel.js) in a test: the hooks it registers with `on`, the
// calls it makes on `$`, a virtual file system, a store, a clock the test
// advances, and a record of every call. Nothing here touches the real disk,
// the network or Claude Code (evidence level L1).
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
// Element types as Claude Code hands them out: opaque values that only h() can build.
const ELEMENT = (name) => Object.freeze({ element: name })
const flat = (xs) => xs.flat(Infinity).filter((c) => c !== undefined && c !== null && c !== false)
globalThis.h = (type, props, ...children) => {
  if (!type || typeof type.element !== 'string') throw new Error('h() needs an element from $.ui.resolve(e)')
  const kids = flat(children.length ? children : [props?.children ?? []])
  return { type: type.element, props: { ...(props || {}), children: kids }, children: kids }
}

export const PLUGIN = process.env.VBW_TEST_PLUGIN_ROOT || path.resolve(here, '../../../plugin')
export const ROOT = '/proj'
export const PANE = 'vbw-panel'
export const T0 = 1_800_000_000_000
let instance = 0

export function deepFreeze(x) {
  if (x && typeof x === 'object' && !Object.isFrozen(x)) {
    Object.freeze(x)
    for (const k of Object.keys(x)) deepFreeze(x[k])
  }
  return x
}

// A project record with the fields the panel reads.
export function record(over = {}) {
  return {
    schema: 2,
    project: { name: 'demo' },
    milestone: { id: 'M9', title: 'Live VBW panel', status: 'active' },
    phases: [
      { id: 'P1', title: 'Old work', milestone: 'M1', qa: { result: 'pass' } },
      { id: 'P42', title: 'Panel text', milestone: 'M9', qa: { result: 'pass' } },
      { id: 'P43', title: 'Open and close', milestone: 'M9', qa: { result: 'pass' } },
      { id: 'P44', title: 'Cost', milestone: 'M9' },
      { id: 'P45', title: 'Estimates', milestone: 'M9' },
      { id: 'P46', title: 'Docs', milestone: 'M9' },
    ],
    plans: [
      { id: 'P44.1', phase: 'P44', title: 'Show the cost', status: 'planned' },
      { id: 'P44.2', phase: 'P44', title: 'Show the estimate', status: 'planned' },
    ],
    requirements: [],
    lease: null,
    ...over,
  }
}

export function next(over = {}) {
  return { action: 'build', gate: false, instruction: 'Run the build workflow', detail: {}, ...over }
}

export function lease(kind, startedAtMs, extra = {}) {
  return { run: kind + '-1', kind, started_at: new Date(startedAtMs).toISOString().replace(/\.\d+Z$/, 'Z'), files: null, ...extra }
}

// A matcher holds when each of its keys matches; a nested object matches part of
// a nested value ({ props: { tool: 'Bash' } }), as Claude Code's matchers do.
function matches(matcher, e) {
  if (!matcher) return true
  return Object.entries(matcher).every(([k, v]) =>
    Array.isArray(v) ? v.includes(e?.[k]) : v && typeof v === 'object' ? matches(v, e?.[k]) : e?.[k] === v)
}

// mount(options) loads a fresh copy of the panel module and registers its hooks.
// options: version, root, files (path -> text), store (a Map shared between
// mounts to model a restart), usage, usageError, placed (ui.open answer),
// audioFails, modulePath, env (name -> value), sessionId, process (argv -> result),
// selection ($.ui.selection answer).
export async function mount(options = {}) {
  const o = { version: '2.1.289', root: ROOT, usage: { cost: { usd: 1.4234 } }, placed: true, env: {}, sessionId: 'sess-1', ...options }
  const files = new Map()
  const store = o.store || new Map()
  const invalidations = []
  const handlers = []
  const timers = []
  const calls = []
  const errors = []
  const plays = []
  const opens = []
  let now = T0
  let clockSeq = 0

  const h = { calls, errors, plays, opens, store, files, handlers }
  h.now = () => now

  function put(p, text) {
    files.set(p, { text, mtimeMs: now + ++clockSeq / 1000 })
  }
  for (const [p, text] of Object.entries(o.files || {})) put(p, text)
  h.write = (p, text) => put(p, typeof text === 'string' ? text : JSON.stringify(text))
  h.remove = (p) => files.delete(p)
  h.project = (rec, nxt) => {
    if (rec !== undefined) h.write(o.root + '/.vbw/record.json', rec)
    if (nxt !== undefined) h.write(o.root + '/.vbw/runtime/next.json', nxt)
  }
  h.git = () => {
    if (![...files.keys()].some((p) => p.startsWith(o.root + '/.git/'))) put(o.root + '/.git/HEAD', 'ref: refs/heads/main\n')
  }
  h.setUsage = (u) => void (o.usage = u)
  h.snapshot = () => JSON.stringify([...files.entries()].sort())

  const dirs = () => {
    const s = new Set(o.dirs || [])
    for (const p of files.keys()) {
      let d = path.posix.dirname(p)
      while (d && d !== '/' && !s.has(d)) {
        s.add(d)
        d = path.posix.dirname(d)
      }
    }
    return s
  }

  const impl = {
    'session.version': () => ({ version: o.version, base: o.version }),
    'session.root': () => o.root,
    'session.cwd': () => o.root,
    'session.id': () => o.sessionId,
    'env.get': (name) => o.env[name],
    'fs.list': (p) => {
      const ds = dirs()
      if (!ds.has(p)) throw new Error('ENOENT ' + p)
      const out = []
      for (const [fp, f] of files) if (path.posix.dirname(fp) === p) out.push({ name: path.posix.basename(fp), kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false })
      for (const d of ds) if (path.posix.dirname(d) === p) out.push({ name: path.posix.basename(d), kind: 'dir', size: 0, mtimeMs: 0, isLink: false })
      return out
    },
    'prompt.fill': (a) => ({ isFilled: true, text: a.text }),
    'prompt.suggest': () => ({ isShown: true }),
    'process.run': (argv) => (typeof o.process === 'function' ? o.process(argv) : { exitCode: 0, stdout: 'added T1: ' + argv[argv.length - 1] + '\n', stderr: '' }),
    'ui.selection': () => o.selection,
    'session.usage': () => {
      if (o.usageError) throw new Error('no ledger')
      return o.usage
    },
    'fs.read': (p) => {
      const f = files.get(p)
      if (!f) throw new Error('ENOENT ' + p)
      return f.text
    },
    'fs.exists': (p) => files.has(p) || dirs().has(p),
    'fs.stat': (p) => {
      const f = files.get(p)
      if (f) return { kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false }
      if (dirs().has(p)) return { kind: 'dir', size: 0, mtimeMs: 0, isLink: false }
      throw new Error('ENOENT ' + p)
    },
    'store.get': (k) => (store.has(k) ? store.get(k) : undefined),
    'store.set': (k, v) => void store.set(k, v),
    'store.delete': (k) => void store.delete(k),
    'clock.now': () => now,
    'clock.every': (ms, fn) => {
      const t = { ms, fn, at: now + ms, dead: false, cancel() { t.dead = true } }
      timers.push(t)
      return t
    },
    'clock.after': (ms, fn) => {
      const t = { ms, fn, at: now + ms, dead: false, once: true, cancel() { t.dead = true } }
      timers.push(t)
      return t
    },
    'ui.open': (a) => {
      opens.push(a)
      return typeof o.placed === 'function' ? o.placed(a) : o.placed ? { isPlaced: true } : { isPlaced: false, reason: 'the terminal is too narrow' }
    },
    'ui.close': () => undefined,
    // As in Claude Code 2.1.289: a redraw names what to redraw ('ui.render');
    // without it the call is dropped.
    'ui.invalidate': (what) => {
      if (what !== 'ui.render') throw new Error("$.ui.invalidate needs the event to redraw: 'ui.render'")
      invalidations.push(what)
    },
    'ui.toast': () => undefined,
    'ui.log': () => undefined,
    'ui.status': () => undefined,
    // As in Claude Code: resolve takes the render event (its surface), and the
    // elements are types that only h() turns into a tree; calling one throws.
    'ui.resolve': (e) => {
      if (!e || typeof e.surface !== 'string') throw new Error('$.ui.resolve(e) needs the render event')
      return { Box: ELEMENT('Box'), Text: ELEMENT('Text'), Button: ELEMENT('Button') }
    },
    'command.register': () => undefined,
    'audio.play': (clip) => {
      if (o.audioFails) throw new Error('no player')
      plays.push(clip)
    },
  }

  // Timers and redraw requests answer at once, as in Claude Code; every other call is async.
  const SYNC = new Set(['clock.every', 'clock.after', 'ui.invalidate', 'ui.resolve'])
  const ns = (name) =>
    new Proxy({}, {
      get: (_, method) => (...args) => {
        const key = name + '.' + String(method)
        calls.push({ name: key, args })
        if (!impl[key]) return Promise.reject(new Error('no implementation for ' + key))
        if (SYNC.has(key)) return impl[key](...args)
        return (async () => impl[key](...args))()
      },
    })
  const cache = {}
  // $.plugin is plain data in Claude Code: the plugin's name and its directory.
  const plugin = Object.freeze({ name: 'vbw', root: PLUGIN })
  const $ = new Proxy({}, { get: (_, n) => (n === 'plugin' ? plugin : (cache[n] ??= ns(String(n)))) })
  h.$ = $

  const on = (event, a, b) => {
    const matcher = typeof a === 'function' ? undefined : a
    const fn = typeof a === 'function' ? a : b
    // In Claude Code a hook without a matcher runs for every such event (every
    // drawing, every command), each one a hop to the plugin's worker.
    if (event === 'ui.render' && !(matcher && matcher.component && (matcher.component !== 'Pane' || matcher.requestId))) {
      throw new Error('a ui.render hook must match { component } (a Pane also its requestId): without it, it runs for every drawing in Claude Code')
    }
    if ((event === 'tool.call' || event === 'turn.step') && !(matcher && matcher.tool)) {
      throw new Error('a ' + event + ' hook must match { tool }: without it, it runs for every call of every agent (decision P2)')
    }
    if (event === 'command.run' && !(matcher && matcher.command)) {
      throw new Error('a command.run hook must match { command }: without it, it runs for every command')
    }
    handlers.push({ event, matcher, fn })
    return { catch() {} }
  }

  const entry = path.join(o.modulePath || path.join(PLUGIN, 'hooks/panel.js'))
  const mod = await import(pathToFileURL(entry).href + '?i=' + ++instance)
  mod.register(on, {})

  h.count = (name) => calls.filter((c) => c.name === name).length
  h.callsOf = (name) => calls.filter((c) => c.name === name).map((c) => c.args)
  h.names = () => [...new Set(calls.map((c) => c.name))]
  h.invalidations = () => invalidations.length

  // Fire an event through the registered hooks, in order. `terminal` answers when
  // every hook passed the event on (default: the event itself).
  h.fire = async (event, e, terminal) => {
    const chain = handlers.filter((x) => x.event === event && matches(x.matcher, e))
    const run = async (i, ev) => {
      if (i >= chain.length) return terminal ? terminal(ev) : ev
      const nextFn = (e2) => run(i + 1, e2)
      nextFn.signal = new AbortController().signal
      try {
        return await chain[i].fn($, ev, nextFn)
      } catch (err) {
        errors.push({ event, error: String(err?.stack || err) })
        return run(i + 1, ev)
      }
    }
    return run(0, e)
  }
  h.start = () => h.fire('session.start', { surface: 'terminal', isInteractive: true, cwd: o.root })
  h.cmd = (command, args = '') => h.fire('command.run', { command, args })
  h.render = (extra = {}) =>
    h.fire('ui.render', {
      plugin: 'vbw', component: 'Pane', requestId: PANE, surface: 'terminal', viewport: { columns: 160, rows: 40 },
      props: { title: 'VBW', isFocused: false, bodyColumns: 50, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} },
      ...extra,
    }, () => ({ type: 'engine', ref: 'default' }))
  h.settle = async () => {
    for (let i = 0; i < 20; i++) await Promise.resolve()
    await new Promise((r) => setImmediate(r))
  }
  h.advance = async (ms) => {
    const target = now + ms
    for (;;) {
      const live = timers.filter((t) => !t.dead && t.at <= target)
      if (!live.length) break
      const t = live.reduce((a, b) => (a.at <= b.at ? a : b))
      now = t.at
      if (t.once) t.dead = true
      else t.at += t.ms
      try {
        await t.fn()
      } catch (err) {
        errors.push({ event: 'timer', error: String(err?.stack || err) })
      }
      await h.settle()
    }
    now = target
  }
  // Advance in 1 s steps until `ok()` holds; returns the virtual ms it took (or -1).
  h.until = async (ok, limitMs = 30000) => {
    for (let t = 0; t <= limitMs; t += 1000) {
      if (await ok()) return t
      await h.advance(1000)
    }
    return -1
  }
  // Any other render site: draw(component, props, extra); the engine's own drawing is { type: 'engine', ref: component }.
  h.draw = (component, props = {}, extra = {}) =>
    h.fire('ui.render', { plugin: 'vbw', component, requestId: component + '-1', surface: 'terminal', viewport: { columns: 120, rows: 40 }, props, ...extra },
      (ev) => ({ type: 'engine', ref: component, props: ev.props }))
  h.texts = async () => collect(await h.render())
  h.text = async () => (await h.texts()).join('\n')
  h.press = async (key) => {
    const b = find(await h.render(), (n) => n.type === 'Button' && n.props.key === key)
    if (!b) throw new Error('no button ' + key)
    await b.props.onPress({ surface: 'terminal' })
    await h.settle()
  }
  h.tree = () => h.render()
  return h
}

export function walk(node, fn) {
  if (node === null || typeof node !== 'object') return
  fn(node)
  for (const c of node.children || []) walk(c, fn)
}
export function find(tree, pred) {
  let hit
  walk(tree, (n) => {
    if (!hit && pred(n)) hit = n
  })
  return hit
}
export function collect(tree) {
  const out = []
  walk(tree, (n) => {
    if (n.type === 'Text') out.push(n.children.filter((c) => typeof c === 'string').join(''))
    if (n.type === 'Button' && n.props.label) out.push(String(n.props.label))
  })
  return out
}
// Text elements drawn dim (the technical term in small text, D107).
export function dimTexts(tree) {
  const out = []
  walk(tree, (n) => {
    if (n.type === 'Text' && n.props.dimColor) out.push(n.children.filter((c) => typeof c === 'string').join(''))
  })
  return out
}

// What the tests allow the panel to call: it reads, draws, keeps a preference and plays a sound.
export const ALLOWED = new Set([
  'session.version', 'session.root', 'session.cwd', 'session.usage',
  'fs.read', 'fs.stat', 'fs.exists',
  'store.get', 'store.set',
  'clock.now', 'clock.every', 'clock.after',
  'ui.open', 'ui.close', 'ui.invalidate', 'ui.resolve',
  'command.register', 'audio.play',
  // The run feed lists the session's workflow folder and finds it by the session id
  // and the Claude config folder (HOME, CLAUDE_CONFIG_DIR: names, never values elsewhere).
  'fs.list', 'session.id', 'env.get',
  // Buttons fill the prompt and the approve gate suggests /vbw:approve; never a submit (Q1).
  'prompt.fill', 'prompt.suggest',
])
