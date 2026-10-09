#!/usr/bin/env bash
set -euo pipefail

textlint_dir=$(cd "$(dirname "$0")" && pwd)
cd "$textlint_dir/../.."

config="$textlint_dir/.textlintrc.json"
# 設定ファイルが無いときの textlint の案内文にはパスが出ないため、先に確かめてパスを示す
if [ ! -f "$config" ]; then
  echo "textlint の設定ファイルがありません: $config" >&2
  exit 1
fi

# 相対パスだとルールの解決に失敗するため絶対パスで渡す（textlint は path.join した値をそのまま require.resolve する）
"$textlint_dir/node_modules/.bin/textlint" \
  --config "$config" \
  --rules-base-directory "$textlint_dir/node_modules" \
  "**/*.md"
