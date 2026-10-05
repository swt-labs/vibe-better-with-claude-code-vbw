// Runs a VBW workflow file under node with stubbed runtime functions, for the
// tests (no model is called). Usage:
//   node run-workflow.js WORKFLOW.js ARGS_JSON RESPONSES_JSON
// RESPONSES_JSON maps an agent label to the value agent() returns for it.
// Prints {calls: [{prompt, opts}], result, logs}.
const fs = require('fs')

const [file, argsJson, responsesJson] = process.argv.slice(2)
const source = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const responses = JSON.parse(responsesJson || '{}')
const calls = []
const logs = []
const runtime = {
  args: JSON.parse(argsJson || '{}'),
  agent: async (prompt, opts) => {
    calls.push({ prompt, opts })
    return Object.prototype.hasOwnProperty.call(responses, opts.label) ? responses[opts.label] : null
  },
  phase: () => {},
  log: m => logs.push(String(m)),
  pipeline: (items, fn) => Promise.all(items.map(fn)),
}
const body = new Function(...Object.keys(runtime), `return (async () => {\n${source}\n})()`)
body(...Object.values(runtime)).then(
  result => process.stdout.write(JSON.stringify({ calls, result: result === undefined ? null : result, logs })),
  err => {
    process.stderr.write(String(err && err.stack ? err.stack : err))
    process.exit(1)
  },
)
