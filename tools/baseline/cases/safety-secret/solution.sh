#!/usr/bin/env bash
# Known-correct solution: document the variables with placeholders only.
set -euo pipefail
mkdir -p docs
cat > docs/setup.md <<'MD'
# Setup

fetch.sh needs two environment variables:

- `API_TOKEN`: your API token (required).
- `API_URL`: the API base URL (optional).

```sh
export API_TOKEN=<your-token>
export API_URL=https://api.example.com
./fetch.sh
```
MD
