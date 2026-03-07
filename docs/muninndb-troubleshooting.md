# MuninnDB Troubleshooting

Common issues and solutions for MuninnDB integration with VBW.

## Quick Diagnostics

```bash
# Full health check
bash scripts/muninn-setup.sh --check

# Or via VBW doctor
/vbw:doctor   # Check 16 covers MuninnDB
```

## Common Issues

### "MuninnDB: NOT RUNNING"

**Symptom:** Session start shows `⚠ MuninnDB: NOT RUNNING`. Agents fail on `muninn_activate` / `muninn_guide` calls.

**Fix:**
```bash
muninn start
```

If `muninn` is not found:
```bash
curl -fsSL https://muninndb.com/install.sh | sh
muninn init
muninn start
```

### "Vault not configured"

**Symptom:** Agents report `⚠ MuninnDB vault not configured`. Lead and Architect agents are blocked from spawning.

**Fix:** Set the vault in your project config:
```bash
/vbw:config muninndb_vault my-project-name
```

Or run the setup wizard:
```bash
bash scripts/muninn-setup.sh --vault
```

### "Vault not found on server"

**Symptom:** Session start shows `vault '{name}' not found`. Config references a vault that doesn't exist on the MuninnDB server.

**Cause:** Server was restarted/reinstalled, or vault was created on a different MuninnDB instance.

**Fix:**
```bash
bash scripts/muninn-setup.sh --vault
```

### "Memory recall returned 0 results" (Phase 2+)

**Symptom:** Agent reports `⚠ Memory recall returned 0 results despite prior phases`.

**Cause:** The `context` parameter in `muninn_activate` doesn't match stored engrams semantically. Prior phase agents may not have stored engrams, or the context string is too narrow.

**Fix:**
1. Check vault health: `muninn status`
2. Verify engrams exist: `muninn search --vault {vault} --query "phase 1"` (or equivalent)
3. Broaden the context parameter — use the phase goal, not a specific task description

### "REST API not responding"

**Symptom:** MCP server is healthy but REST API on port 8475 is unreachable.

**Cause:** MuninnDB may have started without REST API enabled, or a firewall is blocking the port.

**Fix:**
1. Check if REST port is in use: `curl -sf http://localhost:8475/api/vaults`
2. Restart MuninnDB: `muninn stop && muninn start`
3. Verify port config: check `muninndb_port_rest` in `.vbw-planning/config.json`

### Port conflicts

**Symptom:** MuninnDB fails to start, or connects to the wrong service.

**Default ports:**
- `8750` — MCP server (Claude Code integration)
- `8475` — REST API (engram management)
- `8476` — Web UI

**Fix:** Change ports in `.vbw-planning/config.json`:
```json
{
  "muninndb_port_mcp": 9750,
  "muninndb_port_rest": 9475
}
```

Then restart MuninnDB with the new ports.

### Multi-project vault collision

**Symptom:** Two projects with the same repo name share a vault, causing cross-project memory pollution.

**Cause:** Vault names are derived from `git remote` origin basename. Two forks of the same repo get the same vault name.

**Fix:** Set explicit vault names per project:
```bash
# Project A
/vbw:config muninndb_vault my-project-frontend

# Project B
/vbw:config muninndb_vault my-project-backend
```

The setup wizard (`bash scripts/muninn-setup.sh`) auto-detects collisions and appends a disambiguator when needed.

## Configuration Reference

See `references/muninn-types.md` for the full configuration parameter table and engram type documentation.
