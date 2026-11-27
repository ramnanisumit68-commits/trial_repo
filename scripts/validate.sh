#!/usr/bin/env bash
# Validation run on push (git pre-push hook) and on push/PR/merge (GitHub Actions).
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $1" >&2; exit 1; }

echo "▶ 1/4 Checking for suspicious files"
# Config/script files with very long lines usually mean hidden/obfuscated code.
for f in postcss.config.mjs next.config.ts next.config.js next.config.mjs init; do
  [ -f "$f" ] || continue
  max=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$f")
  [ "$max" -le 300 ] || fail "$f has a line of $max chars (possible obfuscated code)"
done
# npm scripts must not run extra local files before the framework commands.
if grep -nE '"(dev|build|start)":[^,]*node [^n"]' package.json >/dev/null; then
  fail "package.json dev/build/start scripts run an extra 'node <file>' step"
fi
if grep -nE '"(preinstall|install|postinstall|prepare)"' package.json >/dev/null; then
  fail "package.json defines an install lifecycle script"
fi

echo "▶ 2/4 Installing dependencies"
npm ci --ignore-scripts --no-audit --no-fund

echo "▶ 3/4 Type check"
npx tsc --noEmit

echo "▶ 4/4 Production build"
npx next build

echo "✓ All checks passed"
