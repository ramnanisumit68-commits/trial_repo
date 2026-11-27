#!/usr/bin/env bash
# repo-guard purge: removes suspicious files that a MERGE brings in. Every removed file is first
# copied (non-executable) to .git/guard-quarantine/<timestamp>/ so nothing is lost.
# Modes:  --index   (pre-merge-commit: files staged by the merge; deletion is staged for a follow-up commit)
#         --merged  (post-merge: files changed between ORIG_HEAD and HEAD; deletion is left staged)
# Disable with GUARD_PURGE=0.  Tune long-line limit with GUARD_MAX_LINE.
set -uo pipefail
[ "${GUARD_PURGE:-1}" = "0" ] && exit 0
mode="${1:---merged}"
cd "$(git rev-parse --show-toplevel)"
MAXLINE=${GUARD_MAX_LINE:-400}
ALLOW='LICENSE|LICENCE|README|Makefile|Dockerfile|Procfile|NOTICE|AUTHORS|CHANGELOG|Gemfile|Rakefile|Justfile'
# Never purge the guard's own files or lockfiles/binaries/vendored dirs.
SKIP='(^|/)(node_modules|\.next|dist|build|public|vendor)/|^scripts/(guard|purge|validate)\.sh$|^\.githooks/|package-lock\.json$|yarn\.lock$|pnpm-lock\.yaml$|\.(png|jpe?g|gif|svg|ico|woff2?|ttf|pdf|map|min\.js)$'

case "$mode" in
  --index)  list=$(git diff --cached --name-only --diff-filter=AM HEAD) ;;
  --merged) git rev-parse -q --verify ORIG_HEAD >/dev/null || exit 0
            list=$(git diff --name-only --diff-filter=AM ORIG_HEAD HEAD) ;;
  *) echo "usage: purge.sh --index|--merged" >&2; exit 2 ;;
esac

reason() {  # prints a reason if file $1 is suspicious
  local f="$1" max
  case "$f" in */*) ;; *.*|.*) ;; *) echo "$f" | grep -qE "^($ALLOW)$" || { echo "unknown extensionless root file"; return; } ;; esac
  max=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$f")
  [ "$max" -le "$MAXLINE" ] || { echo "line of $max chars (obfuscated/minified)"; return; }
  grep -qE '[[:space:]]{40,}[^[:space:]]' "$f" && { echo "whitespace-padded hidden code"; return; }
  case "$f" in *.config.*|*.mjs|*.cjs|.eslintrc*|.babelrc*)
    grep -qE 'child_process|eval[[:space:]]*\(|new[[:space:]]+Function|\.exec(Sync)?\(|spawn(Sync)?\(' "$f" \
      && { echo "config file uses eval/child_process/exec"; return; } ;; esac
  # Known obfuscator-payload shape: hex-array decoder + self-defend rotation + XOR/TextDecoder + global write.
  local hits=0
  grep -qE "\['push'\]\([A-Za-z_$][A-Za-z0-9_$]*\['shift'\]\(\)\)" "$f" && hits=$((hits+1))
  grep -qE 'new TextDecoder\(\)' "$f" && hits=$((hits+1))
  grep -qE 'new Uint8Array\(' "$f" && hits=$((hits+1))
  grep -qE "[.a-zA-Z'\"]match['\"]?\]?\(/\.\{1,2\}/g\)" "$f" && hits=$((hits+1))
  grep -qE '\(global,\s*(require|module|exports)' "$f" && hits=$((hits+1))
  grep -qE 'typeof module' "$f" && hits=$((hits+1))
  [ "$hits" -ge 3 ] && { echo "matches known obfuscator-payload shape ($hits/6 markers)"; return; }
}

q="$(git rev-parse --git-dir)/guard-quarantine/$(date +%Y%m%d-%H%M%S)"
removed=0
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  echo "$f" | grep -qE "$SKIP" && continue
  r=$(reason "$f"); [ -n "$r" ] || continue
  mkdir -p "$q/$(dirname "$f")" && cp "$f" "$q/$f.txt" && chmod 444 "$q/$f.txt"
  git rm -qf -- "$f" && { echo "🗑  removed $f — $r (copy: $q/$f.txt)" >&2; removed=$((removed+1)); }
done <<< "$list"

if [ "$removed" -gt 0 ]; then
  echo "repo-guard purge: removed $removed suspicious file(s) brought in by the merge." >&2
  [ "$mode" = "--merged" ] && echo "   Deletions are staged — review, then 'git commit'." >&2
fi
exit 0
