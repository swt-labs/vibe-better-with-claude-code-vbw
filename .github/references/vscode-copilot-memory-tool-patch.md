# Reapplying the VS Code Copilot memory tool patch

This note records the exact investigation and patch used to fix a GPT-5.4 planning session bug where the agent sometimes received `resolveMemoryFileUri` but not the writable `memory` tool.

The point of this document is simple: if VS Code Insiders updates and overwrites the local bundle patch, this gives you a clean way to redo it without re-deriving the whole thing from scratch.

## What was wrong

Observed behavior:

- Claude-backed sessions could write memory.
- Some GPT-5.4 planning sessions could resolve memory file URIs but could not write memory.
- In those GPT-5.4 cases, the tool list exposed `resolve_memory_file_uri` without exposing `memory`.

That made the planner behave as if writable memory was unavailable even though the Copilot extension clearly shipped a memory tool.

## What I verified before changing anything

I did not start by patching prompts. I first checked whether the built-in Copilot extension actually contained the missing tool.

### 1. The writable memory tool exists in the built-in Copilot extension

Relevant extension:

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/package.json`

Relevant contributed tools found there:

- `copilot_memory`
- `copilot_resolveMemoryFileUri`

Relevant tool set found there:

- `languageModelToolSets[4]` named `vscode`
- that tool set includes both `memory` and `resolveMemoryFileUri`

This ruled out the simplest theory that GPT-5.4 lacked a writable memory tool entirely.

### 2. The memory tool is implemented in the runtime bundle

Relevant runtime bundle:

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js`

What I confirmed in that bundle:

- the memory implementation exists
- the implementation uses `toolName="memory"`
- the implementation marks the tool as non-deferred

That ruled out a second theory: the tool was not missing because its implementation forgot to register itself or forgot to declare itself non-deferred.

### 3. Real session logs showed inconsistent exposure

I inspected Copilot debug artifacts under:

- `~/Library/Application Support/Code - Insiders/User/workspaceStorage/*/GitHub.copilot-chat/debug-logs/*/tools_0.json`
- companion request logs in `main.jsonl`

Those logs showed a real split:

- some sessions had `resolve_memory_file_uri` only
- some had `memory` only
- some had both

That mattered because it showed the bug was not theoretical. The agent runtime was actually exposing different tool sets across sessions.

### 4. The key mismatch was in tool grouping, not tool existence

The crucial runtime map in `extension.js` classified tools into groups. Before the patch, the relevant entries were effectively:

- `memory:"VS Code Interaction"`
- `resolve_memory_file_uri:"Core"`

That split explains the symptom.

If a request path started with Core tools but did not also activate the VS Code Interaction group, the session could get the URI resolver without getting the writable memory tool.

## Root cause

The bug was not in:

- the GitHub Pull Requests extension
- the VBW repo
- the planner prompt
- the existence of the memory tool itself

The bug was in the built-in Copilot Chat runtime bundle.

More precisely:

- `resolve_memory_file_uri` was treated as a Core tool
- `memory` was treated as a VS Code Interaction tool

That grouping mismatch was enough to create sessions where GPT-5.4 could resolve memory paths but could not write memory.

## Primary fix that was applied

I patched the built-in Copilot bundle so `memory` is classified as a Core tool.

### Patched file

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js`

### Backup created

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js.bak-memory-core`

### Exact semantic change

Old behavior:

- `memory:"VS Code Interaction"`

New behavior:

- `memory:"Core"`

Nothing else was changed in the runtime bundle.

## Why this patch is the right one

This fix targets the actual place where the bug is introduced.

It does not rely on:

- planner prompt wording
- agent-specific workarounds
- a second activation step
- model-specific prompt tricks

It fixes the runtime classification so `memory` and `resolve_memory_file_uri` can appear together in the default Core path.

## What not to patch

Do not start by patching these as the main fix:

- `~/.vscode-insiders/extensions/github.vscode-pull-request-github-*`
- VBW agent prompt files
- planner instructions that try to activate extra tool groups

Those can be fallback workarounds. They are not the root-cause fix.

## Redo procedure after a VS Code or Copilot update

Use this section when an update overwrites the patched bundle.

### Step 0: close the loop you are trying to fix

Before changing anything, confirm the symptom still exists in a fresh GPT-5.4 session:

- the session gets `resolveMemoryFileUri`
- the session does not get `memory`
- the setting `github.copilot.chat.tools.memory.enabled` is still enabled

If the setting is disabled, turn it back on first. The patch is not meant to bypass a disabled feature flag.

### Step 1: verify the built-in Copilot extension still ships the memory tool

Inspect:

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/package.json`

Confirm all of the following still exist:

- `copilot_memory`
- `copilot_resolveMemoryFileUri`
- the `vscode` tool set includes both `memory` and `resolveMemoryFileUri`

If any of those are gone, stop. The upstream architecture changed and this exact patch may no longer apply.

### Step 2: verify the runtime bundle still contains the memory implementation

Inspect:

- `/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js`

Confirm the runtime still contains a memory tool implementation with:

- `toolName="memory"`
- a non-deferred marker for that tool

If those are gone, stop and re-investigate. That means the runtime wiring changed enough that the old patch target is stale.

### Step 3: confirm the bad grouping still exists

In `extension.js`, look for the tool grouping map that includes both of these entries:

- `memory:"VS Code Interaction"`
- `resolve_memory_file_uri:"Core"`

If you already see:

- `memory:"Core"`

then one of two things is true:

- the patch is already applied, or
- upstream fixed it

In that case, do not patch again.

### Step 4: create a fresh backup

Before editing the runtime bundle, create a timestamped or named backup.

Recommended backup path:

```text
/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js.bak-memory-core
```

If that backup name already exists and you want to preserve multiple versions, use a timestamped suffix.

### Step 5: apply the patch

Use a targeted replacement. Do not hand-edit the minified file unless you absolutely have to.

The safest repeatable approach is a tiny Node script that:

- reads the bundle
- verifies the old string exists exactly once
- verifies `resolve_memory_file_uri:"Core"` is also present
- writes a backup
- replaces only `memory:"VS Code Interaction"` with `memory:"Core"`

A reliable version:

```js
const fs = require("fs");

const file = "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/extensions/copilot/dist/extension.js";
const backup = `${file}.bak-memory-core`;
const oldNeedle = 'memory:"VS Code Interaction"';
const newNeedle = 'memory:"Core"';
const anchor = 'resolve_memory_file_uri:"Core"';

const src = fs.readFileSync(file, "utf8");

const matches = src.match(/memory:\"VS Code Interaction\"/g) || [];
if (matches.length !== 1) {
  throw new Error(`Expected exactly one memory grouping match, found ${matches.length}`);
}

if (!src.includes(anchor)) {
  throw new Error(`Expected anchor not found: ${anchor}`);
}

if (!fs.existsSync(backup)) {
  fs.copyFileSync(file, backup);
}

const next = src.replace(oldNeedle, newNeedle);
if (next === src) {
  throw new Error("Replacement did not change the file");
}

fs.writeFileSync(file, next);
console.log("Patched memory tool grouping to Core");
console.log(`Backup: ${backup}`);
```

If the exact string no longer exists, do not weaken the script into a broad search-and-replace. Re-investigate first.

### Step 6: validate the patch before reloading VS Code

Check all of the following:

- the bundle now contains `memory:"Core"`
- the bundle still contains `resolve_memory_file_uri:"Core"`
- the backup file exists

If the bundle contains multiple `memory:"VS Code Interaction"` instances after patching, the patch did not land cleanly.

### Step 7: reload VS Code Insiders

The patch does not affect an already-running chat session.

Reload the window or restart VS Code Insiders.

Then start a fresh GPT-5.4 planning session.

### Step 8: verify behavior in a fresh GPT-5.4 session

What you want to see in a new session:

- `memory` is available alongside `resolveMemoryFileUri`
- the planner can write `/memories/session/plan.md` without needing a prompt workaround

If you want hard proof, inspect the newest `tools_0.json` under the Copilot debug logs and confirm the session tool list includes `memory`.

## How I would re-investigate if the patch stops applying cleanly

If a future VS Code update changes the structure enough that the old string search fails, use this order of operations again:

1. Confirm the symptom in a fresh GPT-5.4 session.
2. Confirm `copilot_memory` still exists in `package.json`.
3. Confirm `copilot_resolveMemoryFileUri` still exists in `package.json`.
4. Confirm the `vscode` tool set still includes both logical tools.
5. Confirm the runtime still registers a tool named `memory`.
6. Confirm the runtime still classifies tools into groups and compare the group assigned to `memory` vs. `resolve_memory_file_uri`.
7. Only patch once you can point to the exact runtime mismatch.

That keeps the redo process tied to evidence instead of muscle memory.

## Rollback

If the patch causes trouble or upstream changes make it unsafe, restore the backup:

1. close VS Code Insiders
2. replace `extension.js` with `extension.js.bak-memory-core`
3. relaunch VS Code Insiders

If you created a timestamped backup instead, restore from that file instead of the generic backup name.

## Scope and limitations

This is a local machine patch.

That means:

- it is not portable across machines unless you repeat it there
- it can be overwritten by any VS Code Insiders or Copilot extension update
- it should be treated as a local runtime hotfix, not a permanent upstream solution

## Optional fallback if the runtime patch cannot be applied

Only if the runtime patch is impossible after an upstream change, use a prompt fallback that explicitly activates the VS Code interaction tool set before concluding that writable memory is unavailable.

That is a fallback only. It is not the preferred fix.

## Current patch target version

This investigation was done against:

- VS Code Insiders built-in Copilot Chat extension version `0.45.2026041604`

If the installed version changes, re-run the verification steps above before reapplying anything.
