# Prompting Best Practices for VBW Artifact Development

Curated reference for writing and reviewing VBW's LLM-consumed artifacts: commands, agents, templates, references, CLAUDE.md generation, and context compilation output. Distilled from [Anthropic's prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) and [Claude Code best practices](https://code.claude.com/docs/en/best-practices).

**Scope**: Apply these principles when creating or modifying markdown files that Claude reads as instructions — command definitions, agent definitions, templates, reference docs, bootstrap-generated CLAUDE.md sections, and compiled context output. These do NOT apply to pure bash scripts, JSON configs, or test infrastructure.

**Staleness note**: Last reviewed against source docs 2026-04-02. Review quarterly — these are foundational principles, not API specs.

---

## 1. Be Clear and Direct

Claude responds best to explicit instructions. Vague framing forces the model to guess intent.

- State exactly what the agent should do, in what order, and what constraints apply.
- Use numbered steps when order matters. Use bullet points for unordered constraints.
- If a behavior is required, say so plainly. If a behavior is forbidden, state what to do instead (not just what to avoid).
- **Colleague test**: Show your instruction to someone with minimal context. If they'd be confused, Claude will be too.

**Anti-pattern** (VBW-specific): Instructions that say "handle edge cases" or "be thorough" without specifying which edge cases or what thoroughness means. Name the specific scenarios.

## 2. Provide Context and Motivation

Explaining WHY behind an instruction helps Claude generalize correctly beyond the literal words.

- When a rule exists for a non-obvious reason, include the reason inline. Claude will apply the principle to adjacent situations the rule doesn't explicitly cover.
- Example: Instead of `"Never use git add ."`, write `"Stage files explicitly (never git add .) — blind staging can commit debug files, .DS_Store, or partial work that breaks other contributors."` Claude now understands *why* and will also avoid similar blind-commit patterns.

## 3. Structure with XML Tags

XML tags eliminate ambiguity when a prompt mixes instructions, context, examples, and variable inputs.

- Use consistent, descriptive tag names: `<rules>`, `<workflow>`, `<output_format>`, `<conventions>`, `<constraints>`.
- Nest tags when content has natural hierarchy (e.g., `<workflow>` containing `<phase>` blocks).
- VBW already uses this pattern well in agent definitions. Maintain it — don't regress to flat prose for structured content.
- Wrap examples in `<example>` tags (multiple in `<examples>`) so Claude distinguishes them from instructions.

**VBW convention**: Agent definitions use `<rules>`, `<workflow>`, `<output_format>`, `<conventions>`. Command definitions use YAML frontmatter + markdown body. Keep these patterns consistent across new artifacts.

## 4. Use Examples Effectively

Few-shot (multishot) examples are the most reliable way to steer output format, tone, and structure. 3–5 diverse examples dramatically improve consistency.

- Make examples **relevant** (mirror your actual use case), **diverse** (cover edge cases), and **structured** (wrap in `<example>` tags, multiples in `<examples>`).
- Examples are especially valuable for output format guidance — showing the expected structure is more reliable than describing it.
- Ask Claude to evaluate your examples for relevance and diversity, or to generate additional ones from your initial set.

**VBW application**: When defining agent output formats (e.g., QA report structure, plan format), include 1-2 concrete examples inside `<example>` tags rather than relying solely on prose descriptions of the expected format. The `<plan_style_guide>` in fix-planner is a good model — it shows the structure rather than just describing it.

## 5. Set Roles Precisely

A role statement in the opening line focuses behavior and tone.

- One sentence is sufficient: "You are a read-only QA investigator" or "You are the FIX-PLANNER for the VBW plugin."
- The role should name the specific responsibility and any key constraint (read-only, no edits, planning only).
- Avoid generic roles like "You are a helpful assistant." Name the domain and responsibility.

## 6. Order Content for Long Context

Document placement affects comprehension. For prompts with substantial reference material:

- Put longform data (file contents, large context blocks, reference material) near the **top**.
- Put the query, task instructions, and output format near the **bottom**.
- This ordering can improve response quality by up to 30% on complex, multi-document inputs.

**VBW application**: In compiled context files (`.context-{role}.md`), place project state and file contents above the role-specific instructions and task directives.

## 7. Control Output Format

Steer output formatting with positive instructions, not prohibitions.

- **Tell Claude what to do instead of what not to do**: "Your response should be composed of smoothly flowing prose paragraphs" is more effective than "Do not use markdown."
- **Use XML format indicators**: Wrapping expected output in descriptive tags (e.g., `<smoothly_flowing_prose_paragraphs>`) reinforces structure.
- **Match prompt style to desired output**: The formatting in your prompt influences the response style. If you want structured output, use structured formatting in the prompt. If you want prose, write your prompt in prose.

**VBW application**: Agent output format sections (`<output_format>`) should specify what the output SHOULD look like, not list formatting to avoid. Use the plan style guide and QA report format as templates — they show the desired structure directly.

## 8. Steer Communication Style

Opus 4.6 is more concise and direct than previous models. It may skip verbal summaries after tool calls, jumping directly to the next action.

- If you need visibility into Agent reasoning or progress, explicitly request it: "After completing a task that involves tool use, provide a quick summary of the work you've done."
- If the model is too verbose, no action needed — this is the new default.

**VBW application**: VBW agents that produce structured reports (QA investigator, fix-planner) already specify output format explicitly, which overrides the default conciseness. For agents that perform multi-step work silently, consider whether a progress summary instruction is needed.

## 9. Calibrate Prompting Intensity for Opus 4.6

Claude Opus 4.6 is significantly more proactive than previous models. Instructions written for older models often cause overtriggering.

- **Replace aggressive language**: "CRITICAL: You MUST use this tool" → "Use this tool when it would enhance your understanding of the problem."
- **Remove blanket defaults**: "Default to using [tool]" → "Use [tool] when [specific condition]."
- **Remove anti-laziness nudges**: "If in doubt, use [tool]" will now cause excessive tool use. Remove these.
- **Use `(NON-NEGOTIABLE)` sparingly**: Reserve for genuinely critical invariants (zero-tolerance test policy, root-cause-only fixes). If everything is non-negotiable, nothing is.

**Test for over-prompting**: If removing an instruction doesn't change Claude's behavior, the instruction was unnecessary. Cut it.

## 10. Use Explicit Action Language

Claude distinguishes between being asked to "suggest" vs. "implement." If you want action, use action language.

- "Change this function to improve performance" triggers edits. "Can you suggest improvements?" may only produce commentary.
- For agents that should default to acting, include explicit framing: "By default, implement changes rather than only suggesting them. If the user's intent is unclear, infer the most useful likely action and proceed."
- For agents that should be conservative (read-only, planning-only), use the opposite: "Do not jump into implementation unless clearly instructed to make changes."

**VBW application**: fix-issue should use action-default language. fix-planner and qa-investigator should use conservative language since they are planning/read-only. Check that the language matches the agent's role.

## 11. Guide Subagent Orchestration

Claude Opus 4.6 proactively delegates to subagents without being told. This is useful but can be excessive.

- Specify when subagents are warranted vs. when direct work is sufficient:
  - **Use subagents for**: parallel independent tasks, isolated context needs, investigation that would clutter main context.
  - **Work directly for**: single-file edits, sequential operations, tasks needing shared state across steps.
- Watch for unnecessary subagent spawning on simple tasks where a direct search or read is faster and cheaper.

## 12. Guide Thinking and Reasoning

Opus 4.6 does significantly more upfront exploration than previous models. This can be helpful but also inflates thinking tokens.

- **Choose and commit**: "When deciding how to approach a problem, choose an approach and commit to it. Avoid revisiting decisions unless you encounter new information that directly contradicts your reasoning."
- **Self-check**: "Before you finish, verify your answer against [test criteria]." This catches errors reliably, especially for coding.
- **Prefer general instructions over prescriptive steps**: A prompt like "think thoroughly" often produces better reasoning than a hand-written step-by-step plan. Claude's reasoning frequently exceeds what a human would prescribe.
- If thinking is excessive, use targeted guidance rather than prescriptive step-by-step reasoning chains.

**VBW application**: For VBW agents with multi-step workflows (fix-issue, fix-planner), the workflow steps provide structure but each step should allow Claude to reason freely within it rather than micro-managing the approach. Self-check instructions are especially valuable for QA rounds.

## 13. Control Overeagerness

Claude Opus 4.6 tends to over-engineer — adding features, abstractions, and defensive code beyond what was requested.

- Scope instructions precisely: "Only make changes that are directly requested or clearly necessary."
- Forbid speculative additions: no extra features, no refactoring adjacent code, no defensive handling for impossible scenarios.
- Don't add docstrings, comments, or type annotations to code you didn't change.
- Don't create helpers or abstractions for one-time operations.

**VBW application**: When writing command or agent instructions, constrain the agent's scope explicitly. A QA agent should review the change, not audit the entire codebase. A fix agent should fix the reported issue, not improve surrounding code.

## 14. Write General Solutions, Not Test-Specific Ones

Claude can focus too heavily on making tests pass at the expense of general solutions, or may hard-code values for specific test inputs.

- Instruct agents to "implement a solution that works correctly for all valid inputs, not just the test cases."
- "Tests are there to verify correctness, not to define the solution."
- If a task is unreasonable or tests are incorrect, the agent should report it rather than work around it.

**VBW application**: VBW's fix-issue agent already has "root-cause fixes only" and "forbidden fix patterns" guidance. This reinforces the same principle from the testing angle — ensure contract tests (`verify-*.sh`) validate the general pattern, not just the specific failing example.

## 15. Manage Long-Horizon State

Claude excels at tracking state across extended sessions and multiple context windows.

- **Use structured formats for state data**: JSON or structured files for test results, task status, and tracked items. Claude understands schema requirements from structured data.
- **Use unstructured text for progress notes**: Freeform notes work well for tracking general progress and context across sessions.
- **Use git for state tracking**: Git provides a log of what's been done and checkpoints that can be restored. Claude performs especially well using git to track state.
- **Context awareness**: Claude can track its remaining context window. If the agent harness supports compaction, tell Claude explicitly so it doesn't try to wrap up work prematurely: "Your context window will be automatically compacted as it approaches its limit, allowing you to continue working indefinitely."

**VBW application**: VBW's `.vbw-planning/` state model (STATE.md, ROADMAP.md, phase directories) already follows these patterns. When writing agent instructions that interact with state, reference the structured format and instruct agents to update it incrementally rather than rewriting from scratch.

## 16. Balance Autonomy and Safety

Without guidance, Opus 4.6 may take actions that are difficult to reverse or affect shared systems.

- Frame safety in terms of **reversibility and impact**: "Take local, reversible actions freely. For actions that are hard to reverse, affect shared systems, or could be destructive, ask the user before proceeding."
- Provide concrete examples of actions requiring confirmation: deleting files/branches, force-pushing, dropping tables, posting to external services.
- Do not use destructive actions as shortcuts. Do not bypass safety checks (e.g., `--no-verify`).

**VBW application**: VBW already has `destructive-commands.txt` and safety guards. When writing agent instructions, include the reversibility framing so the agent can generalize beyond the explicit list to novel destructive scenarios.

## 17. Structure Research Tasks

For agents that gather information before acting (fix-planner, scouts):

- Define clear success criteria for the research question.
- Use a structured approach: develop competing hypotheses, track confidence levels, self-critique.
- Encourage iterative refinement: gather data → form hypotheses → test against evidence → refine.

**VBW application**: fix-planner's Discovery phase should follow this pattern — hypothesizing root causes, gathering evidence, and refining before committing to a plan. Scout agents should track what they've found vs. what remains unknown.

## 18. Use Self-Correction Chains

The most effective pattern for quality work: generate a draft → review against criteria → refine based on review.

- Each step can be a separate agent invocation for inspection and branching at each point.
- VBW's QA loop (fix-issue Phase 3) is a direct implementation of this pattern: implement → QA review → fix → re-review.
- When designing new multi-step workflows, build in the review-and-refine step rather than assuming first-pass output is final.

## 19. Require Cleanup of Temporary Files

Claude may create temporary files for testing and iteration. If this is undesirable:

- "If you create any temporary new files, scripts, or helper files for iteration, clean up these files by removing them at the end of the task."

**VBW application**: fix-issue and dev agents that run tests should clean up any temporary test fixtures, scratch files, or debug output before committing. Include this instruction when the agent has write access.

## 20. Require Investigation Before Claims

Claude can hallucinate about code it hasn't read. The `<investigate_before_answering>` pattern prevents this.

```xml
<investigate_before_answering>
Never speculate about code you have not opened. If a file is referenced
in the issue or diff, you MUST read it before reporting findings about it.
Make sure to investigate and read relevant files BEFORE drawing conclusions
about the codebase.
</investigate_before_answering>
```

**VBW application**: Include this pattern (or equivalent) in any agent that makes claims about code behavior — especially QA agents, debuggers, and planners. VBW's qa-investigator already has this; ensure new agents follow the same pattern.

## 21. Design Verification Into Instructions

Claude performs dramatically better when it can verify its own work. Build verification into task instructions, not as an afterthought.

- Specify concrete verification steps: run tests, check exit codes, compare before/after state.
- Prefer automated verification (test commands, lint checks) over manual inspection.
- "Address root causes, not symptoms" — include instructions to verify the root cause is fixed, not just the surface symptom.

**VBW convention**: The three-tier testing model (BATS for scripts, contract tests for structure, smoke tests for LLM behavior) should be referenced in any agent that produces testable output.

## 22. Optimize Parallel Tool Calling

Claude excels at parallel execution when guided properly.

- State the parallelism rule once: "If you intend to call multiple tools and there are no dependencies between the calls, make all independent calls in parallel."
- State the dependency rule: "If calls depend on previous results, execute them sequentially. Never use placeholders or guess missing parameters."
- For VBW agents that do multi-file investigation, explicitly note which lookups can run in parallel (e.g., "search for callers in parallel") vs. which depend on prior results.

## 23. CLAUDE.md and Skills Authoring

When VBW generates or modifies CLAUDE.md content (via `bootstrap-claude.sh` or `check-claude-md-staleness.sh`):

- **Keep it concise**: For each line, ask "Would removing this cause Claude to make mistakes?" If not, cut it. Bloated CLAUDE.md files cause Claude to ignore your actual instructions.
- **Only include what Claude can't infer**: Don't describe standard language conventions Claude already knows. Include project-specific commands, non-obvious workflows, and architectural decisions.
- **Avoid staleness**: Don't include information that changes frequently. Link to docs instead.
- **Treat like code**: Review when things go wrong, prune regularly, test changes by observing behavior.

For skills (`SKILL.md` files):
- Use for domain knowledge or workflows that are only relevant sometimes. Claude loads them on demand.
- Set `disable-model-invocation: true` for workflows with side effects that should only trigger manually.
- Don't duplicate CLAUDE.md content in skills — skills are for specialized knowledge, not general project conventions.

## 24. Point to Existing Patterns as Reference Anchors

When an agent needs to produce something that follows an existing pattern, point to a concrete example rather than describing the pattern abstractly.

- "Look at how existing widgets are implemented. HotDogWidget.php is a good example. Follow the pattern."
- Reference specific functions, types, or files — not just directory names.
- This is more reliable than describing the pattern in prose, because Claude reads the actual implementation and generalizes from it.

**VBW application**: When writing agent instructions that produce new artifacts (commands, agents, templates, scripts), reference an existing well-structured example by path. For new commands, "follow the structure of `commands/status.md`" is better than describing the YAML frontmatter + markdown body pattern from scratch. For new scripts, "follow the conventions in `scripts/compile-context.sh`" grounds the agent in real code.

## 25. Design Instructions for Context Efficiency

Context is the fundamental constraint. LLM performance degrades as context fills. Every file read, command output, and conversation turn consumes tokens.

- **Write concise instructions**: Every word in an agent definition or command template is loaded into context. Ruthlessly prune prose that doesn't change behavior.
- **Scope investigations**: Unbounded "investigate everything" instructions cause Claude to read hundreds of files, filling context with irrelevant content. Always scope: "search for callers of `functionX` in `scripts/`" rather than "investigate the codebase."
- **Use subagents for exploration**: Subagents run in separate context windows and report back summaries, keeping the main agent's context clean for implementation.
- **Separate research from execution**: A fresh context with a clear plan (from a prior session or subagent) outperforms a long session with accumulated investigation context.

**VBW application**: VBW's context compilation (`compile-context.sh`) already follows this — producing role-specific context files so each agent loads only what it needs. When writing new agent instructions, prefer directing agents to specific files/paths over broad exploration. fix-planner's handoff to fix-issue via `/memories/session/plan.md` embodies the "separate research from execution" pattern.

## 26. Avoid Common Anti-Patterns

Recognizing failure patterns early saves tokens and improves output quality. Design agent instructions to prevent these:

- **The kitchen sink session**: Mixing unrelated tasks in one context. Context fills with irrelevant information and performance degrades. **Prevention**: VBW agents should have clear scope boundaries. QA investigates the change, not the codebase. Planners plan, not implement.
- **The over-correction loop**: Claude does something wrong, you correct it, it's still wrong, you correct again. Context is polluted with failed approaches. **Prevention**: After two failed corrections, instruct a fresh start with a better initial prompt incorporating lessons learned. VBW's QA loop handles this by spawning fresh sub-agent invocations per round.
- **The over-specified instruction set**: If instructions are too long, important rules get lost in noise. Claude ignores half of them. **Prevention**: For each instruction line, ask "Would removing this cause Claude to make mistakes?" If not, cut it. Prefer hooks (deterministic) over instructions (advisory) for critical behaviors.
- **The infinite exploration**: Asking Claude to "investigate" without scoping it. Claude reads hundreds of files, filling context. **Prevention**: Scope investigations narrowly. Use subagents so exploration doesn't consume the main agent's context. VBW's fix-planner uses Explore subagents for exactly this reason.
- **The trust-then-verify gap**: Claude produces plausible-looking output that doesn't handle edge cases. **Prevention**: Always provide verification (tests, lint, exit code checks). If you can't verify it, don't ship it. VBW's three-tier testing model and QA loop address this structurally.
