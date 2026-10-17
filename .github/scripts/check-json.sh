#!/usr/bin/env bash
set -euo pipefail

# jq がないと検査（if ! jq）がすべてのファイルで失敗し、JSON が壊れていると誤って示すため、先に確かめる
if ! command -v jq >/dev/null; then
  echo "エラー: jq が見つかりません。インストールしてから実行してください" >&2
  exit 1
fi

cd "$(dirname "$0")/../.."
# Claude Code は JSON として読めない設定ファイルを丸ごと飛ばすため、マージ前に検出する https://code.claude.com/docs/en/settings#fix-a-broken-settings-file
# jq は空のファイルや値が複数並ぶファイルも読めるため、値がちょうど 1 つか（https://www.rfc-editor.org/rfc/rfc8259#section-2）を確かめる
git ls-files -z '*.json' | {
  status=0
  while IFS= read -r -d '' file; do
    if ! jq -s -e 'length == 1' "$file" >/dev/null; then
      # GitHub Actions では、このワークフローコマンドでファイルにアノテーションが付く https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#setting-an-error-message
      echo "::error file=$file::JSON として読めないか、値がちょうど 1 つではありません"
      status=1
    fi
  done
  exit "$status"
}
