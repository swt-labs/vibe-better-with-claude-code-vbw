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

Also read `active_profile` to calibrate recommendation verbosity (see Recommendation Principle).

Two modes, silently selected:

| Mode | Signals | Question style | Depth |
| ------ | --------- | --------------- | ------- |
| **Builder** | Plain language, vibe keywords, prototype/yolo profile | Scenario-based, no jargon, cause-and-effect | Concrete situations |
| **Architect** | Technical terms, specific requirements, production profile | Direct, uses domain terms, trade-off framing | Design decisions |

Same gray area, two modes:

**Builder:** "When someone's internet drops while they're writing a post, we'll save their work and try again when they're back online. This is standard — it prevents data loss. Sound good?"
- "Sounds good (Recommended — prevents data loss)"
- "I'd prefer it to show an error instead"
- "Let me explain..."

**Architect:** "For offline write handling, the enterprise-standard approach is optimistic local queueing with sync on reconnect. Pessimistic blocking has a poor UX in mobile-first apps and doesn't reduce conflict risk. Recommendation: queue locally, sync on reconnect."
- "Queue locally, sync on reconnect (Recommended — standard for mobile-first)"
- "Block submission, show connectivity state"
- "Let me explain..."

## Step 1.5: Detect Continuation

Before orienting, check if `{NN}-CONTEXT.md` already exists for the target phase.

- **If no CONTEXT.md exists:** Fresh discussion — proceed to Step 2 normally.
- **If CONTEXT.md exists:** This is a **continuation discussion**. Read the existing file to understand what was already covered (Decisions sections, Deferred Ideas, Phase Boundary). Proceed to Step 2 with this context loaded.

## Step 1.7: Assumptions Path

An alternative to the question-driven Orient → Explore → Capture flow. Instead of asking the user about gray areas, read the codebase first, form evidence-backed assumptions, and present them for correction— reducing interaction from ~15-20 questions to ~2-4 corrections.

### Activation

Check these conditions in order. The first match wins:

1. `--assumptions` flag is present → use assumptions path
2. `discussion_mode` is `"assumptions"` in `.vbw-planning/config.json` → use assumptions path
3. `discussion_mode` is `"auto"` AND `.vbw-planning/codebase/META.md` exists → use assumptions path
4. `discussion_mode` is `"questions"` or `"auto"` without codebase map → proceed to Step 2 (standard questions path)

**Codebase map guard:** If the assumptions path is activated but `.vbw-planning/codebase/META.md` does not exist, display: "Assumptions mode works best with codebase context. Run `/vbw:map` first for evidence-backed assumptions, or proceeding with questions mode." Then fall back to Step 2.

### A1: Codebase Analysis

Read codebase context files relevant to the target phase:

- `.vbw-planning/codebase/ARCHITECTURE.md` — architecture patterns, data flow
- `.vbw-planning/codebase/PATTERNS.md` — code conventions, design patterns
- `.vbw-planning/codebase/CONCERNS.md` — known issues, tech debt
- Phase goal from `ROADMAP.md`

For specific gray areas that need deeper evidence, read actual source files (model definitions, service interfaces, view controllers) inline or via Explore subagent. Do not form assumptions from codebase summaries alone when the source files are readily available.

### A2: Form Assumptions

Identify gray areas using the same analytical process as Step 2 (Orient) — ask "what decisions about this phase could go multiple ways and would change what gets built?" For each gray area, form a structured assumption instead of a question.

Gray area count follows the profile depth table: prototype 2-3, default 3-5, production 4-6.

Structure each assumption as:

```
### [Gray Area Title]

**Assumption:** [What you conclude based on codebase evidence]
**Evidence:** [File paths + specific code patterns that support this]
**Confidence:** High (90%+) | Medium (60-90%) | Low (<60%)
**Consequence if wrong:** [What breaks or needs rework]
```

Ground confidence levels in codebase evidence:
- **High** — codebase has explicit implementation matching the assumption
- **Medium** — codebase has related patterns but the specific decision is ambiguous
- **Low** — codebase provides no clear signal; genuine uncertainty

For each assumption, also form a recommendation per the Recommendation Principle. Include the recommendation in the assumption text when it differs from the assumption itself.

<example>
### Cold-Start Behavior (New User With No History)

**Assumption:** The app shows a curated default feed for new users, not an empty state. The `UserFeedService` already has a `defaultFeed()` method that returns trending items when `user.history.isEmpty`.
**Evidence:** `src/services/UserFeedService.swift:42` — `func defaultFeed() -> [FeedItem]`; `src/models/User.swift:18` — `var history: [HistoryEntry] = []`
**Confidence:** High (90%+)
**Consequence if wrong:** Empty state UX needs design work, adding ~2 days to the phase
</example>

### A3: Present for Correction

Present all assumptions at once, grouped by confidence level. Use `AskUserQuestion` with structured options.

Presentation varies by profile:

| Profile | Behavior |
| ---------- | ---------- |
| `production` | All confidence levels shown individually with detailed evidence citations. |
| `default` | High confidence batched as a confirmation list. Medium shown individually. Low become standard questions (fall through to Step 3 Explore). |
| `prototype` | High and medium batched as confirmations. Only low confidence shown individually. |
| `yolo` | All assumptions accepted automatically. Low-confidence items flagged in output but not asked. |

**High confidence (confirming):** Batch as a list: "Based on the codebase, I'm assuming: [numbered list with evidence citations]. Any corrections?"
- Options: "All correct", "I'd like to correct one", "Let me explain..."

**Medium confidence (validating):** Present individually: "I think [X] based on [evidence], but [gap]. Is this right?"
- Options: "[Assumption] (Recommended — [reason])", "[Alternative]", "Let me explain..."

**Low confidence (genuine questions):** Fall through to standard Step 3 Explore flow with recommendation-led questions.

### A4: Process Corrections

For each assumption the user reviews:
- **Confirmed:** Record as a decision with the original assumption and evidence
- **Corrected:** Record the user's correction as the decision, preserve the original assumption as context ("Originally assumed X based on [evidence]; user corrected to Y")
- **Expanded:** If the user chose "Let me explain...", capture the nuance and update the assumption accordingly

### A5: Capture

Same output as Step 4 (Capture). Write `{NN}-CONTEXT.md` using the template. Assumption-sourced decisions go in `## Decisions Made` with evidence and confidence metadata:

```
### [Gray Area]
- Decision: [confirmed assumption or user correction]
- Evidence: [file paths + patterns]
- Confidence: [level at time of assumption]
- Correction: [user's correction — omit if confirmed as-is]
```

Also append to `discovery.json` using the existing schema. For confirmed assumptions, the `answer` field records the assumption text. For corrected assumptions, `answer` records the user's correction with the original assumption noted.

After A5, skip Steps 2-4 — the assumptions path replaces Orient, Explore, and Capture for the areas it covers.

## Step 2: Orient

Read the phase goal from ROADMAP.md and **think** about what gray areas exist. No keyword matching. No predefined templates. Pure analysis.

The engine asks itself:

> "What decisions about this phase could go multiple ways and would change what gets built?"

For each gray area identified, also form a preliminary recommendation based on the codebase context and enterprise best practices. If a recommendation depends on codebase state (existing patterns, data models, framework choices), read the relevant files or cite already-loaded context before forming the recommendation — do not speculate about code you have not opened. You will use these recommendations when exploring each area in Step 3.

**Continuation mode:** When existing CONTEXT.md was loaded in Step 1.5, the question becomes:

> "What decisions about this phase are NOT already captured in the existing discussion context? What new angles, edge cases, or deeper implications haven't been explored yet?"

Exclude gray areas already covered by existing `## Decisions` subsections. Focus on:
- Topics the user didn't select in the original discussion
- Deeper implications of decisions already made (second-order effects)
- Edge cases or integration concerns that surface after the first discussion
- Deferred ideas that the user may want to revisit

Generate phase-specific gray areas. These must be concrete, not categorical.

Bad (generic): "UI decisions", "Data handling", "Error states"
Good (phase-specific): For "Recipe recommendation engine": "How recommendations are surfaced (feed vs search vs suggestions)", "Cold-start behavior (new user with no history)", "Dietary restriction handling (strict filter vs soft preference)"

For bootstrap context (no phases yet): generate gray areas from the project description and domain research (if available).

Profile depth controls gray area count:

| Profile | Gray Areas |
| --------- | ----------- |
| prototype | 2-3 |
| default | 3-5 |
| production | 4-6 |

Present gray areas as a multi-select using AskUserQuestion.
- **Fresh discussion:** "Which areas should we discuss?" No "skip all" option — if the user ran discuss, give them real choices.
- **Continuation:** "These topics weren't covered in the previous discussion. Which would you like to explore?" Include a "None — discussion is complete" option since the user may have only wanted to check.

> **AskUserQuestion spacing**: output 3–4 blank lines before the tool call (the dialog obscures trailing text).

## Step 3: Explore

**Early exit:** If no areas were selected (user chose "None — discussion is complete" in Step 2), skip directly to Step 4.

For each selected area, have a natural conversation. Not a form. Not a fixed number of questions.

The rhythm:
1. Open with your recommendation for the area (for product decisions, present options equally per the Recommendation Principle instead): state the gray area, provide your recommendation with brief reasoning (2-3 sentences), then ask for confirmation via AskUserQuestion. Format the first option as the recommended choice with "(Recommended — [brief reason])" in the label. Include 1-2 alternatives and a "Let me explain..." free-form option.
2. If user picks recommended: confirm in one line, move on. No follow-ups for standard picks.
3. If user picks alternative: record the preference. Only ask a follow-up if the alternative changes a downstream requirement or invalidates the recommendation's reasoning — otherwise move on.
4. If user picks "Let me explain...": read their free-form input, adjust your recommendation based on their reasoning, and confirm the updated decision. Treat their input as a preference, not a request for more options.
5. After covering the area, move to the next one.

**Clear-cut batching:** For decisions where the enterprise answer is standard practice across well-architected projects, batch them instead of asking individually. Present the batch as a list with brief reasoning and confirm via AskUserQuestion with options like "All good", "I'd like to discuss one of these", and "Let me explain...": "For [area], we'll use these standard approaches: [list with brief reasoning]. Any of these need discussion?"

**Scope awareness** (simple, not a subsystem):
If the user mentions something outside the phase boundary:
> "[Feature] sounds like its own phase. I'll note it. Back to [current area]..."
One line. Captured in Deferred Ideas. No feature extraction pipeline.

**Vague answer handling** (natural, not mechanical):
If the user says something vague like "I want it to be fast", just ask a follow-up:
> "Fast in what way — page loads, search results, or handling lots of users at once?"
No disambiguation subsystem. Just good conversation.

## Step 4: Capture

Resolve the CONTEXT filename:
```bash
CONTEXT_NAME=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh context "{phase-dir}")
```

**Continuation mode (CONTEXT.md already exists):** Do NOT overwrite. Merge new insights into the existing file:
- Add new `### [Gray Area]` subsections under `## Decisions` (after existing subsections)
- Append new entries to `## Deferred Ideas` if any surfaced
- Update the `Gathered:` date to today's date
- Do NOT remove, rewrite, or reorder existing content — the original discussion decisions are still valid
- Also append new entries to `discovery.json` (same schema as fresh discussion below) — continuation insights must flow into the discovery record
- **Early exit:** If the user selected "None — discussion is complete" in Step 2, skip capture entirely — do NOT update the date or any file content

**Fresh discussion:** Write `${CONTEXT_NAME}` to the phase directory:

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
| -------- | -------- |
| `active_profile=yolo` | Skip discussion entirely |
| `active_profile=prototype` | 2-3 gray areas, quick explore |
| `active_profile=default` | 3-5 gray areas, standard depth |
| `active_profile=production` | 4-6 gray areas, thorough explore |
| `discovery_questions=false` | Skip discussion entirely |
| `discussion_mode=assumptions` | Use assumptions path (Step 1.7) when codebase map exists |
| `discussion_mode=auto` | Auto-select: assumptions if `.vbw-planning/codebase/META.md` exists, questions otherwise |

## Design Principles

- **One engine, not three.** Bootstrap, phase discovery, and phase discussion are the same protocol with different inputs.
- **Calibrate silently.** Never ask "are you technical?" — infer it.
- **Orient from the phase, not from templates.** Gray areas come from analysis, not predefined lists.
- **Explore conversationally.** Thread-following, not form-filling.
- **Capture for downstream agents.** The output must let researcher, planner, and executor act without asking the user again.
- **Trust Claude's judgment.** This protocol is a guide, not a state machine.

## Recommendation Principle

You own the technical decisions. The user owns the product decisions.

For every **technical decision** (architecture, data model, API design, framework selection, error handling strategy), lead with your recommendation and reasoning. Do not present equal-weight options and wait for the user to ask what an expert would do.

For **product decisions** (feature priority, UX preferences, naming, branding, target audience), present options equally — the user decides.

When codebase context is available, ground recommendations in the existing architecture (patterns, conventions, prior decisions). When it is not, recommend enterprise best practices that minimize tech debt. If a recommendation depends on codebase state, read the relevant files or cite already-loaded context before stating the recommendation — do not speculate about code you have not opened.

If the recommendation is clear-cut, state it as the plan and ask for confirmation via AskUserQuestion with the recommended option marked. If genuinely ambiguous (multiple valid approaches with material trade-offs), present 2-3 options with a recommended one marked, brief pros for each, and why you would pick the recommended one.

Scale recommendation verbosity to the active profile: `production` shows full reasoning with trade-offs for alternatives; `default` gives concise reasoning; `prototype` states the decision with minimal justification.

## Question Anti-Patterns

<examples>
<example>
**Anti-pattern: Equal-weight technical options** — presenting architectural choices without a recommendation.

BAD: "Should X use approach A or approach B?"

GOOD: State the recommendation with reasoning, then confirm: "For X, the enterprise-standard approach is A because [reason]. Sound right?"
</example>

<example>
**Anti-pattern: Asking questions the codebase can answer** — posing questions that reading the code would resolve.

BAD: "Does [model] derive from [source A] or [source B]?"

GOOD: Read the relevant file first, then state what the code shows and what it implies for the decision. See Step 1.7 (Assumptions Path) for the systematic approach: read codebase first, form assumptions, present for correction.
</example>
</examples>

## Two-Tier Context System

Decision capture happens at two levels:

- **Milestone scope** → `.vbw-planning/CONTEXT.md` — written by Scope mode (`/vbw:vibe --scope`). Captures decomposition decisions (why N phases, ordering rationale), requirement-to-phase mapping, project-level key decisions, and deferred ideas. Archived with the milestone.
- **Phase discussion** → `.vbw-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` — written by this Discussion Engine. Captures gray-area decisions, user preferences, and scope boundaries for a single phase.

Both are available to agents during execution. Milestone context is injected into agent context by `compile-context.sh`; phase context is passed to agents by the orchestrator (Plan mode includes it in the subagent task prompt). Milestone context gives agents the "why" behind the phase structure; phase context gives them the "what" for their specific phase.
