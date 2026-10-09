#!/usr/bin/env bash
set -euo pipefail

textlint_dir=$(cd "$(dirname "$0")" && pwd)
cd "$textlint_dir/../.."

# 相対パスだとルールの解決に失敗するため絶対パスで渡す（textlint は path.join した値をそのまま require.resolve する）
"$textlint_dir/node_modules/.bin/textlint" \
  --config "$textlint_dir/.textlintrc.json" \
  --rules-base-directory "$textlint_dir/node_modules" \
  "**/*.md"
