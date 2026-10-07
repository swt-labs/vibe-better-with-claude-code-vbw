// A stand-in for the part of Claude Code's mods API that plugin/hooks/panel-feed.js
// uses: $.fs.read/list/stat/exists over a virtual file system, and $.clock.now.
// It counts every read by path, so a test can prove what was read and what was not.
// Nothing here touches the real disk (evidence level L1).
import path from 'node:path'

export const SESSION = '/home/u/.claude/projects/-proj/0000-session'
export const T0 = 1_791_328_900_000
const LIMIT = 4 * 1024 * 1024

// Real-shaped transcript lines (trimmed copies of Claude Code 2.1.29x agent transcripts).
export const iso = (ms) => new Date(ms).toISOString()
export const line = {
  user: (at, text = 'Execute VBW plan P53.2.') => ({ type: 'user', timestamp: iso(at), message: { role: 'user', content: text } }),
  result: (at) => ({ type: 'user', timestamp: iso(at), message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't1', content: 'ok' }] } }),
  attachment: (at) => ({ type: 'attachment', timestamp: iso(at), attachment: {} }),
  tool: (at, name, input, usage) => ({ type: 'assistant', timestamp: iso(at), message: { role: 'assistant', content: [{ type: 'tool_use', id: 't1', name, input }], ...(usage ? { usage } : {}) } }),
  text: (at, text, usage) => ({ type: 'assistant', timestamp: iso(at), message: { role: 'assistant', content: [{ type: 'text', text }], ...(usage ? { usage } : {}) } }),
  thinking: (at, usage) => ({ type: 'assistant', timestamp: iso(at), message: { role: 'assistant', content: [{ type: 'thinking', thinking: '', signature: 'x' }], ...(usage ? { usage } : {}) } }),
}
export const usage = (input, read, create) => ({ input_tokens: input, cache_read_input_tokens: read, cache_creation_input_tokens: create, output_tokens: 99, service_tier: 'standard' })
export const jsonl = (rows) => rows.map((r) => (typeof r === 'string' ? r : JSON.stringify(r))).join('\n') + '\n'

export function fakeFs(options = {}) {
  const files = new Map()
  const reads = new Map()
  const calls = []
  let now = options.now ?? T0
  let seq = 0
  const put = (p, text, mtimeMs) => files.set(p, { text: typeof text === 'string' ? text : JSON.stringify(text), mtimeMs: mtimeMs ?? now + ++seq })
  for (const [p, t] of Object.entries(options.files || {})) put(p, t)
  const dirs = () => {
    const s = new Set()
    for (const p of files.keys()) for (let d = path.posix.dirname(p); d !== '/' && !s.has(d); d = path.posix.dirname(d)) s.add(d)
    return s
  }
  const size = (f) => (f.size ?? Buffer.byteLength(f.text))
  const $ = {
    fs: {
      read: async (p) => {
        calls.push(['read', p])
        reads.set(p, (reads.get(p) || 0) + 1)
        const f = files.get(p)
        if (!f) throw new Error('ENOENT ' + p)
        if (size(f) > LIMIT) throw new Error('EFBIG ' + p)
        return f.text
      },
      list: async (p) => {
        calls.push(['list', p])
        if (options.listFails) throw new Error('EIO')
        const ds = dirs()
        if (!ds.has(p)) throw new Error('ENOENT ' + p)
        const out = new Map()
        for (const [fp, f] of files) if (path.posix.dirname(fp) === p) out.set(path.posix.basename(fp), { name: path.posix.basename(fp), kind: 'file', size: size(f), mtimeMs: f.mtimeMs, isLink: false })
        for (const d of ds) if (path.posix.dirname(d) === p) out.set(path.posix.basename(d), { name: path.posix.basename(d), kind: 'dir', size: 0, mtimeMs: 0, isLink: false })
        return [...out.values()]
      },
      stat: async (p) => {
        calls.push(['stat', p])
        const f = files.get(p)
        if (f) return { kind: 'file', size: size(f), mtimeMs: f.mtimeMs, isLink: false }
        if (dirs().has(p)) {
          const inside = [...files.entries()].filter(([fp]) => fp.startsWith(p + '/')).map(([, x]) => x.mtimeMs)
          return { kind: 'dir', size: 0, mtimeMs: inside.length ? Math.max(...inside) : 0, isLink: false }
        }
        throw new Error('ENOENT ' + p)
      },
      exists: async (p) => files.has(p) || dirs().has(p),
    },
    clock: { now: async () => now },
  }
  return {
    $,
    files,
    calls,
    reads: (p) => reads.get(p) || 0,
    readCount: () => calls.filter((c) => c[0] === 'read').length,
    write: (p, text, mtimeMs) => put(p, text, mtimeMs),
    // A file too big for one read, as Claude Code refuses it (over 4 MiB).
    huge: (p) => files.set(p, { text: '', size: LIMIT + 1, mtimeMs: now + ++seq }),
    remove: (p) => files.delete(p),
    advance: (ms) => void (now += ms),
    now: () => now,
  }
}
