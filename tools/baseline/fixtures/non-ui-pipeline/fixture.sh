#!/usr/bin/env bash
# Seeds a command-line data tool to finish: logs/access.log (well-formed lines
# "TIME METHOD PATH STATUS BYTES" mixed with malformed ones) and a logstat.sh
# stub. The request asks for several summary features.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
mkdir -p logs
cat > logs/access.log <<'LOG'
2026-10-01T10:00:00 GET /index.html 200 512
2026-10-01T10:00:01 GET /about.html 200 256
2026-10-01T10:00:02 POST /login 302 0
garbage line
2026-10-01T10:00:03 GET /index.html 200 512
2026-10-01T10:00:04 GET /missing 404 128
2026-10-01T10:00:05 GET /index.html 500 64
2026-10-01T10:00:06 GET /about.html abc 10

2026-10-01T10:00:07 GET /login 200 300
2026-10-01T10:00:08 GET /about.html 200 256 extra
2026-10-01T10:00:09 POST /login 401 20
LOG
cat > logstat.sh <<'SH'
#!/usr/bin/env bash
# logstat.sh FILE: summarize an access log (not implemented yet).
echo "not implemented" >&2
exit 1
SH
chmod +x logstat.sh
git add -A && git commit -q -m "chore: seed log tool"
