// What a shell command means, as one short plain line (R87): "running tests",
// "recording P6.7 done", "running fix_topbar.py". Never the raw command, its
// flags or anything that could be a secret: only a known phrase, or the bare
// name of a script file, is ever shown. Pure; never throws.

const MAX = 40
const FALLBACK = 'running a command'
const INTERPRETERS = /^(python[0-9.]*|node|nodejs|deno|bun|tsx|ts-node|ruby|perl|php|bash|sh|zsh|dash|fish|osascript|Rscript|lua)$/
const SKIP = /^(cd|export|set|unset|source|\.|true|false|echo|printf|test|\[|exit|sleep)$/
const TEST_RUNNERS = [
  /^(bats|pytest|py\.test|jest|vitest|mocha|rspec|phpunit|tox|nox)$/,
]

const cut = (s) => (s.length > MAX ? s.slice(0, MAX - 1).trimEnd() + '…' : s)
const base = (p) => String(p).split('/').filter(Boolean).pop() || ''
// A name safe to show: letters, digits, dot, dash, underscore, plus.
const plain = (w) => (typeof w === 'string' && /^[\w.+-]{1,40}$/.test(w) ? w : '')

// Words of one command segment, quotes removed from around a word.
const wordsOf = (seg) => (seg.match(/"[^"]*"?|'[^']*'?|\S+/g) || []).map((w) => w.replace(/^(["'])(.*?)\1?$/, '$2'))

// Split on ; & | and newlines that are outside quotes.
function segments(command) {
  const out = []
  let cur = ''
  let q = ''
  for (const ch of command) {
    if (q) {
      if (ch === q) q = ''
      cur += ch
    } else if (ch === '"' || ch === "'") {
      q = ch
      cur += ch
    } else if (';&|\n'.includes(ch)) {
      out.push(cur)
      cur = ''
    } else cur += ch
  }
  out.push(cur)
  return out.map((s) => s.trim()).filter(Boolean)
}

const ids = (a) => a.filter((w) => !w.startsWith('-')).map(plain).filter(Boolean)
const VBW = {
  'run start': () => 'starting a run',
  'run end': () => 'closing the run',
  'run confirm': () => 'checking the record',
  'plan done': (a) => 'recording ' + (ids(a)[0] || 'a plan') + ' done',
  'plan block': (a) => 'recording ' + (ids(a)[0] || 'a plan') + ' blocked',
  'plan reset': (a) => 'resetting ' + (ids(a)[0] || 'a plan'),
  'fix done': (a) => 'recording ' + (ids(a)[0] || 'a fix') + ' fixed',
  'fix retry': (a) => 'retrying ' + (ids(a)[0] || 'a fix'),
  'qa finding': () => 'recording a QA finding',
  'qa record': () => 'recording a QA verdict',
  'req accept': (a) => 'recording ' + (ids(a)[0] || 'a requirement') + ' accepted',
  'req reject': (a) => 'recording ' + (ids(a)[0] || 'a requirement') + ' rejected',
  'spec sync': () => 'syncing the spec',
  'spec check': () => 'checking the spec',
  'spec add': () => 'adding a requirement',
  'milestone start': () => 'starting a milestone',
  'todo add': () => 'adding a todo',
  apply: (a) => (a.includes('--patch') ? 'updating the plan' : 'recording the plan'),
  approve: () => 'approving the contract',
  prove: () => 'proving the checks',
  check: () => 'running the checks',
  next: () => 'reading the next step',
  status: () => 'reading the status',
  show: (a) => 'showing ' + (ids(a).slice(0, 2).join(' ') || 'the record'),
  ship: () => 'shipping the milestone',
  decide: () => 'recording a decision',
  commit: () => 'committing',
}

function isTests(w) {
  const [cmd, a = '', b = ''] = w
  const name = base(cmd)
  if (TEST_RUNNERS.some((r) => r.test(name))) return true
  if (['npm', 'pnpm', 'yarn', 'bun'].includes(name)) return a === 'test' || (a === 'run' && /^test/.test(b)) || /^test:/.test(a)
  if (['cargo', 'go', 'dotnet', 'swift', 'mvn', 'gradle', 'make'].includes(name)) return a === 'test' || a === 'check' && name === 'make'
  if (/^python[0-9.]*$/.test(name)) return a === '-m' && (b === 'pytest' || b === 'unittest')
  if (name === 'node' || name === 'deno' || name === 'bun') return w.includes('--test')
  return false
}

function intend(seg) {
  let w = wordsOf(seg)
  while (w.length && /^\w+=/.test(w[0])) w = w.slice(1)
  if (!w.length) return null
  const name = base(w[0])
  if (SKIP.test(name) && !/\//.test(w[0])) return null
  if (name === 'vbw') {
    const a = w.slice(1)
    const two = VBW[a[0] + ' ' + a[1]]
    const one = VBW[a[0]]
    return two ? two(a.slice(2)) : one ? one(a.slice(1)) : 'running vbw'
  }
  if (isTests(w)) return 'running tests'
  if (INTERPRETERS.test(name)) {
    const args = w.slice(1)
    let i = 0
    while (i < args.length && args[i].startsWith('-') && args[i] !== '-') {
      if (/^-[a-zA-Z]*[ec]$|^--(eval|command|print)$/.test(args[i])) return 'running a script'
      i++
    }
    const file = args[i]
    if (!file || file === '-' || file.startsWith('<')) return 'running a script'
    return plain(base(file)) ? 'running ' + base(file) : 'running a script'
  }
  if (/^\.{0,2}\//.test(w[0]) || /^[\w.-]+\/[\w./-]+$/.test(w[0])) return plain(name) ? 'running ' + name : FALLBACK
  return FALLBACK
}

// The intention of a shell command: one line, at most 40 characters.
export function shellIntent(command) {
  try {
    if (typeof command !== 'string') return FALLBACK
    for (const seg of segments(command)) {
      const t = intend(seg)
      if (t) return cut(t)
    }
  } catch {
    // fall through
  }
  return FALLBACK
}
