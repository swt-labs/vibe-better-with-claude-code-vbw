#!/usr/bin/env bash
# Contributor setup: install this repository's pre-push hook (version files in
# sync). Run it yourself in your own clone; VBW never installs hooks in user
# repositories. Idempotent; refuses to replace a hook it did not write.
set -euo pipefail

hooks_dir="$(git rev-parse --git-path hooks)"
hook="$hooks_dir/pre-push"
marker="# VBW contributor pre-push hook"
mkdir -p "$hooks_dir"

if [ -e "$hook" ] && ! grep -qF "$marker" "$hook"; then
  echo "pre-push hook exists and was not installed by this script; leaving it alone" >&2
  exit 1
fi

cat > "$hook" <<HOOK
#!/usr/bin/env bash
$marker
exec bash "\$(git rev-parse --show-toplevel)/tools/pre-push-hook.sh" "\$@"
HOOK
chmod +x "$hook"
echo "installed $hook"
