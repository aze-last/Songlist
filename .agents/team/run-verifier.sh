#!/usr/bin/env bash
# run-verifier.sh -- Gate-first diff verifier runner (Linux/macOS/WSL; ps1 twin: run-verifier.ps1).
#
# Order of operations:
#   1. Resolve the repo root and confirm the tool-less verifier agent exists.
#   2. Run the deterministic gate only: diff-scan.sh --gate-only.
#      (allowlist -> denied files -> secrets -> pnpm/destructive). No model call on failure.
#   3. Snapshot git status.
#   4. Build the verifier packet: PLAN.md + changed-file list + tracked diff + untracked text.
#   5. Call `opencode run --agent verifier --model <model>` with the packet.
#   6. Snapshot git status again; a mutation is a contract violation.
#   7. Require a final `Decision: APPROVE|BLOCK` line.
#
# Exit codes: 0 = APPROVE, 1 = BLOCK (gate or verifier), 2 = runner/tamper error.
#
# Model override: set VERIFIER_MODEL. The free lineup rotates, so the default lives
# in one variable below.

TESTFILTER=""
for arg in "$@"; do
  case "$arg" in
    --test-filter=*) TESTFILTER="${arg#*=}" ;;
    -TestFilter) : ;;
    *) [ -z "$TESTFILTER" ] && TESTFILTER="$arg" ;;
  esac
done
# Support: run-verifier.sh -TestFilter <name> (PowerShell-style pair).
for ((i = 1; i <= $#; i++)); do
  if [ "${!i}" = "-TestFilter" ]; then
    j=$((i + 1))
    [ "$j" -le "$#" ] && TESTFILTER="${!j}"
  fi
done

DEFAULT_VERIFIER_MODEL="opencode/deepseek-v4-flash-free"
MODEL="${VERIFIER_MODEL:-$DEFAULT_VERIFIER_MODEL}"
INLINE_LIMIT=16000
MAX_PACKET_CHARS=$((4 * 1024 * 1024))

fail() {
  local message="$1" code="${2:-2}"
  echo "BLOCK: $message"
  echo "RESULT: BLOCK"
  exit "$code"
}

# Minimal binary detection (mirrors the gate; not a gate decision itself).
BINARY_EXTENSIONS=" .png .jpg .jpeg .gif .bmp .ico .webp .tif .tiff .pdf .zip .gz .tgz .tar .7z .rar .xz .bz2 .exe .dll .so .dylib .bin .dat .pyc .pyo .class .jar .war .mp3 .mp4 .mov .avi .mkv .wav .flac .woff .woff2 .ttf .otf .eot .sqlite .sqlite3 .db .xls .xlsx .doc .docx .ppt .pptx .psd .blend "
is_binary() {
  local path="$1" ext
  ext="$(printf '%s' "${path##*.}" | tr 'A-Z' 'a-z')"
  case "$BINARY_EXTENSIONS" in *" .$ext "*) return 0 ;; esac
  [ -f "$path" ] || return 0
  if LC_ALL=C head -c 8000 -- "$path" 2>/dev/null | od -An -v -tx1 | grep -q ' 00'; then
    return 0
  fi
  return 1
}

# 0. Preconditions -----------------------------------------------------------
command -v opencode >/dev/null 2>&1 || fail "'opencode' is not on PATH - no verifier call was made."

ROOT="$(git rev-parse --show-toplevel 2>/dev/null | head -n 1)"
[ -n "$ROOT" ] || fail "Cannot determine the repository root - no verifier call was made."
cd "$ROOT" || fail "Cannot enter repository root $ROOT."

[ -f .agents/team/diff-scan.sh ] || fail "Gate script not found at .agents/team/diff-scan.sh - no verifier call was made."
if [ ! -f .opencode/agents/verifier.md ] && [ ! -f opencode.json ] && [ ! -f .agents/team/opencode.json ]; then
  fail "Verifier agent definition not found (neither .opencode/agents/verifier.md nor opencode.json) - no verifier call was made."
fi
[ -f PLAN.md ] || fail "PLAN.md not found - spec conformance cannot be verified; no verifier call was made."

# 1. Deterministic gate FIRST (no network, no model) -------------------------
echo "--- Pre-Verifier Gate ---"
if [ -n "$TESTFILTER" ]; then
  bash .agents/team/diff-scan.sh --gate-only "$TESTFILTER"
else
  bash .agents/team/diff-scan.sh --gate-only
fi
GATE_CODE=$?
if [ "$GATE_CODE" -ne 0 ]; then
  fail "Deterministic gate returned BLOCK (exit $GATE_CODE); verifier was not called." 1
fi

# 2. Build the packet --------------------------------------------------------
HAS_HEAD=0
if git rev-parse -q --verify HEAD >/dev/null 2>&1; then HAS_HEAD=1; fi

TRACKED=()
if [ "$HAS_HEAD" = "1" ]; then
  TRACKED_OUT="$(git diff HEAD --name-only 2>/dev/null)"
  if [ $? -ne 0 ]; then fail "git diff HEAD failed - cannot build the change set."; fi
  while IFS= read -r f; do [ -n "$f" ] && TRACKED+=("$f"); done <<< "$TRACKED_OUT"
else
  echo "NOTE:  No HEAD commit; every file is presented as new content."
fi

UNTRACKED=()
UNTRACKED_OUT="$(git ls-files --others --exclude-standard 2>/dev/null)"
if [ $? -ne 0 ]; then fail "git ls-files failed - cannot list untracked files."; fi
while IFS= read -r f; do [ -n "$f" ] && UNTRACKED+=("$f"); done <<< "$UNTRACKED_OUT"

ALL_FILES=()
DEDUPED="$(printf '%s\n' ${TRACKED[@]+"${TRACKED[@]}"} ${UNTRACKED[@]+"${UNTRACKED[@]}"} | awk 'NF && !seen[$0]++')"
while IFS= read -r f; do [ -n "$f" ] && ALL_FILES+=("$f"); done <<< "$DEDUPED"

REMOTES="$(git remote -v 2>/dev/null | awk '{print $2}' | awk '!seen[$0]++ { printf "%s%s", sep, $0; sep=", " }')"
[ -n "$REMOTES" ] || REMOTES="(none)"

PACKET_FILE="$(mktemp 2>/dev/null)" || fail "mktemp failed - cannot build the verifier packet."
OUT_LOG="$(mktemp 2>/dev/null)" || { rm -f "$PACKET_FILE"; fail "mktemp failed - cannot capture verifier output."; }
cleanup() { rm -f "$PACKET_FILE" "$OUT_LOG"; }
trap cleanup EXIT

{
  echo "You are the read-only diff verifier. Follow your agent contract exactly."
  echo "Review only the packet below. You have no tools; do not claim to inspect anything else."
  echo ""
  echo "Repository: $ROOT"
  echo "Remotes: $REMOTES"
  echo "Changed files: ${#ALL_FILES[@]}"
  echo ""
  echo "=== PLAN.md (build contract) ==="
  cat PLAN.md
  echo ""
  echo "=== CHANGED FILES ==="
  if [ "${#ALL_FILES[@]}" -eq 0 ]; then
    echo "(none)"
  else
    for f in "${ALL_FILES[@]}"; do echo "- $f"; done
  fi
  echo ""
  echo "=== DIFF (tracked changes plus untracked text files) ==="
  if [ "$HAS_HEAD" = "1" ]; then
    TRACKED_DIFF="$(git diff HEAD -- 2>/dev/null)"
    if [ $? -ne 0 ]; then fail "git diff HEAD failed - cannot build the verifier packet."; fi
    if [ -n "$TRACKED_DIFF" ]; then
      printf '%s\n' "$TRACKED_DIFF"
    else
      echo "(no tracked changes)"
    fi
  else
    echo "(no HEAD commit; untracked files below are the change set)"
  fi
  for f in ${UNTRACKED[@]+"${UNTRACKED[@]}"}; do
    [ -f "$f" ] || continue
    echo "diff --git a/$f b/$f"
    if is_binary "$f"; then
      echo "new file mode 100644"
      echo "Binary file (content not sent to the verifier)."
      echo ""
      continue
    fi
    LINE_COUNT="$(awk 'END { print NR }' "$f")"
    echo "new file mode 100644"
    echo "--- /dev/null"
    echo "+++ b/$f"
    echo "@@ -0,0 +1,$LINE_COUNT @@"
    awk '{print "+"$0}' "$f"
    echo ""
  done
  echo "=== END PACKET ==="
  echo ""
  echo "Return only findings and the final 'Decision: APPROVE' or 'Decision: BLOCK' line."
  echo "Do not repeat suspected secret values; cite file:line and type only."
} > "$PACKET_FILE"

PACKET_CHARS="$(wc -c < "$PACKET_FILE" | tr -d ' ')"
if [ "$PACKET_CHARS" -gt "$MAX_PACKET_CHARS" ]; then
  fail "Verifier packet is $PACKET_CHARS chars, above the $MAX_PACKET_CHARS fail-closed cap. Split the change set or review manually."
fi

# 3. Snapshot, call the tool-less verifier, snapshot again -------------------
BEFORE="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)"
if [ $? -ne 0 ]; then fail "git status failed - cannot enforce the clean-tree contract."; fi

echo "--- Verifier Run ---"
echo "MODEL:  $MODEL"
if [ "$PACKET_CHARS" -gt "$INLINE_LIMIT" ]; then
  echo "PACKET: $PACKET_CHARS chars (attached with --file)"
  opencode run --agent verifier --model "$MODEL" --file "$PACKET_FILE" \
    "Review the attached verifier packet. Return only findings and the final Decision line." \
    > "$OUT_LOG" 2>&1
else
  echo "PACKET: $PACKET_CHARS chars (inline)"
  PROMPT="$(cat "$PACKET_FILE")"
  opencode run --agent verifier --model "$MODEL" "$PROMPT" > "$OUT_LOG" 2>&1
fi
CODE=$?
cat "$OUT_LOG"
OUTPUT="$(cat "$OUT_LOG")"

AFTER="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)"
if [ "$AFTER" != "$BEFORE" ]; then
  echo "--- Working Tree Diff (before vs after) ---"
  diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") || true
  fail "The verifier run changed the working tree. The tool-less verifier must be read-only; treat this as a contract violation." 2
fi

if [ "$CODE" -ne 0 ]; then
  fail "opencode run failed (exit $CODE); the output above is not a valid review." 2
fi

# 4. Require a final decision line ------------------------------------------
DECISION="$(printf '%s\n' "$OUTPUT" | grep -E '^[[:space:]]*Decision:[[:space:]]*(APPROVE|BLOCK)([^A-Za-z]|$)' | tail -n 1 | sed -E 's/.*Decision:[[:space:]]*([A-Za-z]+).*/\1/' | tr 'a-z' 'A-Z')"
if [ -z "$DECISION" ]; then
  fail "Verifier output has no final 'Decision: APPROVE|BLOCK' line - fail-closed." 2
fi

if [ "$DECISION" = "BLOCK" ]; then
  echo "RESULT: BLOCK"
  exit 1
fi
echo "RESULT: APPROVE"
exit 0
