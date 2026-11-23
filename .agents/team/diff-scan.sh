#!/usr/bin/env bash
# diff-scan.sh -- bash twin of diff-scan.ps1 (Linux/macOS parity, identical contract).
# Execution Order: script -> failures straight back to the coder -> reviewer inspects git diff.
# Gate-enforced stacks:
#   - Laravel / PHP      : Pint lint + artisan test
#   - Node / TypeScript  : package.json scripts (pnpm lint / pnpm test) - TS rides the Node path
#   - Python             : ruff lint (uv-preferred) + pytest (narrower by changed test files)
#   - Flutter / Dart     : dart format (check-only) + flutter analyze + flutter test
#   - Rust               : cargo fmt --check + cargo test
#   - Go                 : gofmt -l + go test ./...
# Exit 0 = GREEN. Exit 1 = BLOCK. FAIL-CLOSED: git enumeration errors can never produce a silent GREEN.
# Usage: bash .agents/team/diff-scan.sh [--gate-only] [TestFilter]
# TestFilter is honored by: artisan --filter, pnpm test -- <name>, pytest -k, cargo test <name>, go test -run.
# --gate-only runs the allowlist/denied-file/secret/pnpm/destructive gate and exits before any
# linter or test. run-verifier.sh uses it so no gate logic is duplicated.

TESTFILTER=""
GATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --gate-only|-GateOnly|--GateOnly) GATE_ONLY=1 ;;
    *) [ -z "$TESTFILTER" ] && TESTFILTER="$arg" ;;
  esac
done
FAIL=0

block()   { echo "BLOCK: $*"; FAIL=1; }
note()    { echo "NOTE:  $*"; }
report()  { echo "GATE:  $*"; }
has()     { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Fail-closed repository allowlist + secret/credential gate.
# This runs before any linter/test (and before any verifier/model call).
# Default deny: missing allowlist, missing repo identity, or no matching entry
# aborts immediately. Findings never print the suspected secret value.
# ---------------------------------------------------------------------------

normalize_repo_path() {
  local p="${1:-}"
  [ -n "$p" ] || { printf '%s' ""; return 0; }
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  while [ "${p%/}" != "$p" ] || [ "${p%\\}" != "$p" ]; do
    p="${p%/}"; p="${p%\\}"
  done
  p="${p//\\//}"
  # WSL path (/mnt/c/...) and native Windows path must normalize to the same key.
  if [[ "$p" =~ ^/mnt/([A-Za-z])/(.*)$ ]]; then
    p="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
  fi
  if [[ "$p" =~ ^[A-Za-z]: ]]; then
    p="$(printf '%s' "${p:0:1}" | tr 'A-Z' 'a-z')${p:1}"
  fi
  printf '%s' "$p" | tr 'A-Z' 'a-z'
}

normalize_remote() {
  local r="${1:-}"
  [ -n "$r" ] || { printf '%s' ""; return 0; }
  r="${r#"${r%%[![:space:]]*}"}"
  r="${r%"${r##*[![:space:]]}"}"
  while [ "${r%/}" != "$r" ] || [ "${r%\\}" != "$r" ]; do
    r="${r%/}"; r="${r%\\}"
  done
  r="${r%.git}"
  printf '%s' "$r" | tr 'A-Z' 'a-z'
}

get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null | head -n 1
}

get_repo_remotes() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    git remote get-url --all "$name" 2>/dev/null
  done < <(git remote 2>/dev/null)
}

assert_repo_allowed() {
  local allowlist="${REPO_ALLOWLIST:-.agents/team/repo-allowlist.txt}"
  if [ ! -f "$allowlist" ]; then
    block "REPO_ALLOWLIST not found at $allowlist - default deny (no verifier/model call)."
    return 1
  fi

  local root; root="$(get_repo_root)"
  if [ -z "$root" ]; then
    block "Cannot determine the repository root - default deny."
    return 1
  fi

  local norm_root; norm_root="$(normalize_repo_path "$root")"
  local -a remotes=()
  local url
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    url="$(normalize_remote "$url")"
    [ -n "$url" ] && remotes+=("$url")
  done < <(get_repo_remotes)

  local entry entry_count=0 matched=0 r needle
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry%$'\r'}"
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [ -n "$entry" ] || continue
    case "$entry" in \#*) continue ;; esac
    entry_count=$((entry_count + 1))

    if [[ "$entry" =~ ^path[[:space:]]*:[[:space:]]*(.+)$ ]]; then
      if [ "$(normalize_repo_path "${BASH_REMATCH[1]}")" = "$norm_root" ]; then matched=1; break; fi
    elif [[ "$entry" =~ ^remote[[:space:]]*:[[:space:]]*(.+)$ ]]; then
      needle="$(normalize_remote "${BASH_REMATCH[1]}")"
      for r in ${remotes[@]+"${remotes[@]}"}; do
        if [ "$r" = "$needle" ]; then matched=1; break 2; fi
      done
    else
      if [ "$(normalize_repo_path "$entry")" = "$norm_root" ]; then matched=1; break; fi
      needle="$(normalize_remote "$entry")"
      for r in ${remotes[@]+"${remotes[@]}"}; do
        if [ "$r" = "$needle" ]; then matched=1; break 2; fi
      done
    fi
  done < "$allowlist"

  if [ "$entry_count" -eq 0 ]; then
    block "REPO_ALLOWLIST is empty at $allowlist - default deny."
    return 1
  fi
  if [ "$matched" -ne 1 ]; then
    block "Repository not allowlisted (default deny). Root: $root. Add 'path:$root' or a matching 'remote:<url>' to $allowlist."
    return 1
  fi
  note "Repository allowlisted: $root"
  return 0
}

BINARY_EXTENSIONS=" .png .jpg .jpeg .gif .bmp .ico .webp .tif .tiff .pdf .zip .gz .tgz .tar .7z .rar .xz .bz2 .exe .dll .so .dylib .bin .dat .pyc .pyo .class .jar .war .mp3 .mp4 .mov .avi .mkv .wav .flac .woff .woff2 .ttf .otf .eot .sqlite .sqlite3 .db .xls .xlsx .doc .docx .ppt .pptx .psd .blend "

test_binary_file() {
  local path="$1" ext
  ext="$(printf '%s' "${path##*.}" | tr 'A-Z' 'a-z')"
  case "$BINARY_EXTENSIONS" in *" .$ext "*) return 0 ;; esac
  [ -f "$path" ] || return 0
  if LC_ALL=C head -c 8000 -- "$path" 2>/dev/null | od -An -v -tx1 | grep -q ' 00'; then
    return 0
  fi
  return 1
}

test_path_has_segment() {
  local p="${1//\\//}" segment="$2"
  p="${p#/}"; p="${p%/}"
  [ "$p" = "$segment" ] && return 0
  case "$p" in
    "$segment"/*|*/"$segment"/*|*/"$segment") return 0 ;;
  esac
  return 1
}

# Prints the denial reason and returns 0 when denied; prints nothing and returns 1 when allowed.
test_denied_file() {
  local p="${1//\\//}"
  local leaf="${p##*/}"

  # Environment templates are safe; every other .env* file is denied.
  case "$leaf" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
    .env*) printf '%s' "environment file"; return 0 ;;
  esac

  case "$leaf" in
    appsettings.json|appsettings.*.json) printf '%s' "application settings (may contain credentials)"; return 0 ;;
    id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*|id_dsa|id_dsa.*) printf '%s' "SSH private key"; return 0 ;;
    *.pem|*.key|*.pfx|*.p12|*.jks|*.keystore|*.ppk|*.kdbx|*.ovpn) printf '%s' "private key / credential container"; return 0 ;;
    credentials|credentials.*|credential|credential.*|secret|secrets|secret.*|secrets.*) printf '%s' "credentials file"; return 0 ;;
    service-account*.json|service_account*.json) printf '%s' "service account key"; return 0 ;;
    .npmrc|npmrc|.pypirc|pypirc|.netrc|netrc|.git-credentials|git-credentials) printf '%s' "credential config"; return 0 ;;
    terraform.tfstate|terraform.tfstate.*|*.tfvars|*.tfvars.json) printf '%s' "terraform state/vars (may contain secrets)"; return 0 ;;
    package-lock.json|yarn.lock|bun.lockb) printf '%s' "non-pnpm lockfile"; return 0 ;;
    *.sqlite|*.sqlite3|*.db) printf '%s' "binary database"; return 0 ;;
    *.dump|*.bak) printf '%s' "database dump/backup"; return 0 ;;
  esac

  case "$leaf" in
    *.sql)
      case "$p" in
        */migrations/*|*/migration/*|*/migrate/*|*/db/migrate/*) return 1 ;;
      esac
      case "$leaf" in *migrat*) return 1 ;; esac
      printf '%s' "SQL dump/export (may contain sensitive data)"; return 0 ;;
  esac

  test_path_has_segment "$p" "storage" && { printf '%s' "storage directory"; return 0; }
  case "$p" in */.aws/credentials|.aws/credentials) printf '%s' "AWS credentials"; return 0 ;; esac
  test_path_has_segment "$p" ".ssh" && { printf '%s' "SSH directory"; return 0; }
  case "$p" in */.kube/config|.kube/config) printf '%s' "Kubernetes config"; return 0 ;; esac
  case "$p" in */.docker/config.json|.docker/config.json) printf '%s' "Docker credential config"; return 0 ;; esac

  return 1
}

PLACEHOLDER_RE='(example|sample|placeholder|dummy|fake|redacted|changeme|change[_-]?me|your[_-]|x{3,}|<[^>]+>|\$\{[^}]+\}|%[a-z_]+%|os\.environ|process\.env|getenv|env\.get|secret[_-]?manager|vault)'

SECRET_RULE_NAMES=(
  private-key aws-access-key aws-secret-key github-token slack-token google-api-key
  stripe-key openai-style-key jwt connection-string-password secret-assignment
)
SECRET_RULE_PATTERNS=(
  '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----'
  '(^|[^A-Za-z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^A-Za-z0-9]|$)'
  'ci:aws_secret_access_key[[:space:]]*[:=][[:space:]]*["'\'']?[a-z0-9/+=]{40}'
  '(^|[^A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})([^A-Za-z0-9]|$)'
  '(^|[^A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{10,}([^A-Za-z0-9]|$)'
  '(^|[^A-Za-z0-9])AIza[0-9A-Za-z_-]{35}([^A-Za-z0-9]|$)'
  '(^|[^A-Za-z0-9])(sk|rk)_live_[0-9A-Za-z]{24,}([^A-Za-z0-9]|$)'
  '(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{32,}([^A-Za-z0-9]|$)'
  '(^|[^A-Za-z0-9])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}([^A-Za-z0-9]|$)'
  'ci:(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp)://[^:[:space:]/@]+:[^@[:space:]]+@'
  'ci:(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|refresh[_-]?token|password|passwd)[[:space:]]*[:=][[:space:]]*["'\''][a-z0-9_./+=-]{16,}["'\'']'
)

SCANNED_LINES=()
SCANNED_COUNT=0
SECRET_FINDING_KEYS="|"

scan_secret_line() {
  local file="$1" line_no="$2" text="$3" low="" rule name key i
  local had_nocasematch=0 ci_mode=0
  [ -n "$text" ] || return 0
  if [ "$SCANNED_COUNT" -lt 200000 ]; then
    SCANNED_LINES+=("$file:$line_no: $text")
    SCANNED_COUNT=$((SCANNED_COUNT + 1))
  fi

  # Prefer the shell's built-in case-insensitive matching (bash 3.2-safe and
  # fast). Fall back to one `tr` per line only if nocasematch is unavailable.
  shopt -q nocasematch 2>/dev/null && had_nocasematch=1
  if shopt -s nocasematch 2>/dev/null; then
    ci_mode=1
  else
    low="$(printf '%s' "$text" | tr 'A-Z' 'a-z')"
  fi

  if [ "$ci_mode" = "1" ]; then
    if [[ "$text" =~ $PLACEHOLDER_RE ]]; then
      [ "$had_nocasematch" = "1" ] || shopt -u nocasematch 2>/dev/null
      return 0
    fi
  else
    if [[ "$low" =~ $PLACEHOLDER_RE ]]; then
      return 0
    fi
  fi

  for i in "${!SECRET_RULE_NAMES[@]}"; do
    name="${SECRET_RULE_NAMES[$i]}"
    rule="${SECRET_RULE_PATTERNS[$i]}"
    if [[ "$rule" == ci:* ]]; then
      if [ "$ci_mode" = "1" ]; then
        [[ "$text" =~ ${rule#ci:} ]] || continue
      else
        [[ "$low" =~ ${rule#ci:} ]] || continue
      fi
    else
      [[ "$text" =~ $rule ]] || continue
    fi
    key="$file:$line_no:$name"
    case "$SECRET_FINDING_KEYS" in
      *"|$key|"*)
        [ "$had_nocasematch" = "1" ] || shopt -u nocasematch 2>/dev/null
        return 0 ;;
    esac
    SECRET_FINDING_KEYS="$SECRET_FINDING_KEYS$key|"
    block "$file:$line_no - potential secret ($name); value not printed."
    [ "$had_nocasematch" = "1" ] || shopt -u nocasematch 2>/dev/null
    return 0
  done
  [ "$had_nocasematch" = "1" ] || shopt -u nocasematch 2>/dev/null
  return 0
}

scan_secret_added() {
  local file="$1" diff line new_line=0
  diff="$(git diff HEAD -U0 -- "$file" 2>/dev/null)"
  if [ $? -ne 0 ]; then
    block "git diff -U0 failed for $file - fail-closed."
    return 0
  fi
  while IFS= read -r line; do
    if [[ "$line" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      new_line="${BASH_REMATCH[2]}"
    elif [[ "$line" == +* && "$line" != +++* ]]; then
      scan_secret_line "$file" "$new_line" "${line:1}"
      new_line=$((new_line + 1))
    elif [[ "$line" == " "* ]]; then
      new_line=$((new_line + 1))
    fi
  done <<< "$diff"
}

scan_secret_full() {
  local file="$1" line n=0
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    scan_secret_line "$file" "$n" "$line"
  done < "$file"
}

invoke_gitleaks_text() {
  local label="$1" text="$2" tmp code
  has gitleaks || return 0
  [ -n "$text" ] || return 0
  tmp="$(mktemp 2>/dev/null)" || { block "mktemp failed for gitleaks - fail-closed."; return 0; }
  printf '%s\n' "$text" > "$tmp"
  gitleaks detect --no-git --source "$tmp" --redact --no-banner >/dev/null 2>&1
  code=$?
  rm -f "$tmp"
  if [ "$code" -eq 1 ]; then
    block "gitleaks reported potential secrets in $label (values redacted); see repo-relative file:line from the regex scan above."
  elif [ "$code" -ne 0 ]; then
    block "gitleaks failed on $label (exit $code) - fail-closed."
  fi
}

invoke_secret_content_gate() {
  local f
  for f in ${FILES[@]+"${FILES[@]}"}; do
    [ -f "$f" ] || continue
    if test_binary_file "$f"; then
      note "Skipped binary content scan: $f"
      continue
    fi
    if [ "$HAS_HEAD" = "1" ] && git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      scan_secret_added "$f"
    else
      scan_secret_full "$f"
    fi
  done

  # PLAN.md is the build contract and is always scanned in full.
  if [ -f PLAN.md ]; then
    if test_binary_file PLAN.md; then
      block "PLAN.md is binary - fail-closed."
    else
      scan_secret_full PLAN.md
    fi
  fi

  # Optional stronger oracle. The regex rules above are the always-on fallback.
  if has gitleaks; then
    invoke_gitleaks_text "diff+PLAN.md" "$(printf '%s\n' ${SCANNED_LINES[@]+"${SCANNED_LINES[@]}"})"
  else
    note "gitleaks not installed - regex secret fallback used (diff added lines + PLAN.md)."
  fi
}

# Per-stack exit report state (n/a = marker absent, never enforced)
LAR_LINT="n/a"; LAR_TEST="n/a"
NODE_LINT="n/a"; NODE_TEST="n/a"
PY_LINT="n/a"; PY_TEST="n/a"
FL_LINT="n/a"; FL_TEST="n/a"
RS_LINT="n/a"; RS_TEST="n/a"
GO_LINT="n/a"; GO_TEST="n/a"

if ! has git; then
  block "git not available - fail-closed: cannot verify the change set."
  echo "RESULT: BLOCK"; exit 1
fi

scan_added_lines_label=""
scan_added_lines_n=0
scan_one(){ # $1=label, $2=line content
  local file="$1" line="$2"
  case "$file" in
    .agents/*|*.md) return 0 ;;
  esac
  local n="$scan_added_lines_n"
  case "$line" in
    *"npm run"*|*"npm install"*|*"yarn add"*|*"yarn install"*|*"bun add"*|*"bun install"*)
      block "$file (~added $n): Non-pnpm command detected ($line). Use pnpm exclusively." ;;
  esac
  case "$line" in
    *'->forceDelete()'*|*"DROP TABLE"*|*"TRUNCATE TABLE"*)
      case "$file" in
        *migration*) ;;
        *) block "$file (~added $n): High-risk destructive operation ($line). Soft delete or explicit dev approval required." ;;
      esac ;;
  esac
}
scan_begin(){ scan_added_lines_n=0; scan_added_lines_label="$1"; }
scan_line(){ scan_added_lines_n=$((scan_added_lines_n + 1)); scan_one "$scan_added_lines_label" "$1"; }

# 1. Repository allowlist gate (FAIL-CLOSED, before any model call)
#    Default deny: missing/empty allowlist, or no path/remote match, aborts here.
echo "--- Repository Allowlist Gate ---"
if ! assert_repo_allowed; then
  echo "RESULT: BLOCK"; exit 1
fi

# 2. Change-set acquisition (FAIL-CLOSED)
HAS_HEAD=0
if git rev-parse -q --verify HEAD >/dev/null 2>&1; then HAS_HEAD=1; fi

FILES=()
if [ "$HAS_HEAD" = "1" ]; then
  TRACKED_REVISION_="$(git diff HEAD --name-only 2>/dev/null)"
  if [ $? -ne 0 ]; then
    block "git diff HEAD failed - fail-closed: cannot verify the change set."
  else
    while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<<"$TRACKED_REVISION_"
  fi
else
  note "No commits yet (no HEAD) - entire worktree is treated as new content."
fi

UNTRACKED_REVISION_="$(git ls-files --others --exclude-standard 2>/dev/null)"
if [ $? -ne 0 ]; then
  block "git ls-files failed - fail-closed: cannot list untracked files."
else
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<<"$UNTRACKED_REVISION_"
fi

# dedupe (bash 3.2-safe: no mapfile / process substitution)
if [ "${#FILES[@]}" -gt 0 ]; then
  DEDUPED="$(printf '%s\n' "${FILES[@]}" | awk '!seen[$0]++' || true)"
  FILES=()
  while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<<"$DEDUPED"
fi

# 2a. Denied files anywhere in the change set.
#     Covers secrets, credential containers, binary DBs, SQL dumps, and foreign lockfiles.
for f in ${FILES[@]+"${FILES[@]}"}; do
  reason="$(test_denied_file "$f")"
  if [ -n "$reason" ]; then
    block "$f in change set -- denied ($reason)."
  fi
done

# 2b. Secret content gate (diff added lines + untracked text + full PLAN.md).
#     Runs before any linter/test and before the verifier/model call. Never prints values.
invoke_secret_content_gate

# 3. Strict PNPM + destructive-op scan on added content
for f in ${FILES[@]+"${FILES[@]}"}; do
  if [ ! -e "$f" ]; then continue; fi # deleted file - name already banned-checked above
  TRACKED_F=1
  if [ "$HAS_HEAD" = "1" ]; then
    git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || TRACKED_F=0
  else
    TRACKED_F=0
  fi
  scan_begin "$f"
  if [ "$TRACKED_F" = "1" ]; then
    ADDED_OUT="$(git diff HEAD -U0 -- "$f" 2>/dev/null)"
    if [ $? -ne 0 ]; then
      block "git diff -U0 failed for $f - fail-closed."
      continue
    fi
    if [ -n "$ADDED_OUT" ]; then
      ADDED_PLAIN="$(printf '%s\n' "$ADDED_OUT" | grep '^+' | grep -v '^+++' | cut -c2-)"
      if [ -n "$ADDED_PLAIN" ]; then
        while IFS= read -r line; do scan_line "$line"; done <<<"$ADDED_PLAIN"
      fi
    fi
  else
    if [ -f "$f" ]; then
      while IFS= read -r line; do scan_line "$line"; done <"$f"
    fi
  fi
done

# 3a. Gate-only mode (used by run-verifier): exit before any linter/test execution.
if [ "$GATE_ONLY" = "1" ]; then
  echo "--- Gate Report ---"
  report "GATE-ONLY: allowlist + denied-file + secret + pnpm/destructive checks."
  if [ "$FAIL" = "1" ]; then
    echo "RESULT: BLOCK"; exit 1
  else
    echo "RESULT: GREEN"; exit 0
  fi
fi

# 4. Linter Gate (per-stack detection)
echo "--- Linter Gate ---"

# 4a. Laravel -- Pint
if [ -f vendor/bin/pint ]; then
  if has php; then
    if php vendor/bin/pint --dirty --format agent; then LAR_LINT="ran ok"; else LAR_LINT="FAILED"; block "Pint linter failed."; fi
  else
    LAR_LINT="skipped (php missing)"
    note "Laravel Pint present but 'php' is not on PATH - lint skipped."
  fi
fi

# 4b. Node / TypeScript -- pnpm lint
if [ -f package.json ]; then
  if grep -q '"lint"' package.json; then
    if has pnpm; then
      if pnpm run lint; then NODE_LINT="ran ok"; else NODE_LINT="FAILED"; block "pnpm lint failed."; fi
    else
      NODE_LINT="skipped (pnpm missing)"
      note "package.json declares a lint script but 'pnpm' is not on PATH - lint skipped."
    fi
  fi
fi

# 4c. Python -- ruff (uv-wrapped preferred)
PYTHON_MARK=0
[ -f pyproject.toml ] && PYTHON_MARK=1
[ -f requirements.txt ] && PYTHON_MARK=1
if [ "$PYTHON_MARK" = "1" ]; then
  if has ruff || has uv; then
    if [ -f pyproject.toml ] && has uv; then
      if uv run ruff check .; then PY_LINT="ran ok"; else PY_LINT="FAILED"; block "ruff check failed (uv run)."; fi
    else
      if ruff check .; then PY_LINT="ran ok"; else PY_LINT="FAILED"; block "ruff check failed."; fi
    fi
  else
    PY_LINT="skipped (ruff/uv missing)"
    note "Python detected but neither 'ruff' nor 'uv' is on PATH - lint skipped (agents: use 'uv run ruff check .')."
  fi
fi

# 4d. Flutter / Dart -- dart format (check-only) + flutter analyze
if [ -f pubspec.yaml ]; then
  if has dart && has flutter; then
    if dart format --set-exit-if-changed --output=none .; then FMT_OK=1; else FMT_OK=0; fi
    if [ "$FMT_OK" = "1" ] && flutter analyze; then
      FL_LINT="ran ok"
    else
      FL_LINT="FAILED"
      block "dart format / flutter analyze failed - run 'dart format .' locally then re-check."
    fi
  else
    FL_LINT="skipped (dart/flutter missing)"
    note "Flutter detected but 'dart'/'flutter' not on PATH - lint skipped."
  fi
fi

# 4e. Rust -- cargo fmt --check
if [ -f Cargo.toml ]; then
  if has cargo; then
    if cargo fmt --check; then RS_LINT="ran ok"; else RS_LINT="FAILED"; block "cargo fmt --check failed - run 'cargo fmt' locally."; fi
  else
    RS_LINT="skipped (cargo missing)"
    note "Rust detected but 'cargo' is not on PATH - lint skipped."
  fi
fi

# 4f. Go -- gofmt -l
if [ -f go.mod ]; then
  if has gofmt; then
    UNFMT="$(gofmt -l . 2>/dev/null || true)"
    if [ -n "$UNFMT" ]; then
      GO_LINT="FAILED"
      block "gofmt: files need formatting:" 
      while IFS= read -r g; do [ -n "$g" ] && block "  - $g"; done <<<"$UNFMT"
    else
      GO_LINT="ran ok"
    fi
  else
    GO_LINT="skipped (gofmt missing)"
    note "Go detected but 'gofmt' is not on PATH - lint skipped."
  fi
fi

# 5. Test Gate (per-stack; narrower first when changed test files are known)
echo "--- Test Gate ---"

# 5a. Laravel -- artisan test
if [ -f artisan ]; then
  if has php; then
    if [ -n "$TESTFILTER" ]; then
      if php artisan test --compact --filter="$TESTFILTER"; then LAR_TEST="ran ok (filter)"; else LAR_TEST="FAILED"; block "Tests failed."; fi
    else
      ran_any=0
      failed=0
      for f in ${FILES[@]+"${FILES[@]}"}; do
        case "$f" in
          tests/*.php)
            ran_any=1
            if ! php artisan test --compact "$f"; then failed=1; block "Tests failed in $f."; fi ;;
        esac
      done
      if [ "$failed" = "1" ]; then LAR_TEST="FAILED"
      elif [ "$ran_any" = "1" ]; then LAR_TEST="ran ok (narrow)"
      else
        if php artisan test --compact; then LAR_TEST="ran ok (full)"; else LAR_TEST="FAILED"; block "Tests failed."; fi
      fi
    fi
  else
    LAR_TEST="skipped (php missing)"
    note "Laravel detected but 'php' is not on PATH - tests skipped."
  fi
fi

# 5b. Node / TypeScript -- pnpm test
if [ -f package.json ] && grep -q '"test"' package.json; then
  if has pnpm; then
    if [ -n "$TESTFILTER" ]; then
      if pnpm test -- "$TESTFILTER"; then NODE_TEST="ran ok"; else NODE_TEST="FAILED"; block "pnpm test failed."; fi
    else
      if pnpm test; then NODE_TEST="ran ok"; else NODE_TEST="FAILED"; block "pnpm test failed."; fi
    fi
  else
    NODE_TEST="skipped (pnpm missing)"
    note "package.json declares a test script but 'pnpm' is not on PATH - tests skipped."
  fi
fi

# 5c. Python -- pytest (narrower by changed tests/*.py; uv-preferred with pyproject.toml)
if [ "$PYTHON_MARK" = "1" ]; then
  if has pytest || has uv; then
    PYTEST_ARGS=()
    for f in ${FILES[@]+"${FILES[@]}"}; do
      case "$f" in
        tests/*|test/*) case "$f" in *.py) PYTEST_ARGS+=("$f") ;; esac ;;
      esac
    done
    if [ -f pyproject.toml ] && has uv; then
      if [ -n "$TESTFILTER" ]; then
        uv run pytest -k "$TESTFILTER"; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (filter)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) - TDD requires a failing-first test; add at least one pytest test."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC) (uv run)."; fi
      elif [ ${#PYTEST_ARGS[@]} -gt 0 ]; then
        uv run pytest "${PYTEST_ARGS[@]}"; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (narrow)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) in the changed test files - TDD requires a failing-first test."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC) (uv run)."; fi
      else
        uv run pytest; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (full)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) - project has no tests yet; TDD requires at least one."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC) (uv run)."; fi
      fi
    else
      if [ -n "$TESTFILTER" ]; then
        pytest -k "$TESTFILTER"; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (filter)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) - TDD requires a failing-first test; add at least one pytest test."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC)."; fi
      elif [ ${#PYTEST_ARGS[@]} -gt 0 ]; then
        pytest "${PYTEST_ARGS[@]}"; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (narrow)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) in the changed test files - TDD requires a failing-first test."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC)."; fi
      else
        pytest; RC=$?
        if [ $RC -eq 0 ]; then PY_TEST="ran ok (full)"
        elif [ $RC -eq 5 ]; then PY_TEST="FAILED"; block "pytest collected no tests (exit 5) - project has no tests yet; TDD requires at least one."
        else PY_TEST="FAILED"; block "pytest failed (exit $RC)."; fi
      fi
    fi
  else
    PY_TEST="skipped (pytest/uv missing)"
    note "Python detected but neither 'pytest' nor 'uv' is on PATH - tests skipped (agents: use 'uv run pytest')."
  fi
fi

# 5d. Flutter -- flutter test
if [ -f pubspec.yaml ]; then
  if has flutter && has dart; then
    ran_any=0; failed=0
    for f in ${FILES[@]+"${FILES[@]}"}; do
      case "$f" in
        test/*_test.dart|test/*/*_test.dart)
          ran_any=1
          if ! flutter test "$f"; then failed=1; block "flutter test failed in $f."; fi ;;
      esac
    done
    if [ "$failed" = "1" ]; then FL_TEST="FAILED"
    elif [ "$ran_any" = "1" ]; then FL_TEST="ran ok (narrow)"
    else
      if flutter test; then FL_TEST="ran ok (full)"; else FL_TEST="FAILED"; block "flutter test failed."; fi
    fi
  else
    FL_TEST="skipped (flutter missing)"
    note "Flutter detected but 'flutter' is not on PATH - tests skipped."
  fi
fi

# 5e. Rust -- cargo test
if [ -f Cargo.toml ]; then
  if has cargo; then
    if [ -n "$TESTFILTER" ]; then
      if cargo test "$TESTFILTER"; then RS_TEST="ran ok (filter)"; else RS_TEST="FAILED"; block "cargo test failed."; fi
    else
      if cargo test; then RS_TEST="ran ok (full)"; else RS_TEST="FAILED"; block "cargo test failed."; fi
    fi
  else
    RS_TEST="skipped (cargo missing)"
    note "Rust detected but 'cargo' is not on PATH - tests skipped."
  fi
fi

# 5f. Go -- go test ./...
if [ -f go.mod ]; then
  if has go; then
    if [ -n "$TESTFILTER" ]; then
      if go test -run "$TESTFILTER" ./...; then GO_TEST="ran ok (filter)"; else GO_TEST="FAILED"; block "go test failed."; fi
    else
      if go test ./...; then GO_TEST="ran ok (full)"; else GO_TEST="FAILED"; block "go test failed."; fi
    fi
  else
    GO_TEST="skipped (go missing)"
    note "Go detected but 'go' is not on PATH - tests skipped."
  fi
fi

# 6. No-surface honesty note (only when the repo matches NO supported stack)
SURFACES=0
for m in artisan package.json pyproject.toml requirements.txt pubspec.yaml Cargo.toml go.mod; do
  [ -e "$m" ] && SURFACES=1
done
if [ "$SURFACES" = "0" ]; then
  note "No supported stack surface found -> lint/test gates skipped by design (see .agents/rules.md)."
fi

# 7. Gate Report (definitive per-stack states for the coder report)
echo "--- Gate Report ---"
report "LARAVEL : lint=$LAR_LINT | test=$LAR_TEST"
report "NODE/TS : lint=$NODE_LINT | test=$NODE_TEST"
report "PYTHON  : lint=$PY_LINT | test=$PY_TEST"
report "FLUTTER : lint=$FL_LINT | test=$FL_TEST"
report "RUST    : lint=$RS_LINT | test=$RS_TEST"
report "GO      : lint=$GO_LINT | test=$GO_TEST"

if [ "$FAIL" = "1" ]; then
  echo "RESULT: BLOCK"; exit 1
else
  echo "RESULT: GREEN"; exit 0
fi
