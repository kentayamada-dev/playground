#!/usr/bin/env bash
set -euo pipefail

textlint_dir=$(cd "$(dirname "$0")" && pwd)
cd "$textlint_dir/../.."

report=$(mktemp)
status=0
# 相対パスだとルールの解決に失敗するため絶対パスで渡す（textlint は path.join した値をそのまま require.resolve する）
"$textlint_dir/node_modules/.bin/textlint" \
  --rules-base-directory "$textlint_dir/node_modules" \
  -f checkstyle "**/*.md" > "$report" || status=$?
# 2 はルールの読み込み失敗などの異常終了。指摘 0 件として通さないよう、ここで失敗させる
if [ "$status" -ge 2 ]; then
  exit "$status"
fi
reviewdog -f=checkstyle -name=textlint -reporter=github-pr-annotations \
  -filter-mode=added -fail-level=error < "$report"
