#!/usr/bin/env bats

# Tests for discovered issues surfacing across commands and agents
# Issue #98: Pre-existing test failures silently dropped by /vbw:fix, /vbw:debug, /vbw:qa

load test_helper

# =============================================================================
# Dev agent: DEVN-05 Pre-existing deviation code
# =============================================================================

@test "dev agent has DEVN-05 Pre-existing deviation code" {
  grep -q 'DEVN-05' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent DEVN-05 action is note and do not fix" {
  grep 'DEVN-05' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'do not fix'
}

@test "dev agent has pre-existing failure guidance after Stage 2" {
  grep -q 'Pre-existing failures (DEVN-05)' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent pre-existing guidance requires Pre-existing Issues heading" {
  # Find the DEVN-05 section (multi-paragraph) up to the next heading
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'Pre-existing Issues'
}

@test "dev agent pre-existing guidance says never fix them" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qiE 'never.*(fix|attempt).*pre-existing|do not fix pre-existing'
}

@test "dev agent DEVN-05 uncertainty fallback disambiguates from table default" {
  # The DEVN-05 section must clarify DEVN-03 fallback vs DEVN-04 table default
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'DEVN-04'
}

@test "dev agent deviation table has all 5 DEVN codes" {
  for code in DEVN-01 DEVN-02 DEVN-03 DEVN-04 DEVN-05; do
    grep -q "$code" "$PROJECT_ROOT/agents/vbw-dev.md" || { echo "Missing $code"; return 1; }
  done
}

@test "dev agent deviation table has Default DEVN-04 when unsure" {
  grep -qi 'Default.*DEVN-04.*when unsure' "$PROJECT_ROOT/agents/vbw-dev.md"
}

# =============================================================================
# Fix command: discovered issues output
# =============================================================================

@test "fix command prompt instructs Dev to report pre-existing failures" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command prompt mentions pre-existing failures in spawn block" {
  # The spawn prompt template must tell Dev about pre-existing reporting
  sed -n '/^4\./,/^5\./p' "$PROJECT_ROOT/commands/fix.md" | grep -q 'pre-existing'
}

@test "fix command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/fix.md"
}

# =============================================================================
# Debug command: discovered issues output
# =============================================================================

@test "debug command Path B prompt instructs reporting pre-existing failures" {
  # Path B spawn prompt must mention pre-existing
  sed -n '/Path B/,/^[0-9]\./p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command Path A prompt instructs reporting pre-existing failures" {
  # Path A task creation must mention pre-existing
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command Path A has de-duplication instruction" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'de-duplicate'
}

@test "debug command Path A dedup key includes file" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'test name and file'
}

# =============================================================================
# Debugger agent: pre-existing failure handling
# =============================================================================

@test "debugger agent has pre-existing failure handling section" {
  grep -q 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent classifies unrelated failures as pre-existing" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -qi 'pre-existing'
}

@test "debugger agent does not fix pre-existing failures" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -qi 'do not.*fix pre-existing'
}

@test "debugger agent mentions pre_existing_issues in debugger_report" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -q 'pre_existing_issues'
}

@test "debugger agent references debugger_report schema" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -q 'debugger_report'
}

@test "debugger agent Step 7 output includes pre-existing issues" {
  # Match the Investigation Protocol step 7 line specifically
  sed -n '/Investigation Protocol/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep '7\.' | grep -q 'pre-existing'
}

# =============================================================================
# Handoff schema: debugger_report is a proper schema type
# =============================================================================

@test "handoff schema has dedicated debugger_report section" {
  grep -q '## `debugger_report`' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff schema debugger_report uses correct type in JSON" {
  sed -n '/## .debugger_report/,/^## /p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"type": "debugger_report"'
}

@test "handoff schema blocker_report section does not mention debugger" {
  # Extract blocker_report section up to but not including the debugger_report heading
  local section
  section=$(sed -n '/## .blocker_report/,/^## .debugger_report/{ /^## .debugger_report/d; p; }' "$PROJECT_ROOT/references/handoff-schemas.md")
  run grep -qi 'debugger' <<< "$section"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Debugger report schema: pre_existing_issues field
# =============================================================================

@test "handoff schema documents pre_existing_issues field" {
  grep -q 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff schema pre_existing_issues has test/file/error structure" {
  grep -A2 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"test"'
}

@test "qa_verdict schema includes pre_existing_issues field" {
  sed -n '/qa_verdict/,/^##/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

@test "json schema blocker_report payload_optional includes pre_existing_issues" {
  jq -r '.schemas.blocker_report.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema qa_verdict payload_optional includes pre_existing_issues" {
  jq -r '.schemas.qa_verdict.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema execution_update payload_optional includes pre_existing_issues" {
  jq -r '.schemas.execution_update.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "handoff schema execution_update example includes pre_existing_issues" {
  sed -n '/execution_update/,/^##/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Dev agent: structured protocol for pre_existing_issues
# =============================================================================

@test "dev agent Communication section references pre_existing_issues in execution_update" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'pre_existing_issues'
}

@test "dev agent Communication section references execution_update payload" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'execution_update'
}

# =============================================================================
# Dev agent: DEVN-05 test vs build distinction
# =============================================================================

@test "dev agent DEVN-05 specifies test failures not build errors" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'test.*failure'
}

@test "dev agent DEVN-05 distinguishes modified vs unmodified file errors" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'compile.*lint.*build'
}

@test "dev agent DEVN-05 covers unmodified file errors" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'unmodified.*files'
}

@test "dev agent DEVN-05 uses decision tree format" {
  # Verify the structured numbered steps exist
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q '1\. \*\*Is the failure'
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q '2\. \*\*Is the failure'
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q '3\. \*\*When DEVN-05'
}

@test "dev agent DEVN-05 read-only methods include git commands" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'git log.*git show.*git blame'
}

@test "dev agent Stage 2 cross-references DEVN-05 exception" {
  sed -n '/### Stage 2/,/### Stage 3/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'except.*pre-existing.*DEVN-05'
}

@test "dev agent DEVN-05 prohibits working-tree mutations for classification" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'do NOT check out other branches'
}

@test "dev agent Communication references execution_update not blocker_report for pre_existing_issues" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'execution_update'
  # Should NOT reference blocker_report as the structure source
  ! sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'same.*structure as.*blocker_report'
}

# =============================================================================
# QA agent: pre-existing failure baseline awareness
# =============================================================================

@test "qa agent has pre-existing failure handling section" {
  grep -q 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "qa agent classifies unrelated failures as pre-existing" {
  grep -A5 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -qi 'pre-existing'
}

@test "qa agent pre-existing failures do not influence verdict" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -qi 'NOT influence.*PASS.*FAIL.*PARTIAL'
}

@test "qa agent requires Pre-existing Issues heading in response" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -q 'Pre-existing Issues'
}

@test "qa agent mentions pre_existing_issues in qa_verdict payload" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Lead agent: pre-existing issue aggregation
# =============================================================================

@test "lead agent has pre-existing issue aggregation section" {
  grep -q 'Pre-Existing Issue Aggregation' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "lead agent aggregation mentions execution_update" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'execution_update'
}

@test "lead agent aggregation mentions qa_verdict" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'qa_verdict'
}

@test "lead agent aggregation mentions de-duplicate" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -qi 'de-duplicate'
}

@test "lead agent aggregation specifies merge strategy for duplicate errors" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -qi 'first.*error.*message'
}

@test "debug command Path A dedup specifies merge strategy" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'first error message'
}

@test "execute-protocol discovered issues specifies merge strategy" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -qi 'first.*error.*message'
}

@test "execute-protocol discovered issues caps list size" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -qi 'cap.*20'
}

@test "lead agent aggregation mentions debugger_report" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'debugger_report'
}

@test "lead agent aggregation specifies JSON output format" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q '{test, file, error}'
}

# =============================================================================
# Execute-protocol: display format specification
# =============================================================================

@test "execute-protocol discovered issues specifies bullet display format" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -q 'testName.*path.*error'
}

# =============================================================================
# Debug command: schema naming consistency
# =============================================================================

@test "debug command Path A uses debugger_report schema" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'debugger_report'
}

@test "debug command Path A does not reference blocker_report for debugger" {
  ! sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'blocker_report'
}

@test "json schema has dedicated debugger_report type" {
  jq -e '.schemas.debugger_report' "$PROJECT_ROOT/config/schemas/message-schemas.json" > /dev/null
}

@test "json schema debugger_report requires hypothesis and evidence fields" {
  jq -r '.schemas.debugger_report.payload_required[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'hypothesis'
  jq -r '.schemas.debugger_report.payload_required[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'evidence_for'
}

@test "json schema debugger_report payload_optional includes pre_existing_issues" {
  jq -r '.schemas.debugger_report.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema blocker_report does not list debugger as allowed role" {
  ! jq -r '.schemas.blocker_report.allowed_roles[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger'
}

@test "json schema debugger can send debugger_report" {
  jq -r '.role_hierarchy.debugger.can_send[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger_report'
}

@test "json schema lead can receive debugger_report" {
  jq -r '.role_hierarchy.lead.can_receive[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'debugger_report'
}

# =============================================================================
# VERIFICATION.md format: pre-existing issues section
# =============================================================================

@test "qa agent VERIFICATION.md format includes Pre-existing Issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "verification template has Pre-existing Issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/templates/VERIFICATION.md"
}

@test "verification template Pre-existing Issues has Test/File/Error columns" {
  sed -n '/Pre-existing Issues/,/^##/p' "$PROJECT_ROOT/templates/VERIFICATION.md" | grep -q 'Test.*File.*Error'
}

# =============================================================================
# QA command: discovered issues output + schema consistency
# =============================================================================

@test "qa command references qa_verdict schema not qa_result" {
  # qa_verdict is the canonical schema name; qa_result was a historical mismatch
  ! grep -q 'qa_result' "$PROJECT_ROOT/commands/qa.md"
  grep -q 'qa_verdict' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command spawn prompt reinforces pre-existing reporting" {
  sed -n '/Spawn QA/,/QA agent reads/p' "$PROJECT_ROOT/commands/qa.md" | grep -qi 'pre-existing'
}

# =============================================================================
# Dev agent: Circuit Breaker schema naming
# =============================================================================

@test "dev agent Circuit Breaker references blocker_report not dev_blocker" {
  sed -n '/Circuit Breaker/,/$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'blocker_report'
}

@test "dev agent Circuit Breaker does not reference non-existent dev_blocker schema" {
  ! sed -n '/Circuit Breaker/,/$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'dev_blocker'
}

# =============================================================================
# Execute-protocol: de-duplication for Discovered Issues
# =============================================================================

@test "execute-protocol discovered issues has de-duplication instruction" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -qi 'de-duplicate'
}

# =============================================================================
# Verify command: discovered issues scoped to user-reported
# =============================================================================

@test "verify command discovered issues flow into remediation" {
  grep -qi 'flow into remediation' "$PROJECT_ROOT/commands/verify.md"
}

# =============================================================================
# Verify command: discovered issues output
# =============================================================================

@test "verify command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues recorded in UAT.md" {
  grep -qi 'recorded in the UAT.md' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues uses D{NN} IDs" {
  grep -q 'D{NN}' "$PROJECT_ROOT/commands/verify.md"
}

# =============================================================================
# Consistency: all discovered issues blocks use the same format
# =============================================================================

@test "execute-protocol still has discovered issues section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "all discovered issues sections use display-only constraint" {
  local failed=""
  # verify.md is excluded — its discovered issues flow into remediation via UAT.md, not display-only
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q 'display-only' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing display-only in:$failed"; return 1; }
}

@test "all discovered issues sections suggest /vbw:todo" {
  local failed=""
  # verify.md is excluded — its discovered issues flow into remediation via UAT.md
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q '/vbw:todo' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing /vbw:todo in:$failed"; return 1; }
}

# =============================================================================
# Blocker report: pre_existing_issues documented in reference
# =============================================================================

@test "handoff schema blocker_report example includes pre_existing_issues" {
  sed -n '/## .blocker_report/,/^## .debugger_report/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Bullet format consistency across entry points
# =============================================================================

@test "all discovered issues sections specify testName format" {
  local failed=""
  # verify.md is excluded — uses D{NN} format for UAT remediation, not testName format
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q 'testName.*path/to/file.*error' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing testName format in:$failed"; return 1; }
}

# =============================================================================
# Display-only STOP constraint
# =============================================================================

@test "all discovered issues sections include STOP after display" {
  local failed=""
  # verify.md is excluded — its discovered issues flow into remediation, no STOP needed
  for file in commands/fix.md commands/debug.md commands/qa.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'STOP.*Do not take further action' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing STOP constraint in:$failed"; return 1; }
}

# =============================================================================
# Debugger standalone: structured pre-existing format
# =============================================================================

@test "debugger agent standalone Step 7 specifies structured pre-existing format" {
  sed -n '/Investigation Protocol/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep '7\.' | grep -q 'test, file, error'
}

# =============================================================================
# QA round 2: consistency fixes
# =============================================================================

@test "execute-protocol discovered issues includes STOP after display" {
  sed -n '/Discovered Issues/,/suggest-next/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -qi 'STOP.*Do not take further action'
}

@test "all discovered issues sections have de-duplication instruction" {
  local failed=""
  # verify.md is excluded — uses D{NN} sequential IDs, dedup not applicable
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'de-duplicate\|De-duplicate' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing de-duplication in:$failed"; return 1; }
}

@test "all discovered issues sections have cap at 20" {
  local failed=""
  # verify.md is excluded — UAT test count is naturally bounded by generated tests
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -qi 'cap.*20\|Cap.*20' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing cap at 20 in:$failed"; return 1; }
}

@test "verify command freeform handles pass-intent with observation" {
  grep -qi 'pass-intent.*observation\|pass-intent with observation' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command freeform lists all pass-intent words" {
  # Validate every pass-intent word is listed
  for word in pass passed 'looks good' works correct confirmed yes good fine ok; do
    grep -qi "$word" "$PROJECT_ROOT/commands/verify.md" || { echo "Missing pass-intent word: $word"; return 1; }
  done
}

@test "verify command freeform handles skip-intent with observation" {
  grep -qi 'skip-intent.*observation\|skip-intent with observation' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command freeform specifies whole-word matching" {
  grep -qi 'whole word' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command skip button-selected captures observations" {
  # Step 5 skip path should mention discovered issue / Step 6a
  sed -n '/\*\*"Skip" selected:\*\*/,/\*\*Freeform/p' "$PROJECT_ROOT/commands/verify.md" | grep -qi 'discovered issue\|Step 6a\|observation'
}

@test "verify command D{NN} resume scans existing entries" {
  grep -qi 'scan existing.*D{NN}\|highest existing number\|max+1' "$PROJECT_ROOT/commands/verify.md"
}

@test "dev agent DEVN-05 has priority rule for overlapping uncertainty" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^### /p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'DEVN-03 wins'
}

@test "dev agent Communication section references handoff-schemas.md without circular self-reference" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'handoff-schemas.md'
  # Should not contain "same structure as defined in execution_update" (circular)
  ! sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'same.*structure as defined in.*execution_update'
}

# =============================================================================
# QA round 3 (PR #142): behavior assertions for verify response mapping
# =============================================================================

@test "verify response mapping treats idiomatic positive 'not bad' as pass" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "not bad"
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "verify response mapping handles curly apostrophe in can't complain" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "can’t complain"
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "verify response mapping catches non-adjacent negation scope" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "I don't think it works"
  [ "$status" -eq 0 ]
  [ "$output" = "issue" ]
}

@test "verify response mapping prefers skip when current checkpoint is explicitly deferred" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "Pass overall, but skip this checkpoint for now"
  [ "$status" -eq 0 ]
  [ "$output" = "skip" ]
}

@test "verify response mapping does not create false observation from positive separator text" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "pass: looks great"
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "verify response mapping classifies pass with defect observation" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "pass, but the sidebar is broken"
  [ "$status" -eq 0 ]
  [ "$output" = "pass_with_observation" ]
}

@test "verify response mapping classifies skip with defect observation" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "skip, but the sidebar is broken"
  [ "$status" -eq 0 ]
  [ "$output" = "skip_with_observation" ]
}

@test "verify response mapping falls back to issue for unmatched freeform" {
  run bash "$PROJECT_ROOT/scripts/map-verify-response.sh" "kinda flaky and weird"
  [ "$status" -eq 0 ]
  [ "$output" = "issue" ]
}

@test "verify command documents idiomatic positives and issue-signal guard" {
  grep -qi 'Idiomatic-positive exceptions' "$PROJECT_ROOT/commands/verify.md"
  grep -qi 'Observation extraction guard' "$PROJECT_ROOT/commands/verify.md"
}

# =============================================================================
# QA round 4 (PR #142): newline-separated input via stdin
# =============================================================================

@test "verify response mapping handles newline between pass and issue observation via stdin" {
  result=$(printf 'pass\nbut the sidebar is broken' | bash "$PROJECT_ROOT/scripts/map-verify-response.sh")
  [ "$result" = "pass_with_observation" ]
}

@test "verify response mapping handles newline between skip and issue observation via stdin" {
  result=$(printf 'skip\nbut there is a bug' | bash "$PROJECT_ROOT/scripts/map-verify-response.sh")
  [ "$result" = "skip_with_observation" ]
}

@test "verify response mapping handles newline-only pass via stdin" {
  result=$(printf 'looks good\nno issues' | bash "$PROJECT_ROOT/scripts/map-verify-response.sh")
  [ "$result" = "pass" ]
}
