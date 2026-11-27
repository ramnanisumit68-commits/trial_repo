#!/usr/bin/env bash
# Full validation (push / PR / merge). Always runs guard first, before any npm code executes.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/guard.sh
if [ -f package.json ]; then
  [ -f package-lock.json ] && npm ci --ignore-scripts --no-audit --no-fund || npm install --ignore-scripts --no-audit --no-fund
  npm audit --audit-level=high || echo "⚠ npm audit reported issues (not blocking)"
  npx --no-install tsc --noEmit 2>/dev/null || { [ -f tsconfig.json ] && { echo "✗ type check failed"; exit 1; } || true; }
  npm run --if-present lint
  npm run --if-present test
  npm run --if-present build
fi
echo "✓ validate: all checks passed"
