// R270: the panel words a rough step note as a range (evidence level L1).
import test from 'node:test'
import assert from 'node:assert/strict'
import { pathToFileURL } from 'node:url'
import { PLUGIN } from './helpers/fake-mod.mjs'

process.env.TZ = 'Europe/Zurich'
const step = await import(pathToFileURL(PLUGIN + '/hooks/panel-step.js').href)

const NOW = new Date(2026, 9, 24, 15, 40).getTime()
const at = (m) => new Date(NOW + m * 60000).toISOString()

test('a rough note words a range from end_low, end_high, rough and runs', () => {
  const note = { end: at(18), end_low: at(15), end_high: at(21), rough: true, runs: 2 }
  assert.equal(step.stepWords(note, NOW).text, 'roughly 15 to 21 min, until around 15:55 to 16:01 (rough guess from 2 runs)')
})

test('a rough note whose ends agree words one figure; one run says run', () => {
  const note = { end: at(10), end_low: at(10), end_high: at(10), rough: true, runs: 1 }
  assert.equal(step.stepWords(note, NOW).text, 'roughly 10 min, until around 15:50 (rough guess from 1 run)')
})

test('a rough range names the day of an end on another day', () => {
  const far = { end: at(700), end_low: at(500), end_high: at(840), rough: true, runs: 3 }
  assert.equal(step.stepWords(far, NOW).text, 'roughly 500 to 840 min, until around tomorrow 00:00 to tomorrow 04:40 (rough guess from 3 runs)')
})

test('a tight note keeps the single figure', () => {
  const note = { end: at(12), end_low: at(11), end_high: at(13), rough: false, runs: 6 }
  assert.equal(step.stepWords(note, NOW).text, 'about 12 min, until around 15:52')
})
