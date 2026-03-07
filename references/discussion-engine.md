# Discussion Engine

One engine. Three entry points. Claude thinks, not pattern-matches.

Replaces the three competing discussion subsystems (Bootstrap Discovery, Phase Discovery, Phase Discussion) with a single unified protocol. The user is the visionary. Claude is the builder. The engine's job is to surface decisions that downstream agents (researcher, planner, executor) need to act without asking the user again.

## Entry Points

All resolve to this protocol:

- `/vbw:vibe` — auto-detects discussion need from state
- `/vbw:vibe --discuss [N]` — explicit flag, targets phase N
- `/vbw:discuss [N]` — standalone command

## Step 1: Calibrate

Read conversation signals to determine user sophistication. This is NOT a question — it is inference from:

- Language in prior messages (jargon vs plain language)
- Project description complexity
- Config profile (yolo/prototype/default/production)
- Whether they typed `/vbw:discuss` vs `/vbw:vibe`

Two modes, silently selected:

| Mode | Signals | Question style | Depth |
|------|---------|---------------|-------|
| **Builder** | Plain language, vibe keywords, prototype/yolo profile | Scenario-based, no jargon, cause-and-effect | Concrete situations |
| **Architect** | Technical terms, specific requirements, production profile | Direct, uses domain terms, trade-off framing | Design decisions |

Same gray area, two modes:

**Builder:** "When someone's internet drops while they're writing a post, what should happen?"
- "Save what they wrote and try again later"
- "Show a warning and let them retry"
- "Let me explain..."

**Architect:** "Offline write strategy for post creation?"
- "Queue locally, sync on reconnect (optimistic)"
- "Block submission, show connectivity state (pessimistic)"
- "Let me explain..."

## Step 1.5: Recall Prior Context (MuninnDB)

Before generating gray areas, recall relevant prior decisions:
1. Read `muninndb_vault` from `.vbw-planning/config.json`. If empty: skip memory recall, proceed to Step 2.
2. Call `muninn_guide(vault: {vault})` on first use.
3. Call `muninn_activate(vault: {vault}, context: "{phase goal} {project description}", limit: 10)`.
4. For each result with score > 0.5: note it as prior context that may constrain or inform gray areas.
5. If no results AND this is Phase 2+: report "⚠ Memory recall returned 0 results despite prior phases."

Prior decisions surface constraints: a Phase 1 discussion that chose "optimistic offline sync" eliminates that gray area from Phase 3 — it's already decided.

## Step 2: Orient

Read the phase goal from ROADMAP.md and **think** about what gray areas exist. No keyword matching. No predefined templates. Pure analysis. Factor in any prior decisions recalled in Step 1.5 — do not re-ask questions that are already settled.

The engine asks itself:

> "What decisions about this phase could go multiple ways and would change what gets built?"

Generate phase-specific gray areas. These must be concrete, not categorical.

Bad (generic): "UI decisions", "Data handling", "Error states"
Good (phase-specific): For "Recipe recommendation engine": "How recommendations are surfaced (feed vs search vs suggestions)", "Cold-start behavior (new user with no history)", "Dietary restriction handling (strict filter vs soft preference)"

For bootstrap context (no phases yet): generate gray areas from the project description and domain research (if available).

Profile depth controls gray area count:

| Profile | Gray Areas |
|---------|-----------|
| prototype | 2-3 |
| default | 3-5 |
| production | 4-6 |

Present gray areas as a multi-select using AskUserQuestion: "Which areas should we discuss?"
No "skip all" option — if the user ran discuss, give them real choices.

## Step 3: Explore

For each selected area, have a natural conversation. Not a form. Not a fixed number of questions.

The rhythm:
1. Open with a framing question for the area (use AskUserQuestion).
2. Each answer informs the next question — follow the thread.
3. After 3-4 exchanges, check: "Anything else about [area], or move on?"
4. If more: continue. If done: next area.

**Scope awareness** (simple, not a subsystem):
If the user mentions something outside the phase boundary:
> "[Feature] sounds like its own phase. I'll note it. Back to [current area]..."
One line. Captured in Deferred Ideas. No feature extraction pipeline.

**Vague answer handling** (natural, not mechanical):
If the user says something vague like "I want it to be fast", just ask a follow-up:
> "Fast in what way — page loads, search results, or handling lots of users at once?"
No disambiguation subsystem. Just good conversation.

## Step 4: Capture

Write `{phase}-CONTEXT.md` to the phase directory:

```markdown
# Phase N: Name — Context

Gathered: YYYY-MM-DD
Calibration: builder | architect

## Phase Boundary
[What this phase delivers — scope anchor from ROADMAP.md]

## Decisions
### [Gray Area 1]
- [Decision or preference]
- [Follow-up detail if captured]

### [Gray Area 2]
- [Decision or preference]

### Open (Claude's discretion)
[Areas where user said "you decide" or was indifferent]

## Deferred Ideas
[Out-of-scope ideas captured during discussion. Empty if none.]
```

**Store decisions to MuninnDB:** For each decision captured (not "Open" items), call `muninn_decide(vault: {vault}, concept: "{gray area}: {decision}", rationale: "{why}", alternatives: ["{rejected options}"])`. This ensures downstream agents (Lead, Dev, Architect) can recall these decisions without re-reading CONTEXT.md.

Also append to `discovery.json` using this schema:

```json
{
  "answered": [
    {
      "question": "How should recommendations be surfaced?",
      "answer": "Inline suggestions in the feed, not a separate page",
      "area": "recommendation-surfacing",
      "phase": "bootstrap | 03",
      "date": "YYYY-MM-DD"
    }
  ],
  "inferred": [
    {
      "id": "REQ-01",
      "text": "Recommendations appear inline in the main feed",
      "priority": "Must-have",
      "source": "Discussion: recommendation surfacing"
    }
  ],
  "deferred": [
    {
      "idea": "Social sharing of recommendations",
      "mentioned_during": "Phase 3 discussion",
      "date": "YYYY-MM-DD"
    }
  ]
}
```

## Config Interaction

| Config | Effect |
|--------|--------|
| `active_profile=yolo` | Skip discussion entirely |
| `active_profile=prototype` | 2-3 gray areas, quick explore |
| `active_profile=default` | 3-5 gray areas, standard depth |
| `active_profile=production` | 4-6 gray areas, thorough explore |
| `discovery_questions=false` | Skip discussion entirely |

## Design Principles

- **One engine, not three.** Bootstrap, phase discovery, and phase discussion are the same protocol with different inputs.
- **Calibrate silently.** Never ask "are you technical?" — infer it.
- **Orient from the phase, not from templates.** Gray areas come from analysis, not predefined lists.
- **Explore conversationally.** Thread-following, not form-filling.
- **Capture for downstream agents.** The output must let researcher, planner, and executor act without asking the user again.
- **Trust Claude's judgment.** This protocol is a guide, not a state machine.
