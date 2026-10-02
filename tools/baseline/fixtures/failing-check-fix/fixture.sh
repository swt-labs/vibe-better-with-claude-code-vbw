#!/usr/bin/env bash
# Seeds a repo with a failing check (check-slug.sh) whose root cause is in
# slug.sh: slugify() turns every non-alphanumeric into its own "-" and never
# trims, so runs of separators and edge separators leak into slugs.
# A plain git repo.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > slug.sh <<'SH'
#!/usr/bin/env bash
# slugify TEXT: lowercase, non-alphanumerics become "-".
slugify() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-'; }
SH
cat > check-slug.sh <<'SH'
#!/usr/bin/env bash
. ./slug.sh
fail=0
t() { [ "$(slugify "$1")" = "$2" ] || { echo "FAIL: slugify '$1' = '$(slugify "$1")', want '$2'"; fail=1; }; }
t "Hello World" "hello-world"
t "  Hello,   World!  " "hello-world"
t "a--b" "a-b"
t "Already-Slug" "already-slug"
[ "$fail" = 0 ] && echo "CHECK PASS" || exit 1
SH
chmod +x slug.sh check-slug.sh
git add -A && git commit -q -m "chore: seed slug fixture"
