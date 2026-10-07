// The run feed: what a VBW workflow run is doing now, read from the files Claude
// Code writes for it (mods_4_vbw.md §4). Under <sessionDir>/subagents/workflows/<runId>/:
// journal.jsonl (started/result lines), agent-<id>.meta.json (type, description,
// model) and agent-<id>.jsonl (each agent's transcript); and, once the run ends,
// <sessionDir>/workflows/<runId>.json. These are undocumented Claude Code files:
// every reader here degrades to less detail and never throws. Each file is read
// only when its size or time changed, and a done agent's transcript at most once
// more after it is done. The output is the run model (mods_build_plan.md).

export const QUIET_MS = 45_000
const ROLES = ['architect', 'lead', 'dev', 'qa', 'scout', 'debugger', 'docs']
const MAX_READ = 4 * 1024 * 1024 // Claude Code refuses a larger read
const SCAN = 8 // final jsons findRun opens at most, newest first

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x)
const str = (x) => (typeof x === 'string' ? x : '')
const num = (x) => (typeof x === 'number' && Number.isFinite(x) ? x : null)
const oneLine = (s) => str(s).replace(/\s+/g, ' ').trim()
const cut = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s)
const base = (p) => str(p).split(/[\\/]/).filter(Boolean).pop() || ''
const time = (iso) => {
  const t = Date.parse(str(iso))
  return Number.isFinite(t) ? t : null
}

function json(text) {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

// Lines of a JSONL text that parse as objects; a half-written last line is skipped.
const rows = (text) => str(text).split('\n').map((l) => (l.trim() ? json(l) : undefined)).filter(isObj)

// ---- parsers (pure) ----

// journal.jsonl -> [{type:'started', agentId, label, phase} | {type:'result', agentId, result, error}]
export function parseJournal(text) {
  const out = []
  for (const r of rows(text)) {
    const id = str(r.agentId)
    if (!id) continue
    if (r.type === 'started') out.push({ type: 'started', agentId: id, label: str(r.label), phase: str(r.phase) || null })
    else if (r.type === 'result') {
      const err = r.error ?? (isObj(r.result) ? r.result.error : undefined)
      out.push({ type: 'result', agentId: id, result: r.result ?? null, error: err == null || err === false ? null : err })
    }
  }
  return out
}

const roleOf = (type) => {
  const r = str(type).replace(/^vbw:/, '')
  return str(type).startsWith('vbw:') && ROLES.includes(r) ? r : 'agent'
}
// "qa P55" -> "P55" when the first word is the role.
const labelOf = (desc, role) => {
  const d = oneLine(desc)
  return role !== 'agent' && (d === role || d.startsWith(role + ' ')) ? d.slice(role.length).trim() : d
}
// 'claude-sonnet-5-5' -> 'sonnet'; a family name stays itself.
const modelOf = (m) => {
  const s = str(m).toLowerCase()
  if (!s) return null
  return ['opus', 'sonnet', 'haiku', 'fable'].find((f) => s.includes(f)) || s
}

// agent-<id>.meta.json -> {role, label, model} | null
export function parseMeta(text) {
  const m = typeof text === 'string' ? json(text) : undefined
  if (!isObj(m)) return null
  const role = roleOf(m.agentType)
  return { role, label: labelOf(m.description, role), model: modelOf(m.model) }
}

// What a tool call means, in a few words.
const host = (u) => (/^[a-z]+:\/\/([^/?#]+)/i.exec(str(u)) || [])[1]
const shell = (c) => cut(oneLine(str(c).replace(/^\s*cd\s+("[^"]*"|'[^']*'|\S+)\s*(&&|;)\s*/, '')), 41)
const SAY = {
  read: ['reading', (i) => base(i.file_path)],
  bash: ['running', (i) => shell(i.command)],
  edit: ['editing', (i) => base(i.file_path)],
  multiedit: ['editing', (i) => base(i.file_path)],
  write: ['editing', (i) => base(i.file_path)],
  notebookedit: ['editing', (i) => base(i.notebook_path)],
  grep: ['searching', (i) => cut(oneLine(i.pattern), 41)],
  glob: ['searching', (i) => cut(oneLine(i.pattern), 41)],
  websearch: ['researching', (i) => cut(oneLine(i.query), 41)],
  webfetch: ['researching', (i) => host(i.url)],
  structuredoutput: ['reporting', () => ''],
}
// What a tool call means, in a few words.
function intention(name, input) {
  const say = SAY[str(name).toLowerCase()]
  if (!say) return str(name) || 'working'
  const what = say[1](isObj(input) ? input : {})
  return what ? say[0] + ' ' + what : say[0]
}

function activityOf(blocks) {
  const b = Array.isArray(blocks) ? blocks[blocks.length - 1] : null
  if (!isObj(b)) return null
  if (b.type === 'tool_use') return { kind: 'tool', text: intention(b.name, b.input) }
  if (b.type === 'thinking' || b.type === 'redacted_thinking') return { kind: 'tool', text: 'thinking' }
  if (b.type !== 'text') return null
  const t = oneLine(b.text)
  if (!t) return null
  return { kind: 'text', text: t.length > 70 ? '…' + t.slice(-70).trim() : t }
}

const context = (u) => {
  if (!isObj(u)) return null
  const parts = [u.input_tokens, u.cache_read_input_tokens, u.cache_creation_input_tokens].map(num)
  return parts.some((x) => x !== null) ? parts.reduce((a, x) => a + (x || 0), 0) : null
}

// agent-<id>.jsonl -> {activity, tokens, firstAt, lastAt}: the last assistant line's
// last block, the context of the last usage, the first and last line times.
export function parseTranscript(text) {
  const out = { activity: null, tokens: null, firstAt: null, lastAt: null }
  const lines = str(text).split('\n')
  let seenAssistant = false
  for (let k = lines.length - 1; k >= 0; k--) {
    if (!lines[k].trim()) continue
    const r = json(lines[k])
    if (!isObj(r)) continue
    if (out.lastAt === null) out.lastAt = time(r.timestamp)
    if (r.type !== 'assistant' || !isObj(r.message)) continue
    if (!seenAssistant) {
      seenAssistant = true
      out.activity = activityOf(r.message.content)
    }
    if (out.tokens === null) out.tokens = context(r.message.usage)
    if (out.tokens !== null && out.lastAt !== null) break
  }
  const first = lines.slice(0, 20).map((l) => (l.trim() ? json(l) : undefined)).find((r) => isObj(r) && time(r.timestamp) !== null)
  out.firstAt = first ? time(first.timestamp) : null
  return out
}

// An agent's result as one line of at most 80 characters, or null.
export function resultLine(r) {
  let s = ''
  if (typeof r === 'string') s = (r.split('\n').find((l) => l.trim()) || '').replace(/^\s*#+\s*/, '')
  else if (isObj(r)) {
    s = [r.summary, r.verdict, r.status, r.message].map(str).find((x) => x.trim()) || ''
    if (!s) {
      s = Object.entries(r)
        .map(([k, v]) => k + ': ' + (Array.isArray(v) ? v.length : isObj(v) ? '{…}' : String(v)))
        .join(', ')
    }
  } else if (typeof r === 'number' || typeof r === 'boolean') s = String(r)
  s = oneLine(s)
  return s ? cut(s, 80) : null
}

const STATUS = { running: 'running', completed: 'completed', failed: 'failed', error: 'failed' }

// The run model (mods_build_plan.md, "Shared contract"). Inputs: journal text (or
// parsed events), metas {id: {role,label,model,spawnedAt}}, transcripts
// {id: parseTranscript(...)}, the final json object or null, now in ms.
export function runModel(input) {
  try {
    const o = isObj(input) ? input : {}
    const runId = str(o.runId)
    if (!runId) return null
    const now = num(o.now) ?? 0
    const events = Array.isArray(o.journal) ? o.journal : parseJournal(o.journal)
    const metas = isObj(o.metas) ? o.metas : {}
    const txs = isObj(o.transcripts) ? o.transcripts : {}
    const final = isObj(o.final) ? o.final : null
    const status = !final ? 'running' : STATUS[str(final.status)] || 'stopped'
    const progress = {}
    for (const p of final && Array.isArray(final.workflowProgress) ? final.workflowProgress : []) {
      if (isObj(p) && p.type === 'workflow_agent' && str(p.agentId)) progress[p.agentId] = p
    }
    const order = []
    const started = {}
    const results = {}
    let phase = null
    const seen = []
    for (const e of events) {
      if (!isObj(e) || !str(e.agentId)) continue
      if (!order.includes(e.agentId)) order.push(e.agentId)
      if (e.type === 'started') {
        started[e.agentId] = e
        if (e.phase) phase = e.phase
        if (e.phase && !seen.includes(e.phase)) seen.push(e.phase)
      } else if (e.type === 'result') results[e.agentId] = e
    }
    for (const id of Object.keys(metas)) if (!order.includes(id)) order.push(id)
    const agents = order.map((id) => agentModel(id, metas[id], txs[id], started[id], results[id], progress[id], status, now))
    const starts = agents.map((a) => a.startedAt).filter((t) => t !== null)
    const startedAt = num(final && final.startTime) ?? (starts.length ? Math.min(...starts) : null)
    const dur = num(final && final.durationMs)
    const endedAt = !final || status === 'running' ? null : num(final.startTime) !== null && dur !== null ? final.startTime + dur : time(final.timestamp)
    const titles = (final && Array.isArray(final.phases) ? final.phases : []).map((p) => str(isObj(p) && p.title)).filter(Boolean)
    const phases = titles.length ? titles : seen
    return { runId, kind: str(o.kind) || str(final && final.workflowName) || null, phase, phases, startedAt, endedAt, status, agents }
  } catch {
    return null
  }
}

function agentModel(id, meta, tx, start, res, prog, runStatus, now) {
  const m = isObj(meta) ? meta : {}
  const t = isObj(tx) ? tx : {}
  const p = isObj(prog) ? prog : {}
  let role = ROLES.includes(m.role) || m.role === 'agent' ? m.role : null
  let label = typeof m.label === 'string' ? m.label : null
  if (role === null || label === null) {
    const words = oneLine(start && start.label).split(' ')
    const guess = ROLES.includes(words[0]) ? words[0] : roleOf(p.agentType)
    role = role ?? guess
    label = label ?? labelOf(start ? start.label : '', role)
  }
  const pStart = num(p.startedAt)
  const startedAt = pStart ?? num(t.firstAt) ?? num(m.spawnedAt)
  const lastSeenAt = num(t.lastAt) ?? startedAt
  const failedBy = res ? res.error != null : runStatus !== 'running' || ['failed', 'error'].includes(p.state)
  const ended = Boolean(res) || failedBy
  let state = failedBy ? 'failed' : res ? 'done' : 'working'
  if (state === 'working' && lastSeenAt !== null && now - lastSeenAt > QUIET_MS) state = 'quiet'
  const pEnd = pStart !== null && num(p.durationMs) !== null ? pStart + p.durationMs : null
  return {
    id,
    role,
    label,
    phase: (start && start.phase) || null,
    model: modelOf(m.model) ?? modelOf(p.model),
    state,
    activity: isObj(t.activity) ? t.activity : null,
    startedAt,
    endedAt: ended ? pEnd ?? num(t.lastAt) : null,
    lastSeenAt,
    tokens: num(t.tokens) ?? num(p.tokens),
    result: res ? resultLine(res.error != null ? res.error : res.result) : null,
  }
}

// ---- readers ($, never throw) ----

// A file's parsed value, read again only when its signature (size:mtime) changed.
// A file too big to read keeps its last value and is not tried again until it changes.
async function load($, files, path, entry, parse) {
  const sig = entry.size + ':' + entry.mtimeMs
  const had = files[path]
  if (had && had.sig === sig) return had.value
  let value = had ? had.value : null
  if (entry.size <= MAX_READ) {
    try {
      value = parse(await $.fs.read(path))
    } catch {
      return value // try again next time
    }
  }
  files[path] = { sig, value }
  return value
}

const statFile = ($, path) => $.fs.stat(path).then((s) => (isObj(s) && s.kind === 'file' ? s : null), () => null)
const clock = ($) => Promise.resolve().then(() => $.clock.now()).then((t) => num(t) ?? Date.now(), () => Date.now())
const byName = ($, dir) => $.fs.list(dir).then((es) => Object.fromEntries(es.filter(isObj).map((e) => [e.name, e])), () => ({}))

// The run model of <sessionDir>'s run <runId>, or null when it cannot be read.
export async function gatherRun($, cache, opts) {
  try {
    const { sessionDir, runId, kind } = opts
    if (cache.runId !== runId) {
      for (const k of Object.keys(cache)) delete cache[k]
      Object.assign(cache, { runId, files: {}, sealed: {} })
    }
    const dir = sessionDir + '/subagents/workflows/' + runId
    const entries = await $.fs.list(dir)
    const at = {}
    for (const e of entries) if (isObj(e) && e.kind === 'file') at[e.name] = e
    const journal = at['journal.jsonl'] ? (await load($, cache.files, dir + '/journal.jsonl', at['journal.jsonl'], parseJournal)) || [] : []
    const done = new Set(journal.filter((e) => e.type === 'result').map((e) => e.agentId))
    const metas = {}
    const transcripts = {}
    for (const name of Object.keys(at)) {
      const m = /^agent-([A-Za-z0-9_-]+)\.meta\.json$/.exec(name)
      if (!m) continue
      metas[m[1]] = { ...(await load($, cache.files, dir + '/' + name, at[name], parseMeta)), spawnedAt: at[name].mtimeMs || null }
    }
    for (const name of Object.keys(at)) {
      const m = /^agent-([A-Za-z0-9_-]+)\.jsonl$/.exec(name)
      if (!m) continue
      const id = m[1]
      const path = dir + '/' + name
      if (cache.sealed[id]) {
        transcripts[id] = cache.files[path] ? cache.files[path].value : null
        continue
      }
      transcripts[id] = await load($, cache.files, path, at[name], parseTranscript)
      if (done.has(id)) cache.sealed[id] = true
    }
    const finalPath = sessionDir + '/workflows/' + runId + '.json'
    const fe = await statFile($, finalPath)
    const final = fe ? await load($, cache.files, finalPath, fe, json) : null
    return runModel({ runId, kind, journal, metas, transcripts, final, now: await clock($) })
  } catch {
    return null
  }
}

// The newest run in <sessionDir> that has not ended (no final json, or one still
// running): {runId, kind} or null. For finding a run already going after a reload.
export async function findRun($, cache, sessionDir) {
  try {
    if (!isObj(cache.files)) cache.files = {}
    if (!isObj(cache.dirAt)) cache.dirAt = {}
    const runs = Object.values(await $.fs.list(sessionDir + '/subagents/workflows')).filter((e) => isObj(e) && e.kind === 'dir' && /^wf_/.test(e.name))
    const finals = await byName($, sessionDir + '/workflows')
    const scripts = {}
    for (const e of Object.values(await byName($, sessionDir + '/workflows/scripts'))) {
      const m = /^(.+)-(wf_[^/]+)\.js$/.exec(str(e.name))
      if (m && !(scripts[m[2]] && scripts[m[2]].at >= e.mtimeMs)) scripts[m[2]] = { kind: m[1], at: num(e.mtimeMs) ?? 0 }
    }
    const when = async (id) => {
      if (scripts[id]) return scripts[id].at
      if (cache.dirAt[id] === undefined) {
        const s = await $.fs.stat(sessionDir + '/subagents/workflows/' + id).catch(() => null)
        cache.dirAt[id] = num(s && s.mtimeMs) ?? 0
      }
      return cache.dirAt[id]
    }
    const order = []
    for (const r of runs) order.push({ id: r.name, at: await when(r.name) })
    order.sort((a, b) => b.at - a.at)
    let opened = 0
    for (const { id } of order) {
      const fe = finals[id + '.json']
      const kind = scripts[id] ? scripts[id].kind : null
      if (!fe) return { runId: id, kind }
      const path = sessionDir + '/workflows/' + id + '.json'
      const known = cache.files[path] && cache.files[path].sig === fe.size + ':' + fe.mtimeMs
      if (!known && ++opened > SCAN) break
      const final = await load($, cache.files, path, fe, json)
      if (isObj(final) && final.status === 'running') return { runId: id, kind: str(final.workflowName) || kind }
    }
    return null
  } catch {
    return null
  }
}
