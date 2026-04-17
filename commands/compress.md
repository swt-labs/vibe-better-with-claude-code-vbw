---
name: vbw:compress
category: supporting
disable-model-invocation: true
description: Compress a natural language file into caveman format to save input tokens. Preserves code blocks, URLs, and structure.
argument-hint: "<filepath>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# VBW Compress: $ARGUMENTS

## Guard
- No $ARGUMENTS: STOP "Usage: /vbw:compress path/to/file.{md|txt} (or extensionless file)"

## Steps

1. **Validate input file:**
```bash
TARGET="$ARGUMENTS"
if [ ! -f "$TARGET" ]; then echo "ERROR: File not found: $TARGET"; exit 1; fi
SIZE=$(wc -c < "$TARGET" | tr -d ' ')
if [ "$SIZE" -gt 512000 ]; then echo "ERROR: File too large (${SIZE} bytes, max 500KB)"; exit 1; fi
BASENAME="${TARGET##*/}"
case "$BASENAME" in
  *.*) EXT="${BASENAME##*.}" ;;
  *)   EXT="" ;;
esac
case "$EXT" in md|txt|"") ;; *) echo "ERROR: Only .md, .txt, or extensionless files supported"; exit 1;; esac
echo "OK: $TARGET ($SIZE bytes)"
```
If the guard fails, STOP with the error message.

2. **Create backup:**
```bash
case "$TARGET" in
  *.*) BACKUP="${TARGET%.*}.original.${TARGET##*.}";;
  *)   BACKUP="${TARGET}.original";;
esac
if [ -e "$BACKUP" ]; then
  _i=1; while [ -e "${BACKUP%.*}.${_i}.${BACKUP##*.}" ] 2>/dev/null; do _i=$((_i+1)); done
  case "$BACKUP" in *.*) BACKUP="${BACKUP%.*}.${_i}.${BACKUP##*.}";; *) BACKUP="${BACKUP}.${_i}";; esac
fi
cp "$TARGET" "$BACKUP"
echo "Backup: $BACKUP"
```

3. **Read the original file** in full. Then compress it following these rules:

### Remove
- Articles: a, an, the
- Filler: just, really, basically, actually, simply, essentially, generally
- Pleasantries: "sure", "certainly", "of course", "happy to", "I'd recommend"
- Hedging: "it might be worth", "you could consider", "it would be good to"
- Redundant phrasing: "in order to" → "to", "make sure to" → "ensure", "the reason is because" → "because"
- Connective fluff: "however", "furthermore", "additionally", "in addition"

### Preserve EXACTLY (never modify)
- Code blocks (fenced ``` and indented) — copy byte-for-byte, including comments and spacing
- Inline code (`backtick content`)
- URLs and links
- File paths and commands
- Technical terms, proper nouns, dates, version numbers
- Environment variables

### Preserve structure
- All markdown headings (exact heading text, compress body)
- Bullet/number hierarchy and nesting
- Tables (compress cell text, keep structure)
- Frontmatter/YAML headers

### Compress
- Short synonyms: "big" not "extensive", "fix" not "implement a solution for", "use" not "utilize"
- Fragments OK: "Run tests before commit" not "You should always run tests before committing"
- Drop "you should", "make sure to", "remember to" — state the action directly
- Merge redundant bullets that say the same thing differently
- Keep one example where multiple show the same pattern

4. **Write the compressed version** to the original file path, replacing the original content.

5. **Validate the result.** Read both the backup and the compressed file. Check:
- Every markdown heading from the original exists in the compressed version (exact text)
- Every fenced code block from the original exists unchanged in the compressed version
- Every URL from the original exists in the compressed version
- Compressed file is smaller than the original

If validation fails, identify the specific issue and apply a targeted fix (patch only the broken section). Do not recompress from scratch. Retry up to 2 times. If still failing after retries, restore from backup and report the error.

6. **Report results:**
```bash
ORIG_SIZE=$(wc -c < "$BACKUP" | tr -d ' ')
NEW_SIZE=$(wc -c < "$TARGET" | tr -d ' ')
SAVED=$((ORIG_SIZE - NEW_SIZE))
PCT=$((SAVED * 100 / ORIG_SIZE))
echo "Compressed: ${ORIG_SIZE} → ${NEW_SIZE} bytes (${PCT}% reduction)"
echo "Backup at: $BACKUP"
```
