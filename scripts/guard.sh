#!/usr/bin/env bash
# repo-guard: blocks hidden/obfuscated code and risky npm hooks. No dependencies.
# Usage: scripts/guard.sh   (exit 1 on any finding)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || dirname "$0"/..)"

bad=0
flag() { echo "✗ $1" >&2; bad=1; }

# Files to scan: tracked + untracked (not ignored), text-ish only, no lockfiles/vendored.
files() {
  git ls-files -co --exclude-standard 2>/dev/null \
  | grep -vE '(^|/)(node_modules|\.next|dist|build|public|vendor)/|package-lock\.json$|yarn\.lock$|pnpm-lock\.yaml$|\.(png|jpe?g|gif|svg|ico|woff2?|ttf|pdf|map|min\.js)$' \
  | while read -r f; do [ -f "$f" ] && echo "$f"; done
}

MAXLINE=${GUARD_MAX_LINE:-400}

while read -r f; do
  # 1. Very long lines = minified/obfuscated payloads.
  max=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$f")
  [ "$max" -le "$MAXLINE" ] || flag "$f: line of $max chars (limit $MAXLINE) — possible obfuscated code"
  # 2. Whitespace padding used to push code off-screen.
  grep -qE '[[:space:]]{40,}[^[:space:]]' "$f" && flag "$f: 40+ whitespace chars followed by code (hidden-code trick)"
  # 3. Dangerous calls inside config/tooling files.
  case "$f" in
    *.config.*|*/.eslintrc*|*/.babelrc*|*.mjs|*.cjs)
      grep -nE 'child_process|eval[[:space:]]*\(|new[[:space:]]+Function|https?://[^"'"'"' ]*[?&]|\.exec(Sync)?\(|spawn(Sync)?\(' "$f" >/dev/null \
        && flag "$f: config file uses eval/child_process/exec/network" ;;
  esac
  # 3b. javascript-obfuscator-style decoder payload, in ANY file (not just config files).
  # Fingerprint is the *shape* of known malicious samples, not instance-specific identifier names
  # (those are randomized per build): a big hex-string array reached through the obfuscator's
  # self-defending ['push']('shift') array-rotation loop, decoded with a Uint8Array/XOR/TextDecoder
  # pipeline, and then written onto global/globalThis (or module) via a computed property name.
  hits=0
  grep -qE "\['push'\]\([A-Za-z_$][A-Za-z0-9_$]*\['shift'\]\(\)\)" "$f" && hits=$((hits+1))
  grep -qE 'new TextDecoder\(\)' "$f" && hits=$((hits+1))
  grep -qE 'new Uint8Array\(' "$f" && hits=$((hits+1))
  grep -qE "[.a-zA-Z'\"]match['\"]?\]?\(/\.\{1,2\}/g\)" "$f" && hits=$((hits+1))
  grep -qE '\(global,\s*(require|module|exports)' "$f" && hits=$((hits+1))
  grep -qE 'typeof module' "$f" && hits=$((hits+1))
  [ "$hits" -ge 3 ] && flag "$f: matches known obfuscator-payload shape (hex-array decoder + XOR/TextDecoder + global-patching IIFE) — $hits/6 markers"
done < <(files)

# 4. Unknown extensionless/executable-looking files in repo root.
ALLOW='LICENSE|LICENCE|README|Makefile|Dockerfile|Procfile|NOTICE|AUTHORS|CHANGELOG|Gemfile|Rakefile|Justfile'
for f in $(git ls-files -co --exclude-standard | grep -v / ); do
  [ -f "$f" ] || continue
  case "$f" in *.*|.*) continue;; esac
  echo "$f" | grep -qE "^($ALLOW)$" || flag "$f: unexpected extensionless file in repo root"
done

# 5. package.json checks.
if [ -f package.json ]; then
  grep -nE '"(preinstall|install|postinstall|prepare|prepublish)"[[:space:]]*:' package.json >/dev/null \
    && flag "package.json: install lifecycle script present"
  grep -nE '"(dev|build|start|test|lint)"[[:space:]]*:[^,]*node[[:space:]]+[^-"[:space:]][^"]*&&' package.json >/dev/null \
    && flag "package.json: dev/build/start/test/lint runs an extra 'node <file> &&' step first"
  grep -nE '"[^"]+"[[:space:]]*:[[:space:]]*"(git\+|git://|github:|https?://)' package.json >/dev/null \
    && flag "package.json: dependency installed from git/URL instead of the registry"
  grep -nE 'curl|wget|base64|\| *(sh|bash)' package.json >/dev/null \
    && flag "package.json: scripts use curl/wget/base64/pipe-to-shell"
fi

# 6. CI/hook files must not download-and-run.
for f in $(git ls-files -co --exclude-standard .github .githooks 2>/dev/null); do
  grep -nE 'curl[^|]*\|[[:space:]]*(sh|bash)|wget[^|]*\|[[:space:]]*(sh|bash)|base64[[:space:]]+(-d|--decode)' "$f" >/dev/null \
    && flag "$f: downloads and executes remote code"
done

if [ "$bad" -ne 0 ]; then
  echo "" >&2; echo "repo-guard FAILED. Review the files above; do not run install/build until resolved." >&2
  exit 1
fi
echo "✓ repo-guard: clean"
