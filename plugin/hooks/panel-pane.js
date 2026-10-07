// Mission Control (mods_4_vbw.md §3.3): the pane, seven tabs as buttons across the
// top, after the VBW portrait where the terminal draws images (§3.7). Now opens
// with the panel's own sentences and its sound switch above the live workflow; the
// other tabs are the views of panel-mission-live.js and panel-mission-record.js.
// At ship the pane shows VBW Wrapped (panel-candy.js) until a tab is chosen; the
// all-green sweep crosses the top of Proof. Pure over the state panel.js gathered:
// no `$` here; presses go to `on.act(action)` and the sound switch to `on.sound()`.
import { nowModel, timelineModel, costsModel, renderNow, renderTimeline, renderCosts } from './panel-mission-live.js'
import { planModel, proofModel, decisionsModel, teamModel, renderPlan, renderProof, renderDecisions, renderTeam } from './panel-mission-record.js'
import { renderWrapped } from './panel-candy.js'
import { NEED } from './panel-palette.js'

export const TABS = [['now', 'Now'], ['plan', 'Plan'], ['proof', 'Proof'], ['timeline', 'Timeline'], ['decisions', 'Decisions'], ['team', 'Team'], ['costs', 'Costs']]

// The panel's sentences (panel-view.js), each with its term in small text, and the sound switch.
function summary(ui, v, st, on) {
  const { Box, Text, Button } = ui
  const rows = v.rows.map((r) =>
    h(Box, { key: r.id, flexDirection: 'column', marginBottom: 1 },
      h(Text, { color: r.id === 'need' && v.need ? NEED : undefined }, String(r.text)),
      h(Text, { dimColor: true }, String(r.term))))
  rows.push(
    h(Box, { key: 'sound', flexDirection: 'row', marginBottom: 1 },
      h(Text, null, 'Sound is ' + (st.sound ? 'on' : 'off') + '. '),
      h(Button, { key: 'sound-toggle', label: st.sound ? 'Turn off' : 'Turn on', onPress: () => on.sound() })))
  return rows
}

function body(ui, { st, now, width }, act) {
  const rec = st.record
  switch (st.tab) {
    case 'plan': return renderPlan({ ...ui, Input: undefined }, planModel({ record: rec, phase: st.phase }), act) // Ask is not wired yet
    case 'proof': return renderProof(ui, proofModel({ record: rec, selected: st.check }), act)
    case 'timeline': return renderTimeline(ui, timelineModel({ run: st.run, now, steps: st.steps, width: Math.max(10, width - 24) }))
    case 'decisions': return renderDecisions(ui, decisionsModel({ record: rec }))
    case 'team': return renderTeam(ui, teamModel({ record: rec }), act)
    case 'costs': return renderCosts(ui, costsModel({ runs: st.leases, sessionCost: st.cost, width: Math.max(1, Math.floor(width / 3)) }))
    default: return renderNow(ui, nowModel({ run: st.run, now, selected: st.agent }), act)
  }
}

// input: { st, v, now, width, portrait (a PNG's path, or null), wrapped (the
// Wrapped model, or null), sweep ({ cols, cells } of the sweep's frame, or null) }.
export function renderPane(ui, input, on) {
  const { Box, Button, Image, Raster } = ui
  const { st, v } = input
  const act = (a) => on.act(a)
  const wrapped = st.tab === 'wrapped' && input.wrapped ? input.wrapped : null
  const tab = wrapped ? 'wrapped' : TABS.some(([id]) => id === st.tab) ? st.tab : 'now'
  const tabs = h(Box, { key: 'tabs', flexDirection: 'row', flexWrap: 'wrap', columnGap: 1, flexShrink: 1 },
    ...TABS.map(([id, label]) => h(Button, {
      key: 'tab-' + id, label, ...(id === tab ? { variant: 'primary' } : { dimColor: true }), onPress: () => act({ show: id }),
    })))
  const portrait = Image && typeof input.portrait === 'string'
    ? [h(Image, { key: 'vbw-portrait', source: { file: input.portrait, format: 'png' }, columns: 6, rows: 3, alt: 'VBW' })] : []
  const head = h(Box, { key: 'head', flexDirection: 'row', columnGap: 1, marginBottom: 1 }, ...portrait, tabs)
  const sweep = tab === 'proof' && Raster && input.sweep ? [h(Raster, { key: 'vbw-sweep', columns: input.sweep.cols, rows: 1, cells: input.sweep.cells })] : []
  const view = wrapped ? renderWrapped(ui, wrapped) : body(ui, { ...input, st: { ...st, tab } }, act)
  return h(Box, { flexDirection: 'column' }, head, ...(tab === 'now' ? summary(ui, v, st, on) : []), ...sweep, view)
}
