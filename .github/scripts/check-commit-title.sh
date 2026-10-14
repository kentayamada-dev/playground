#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ] || ! [[ $1 =~ ^[0-9a-f]{40}$ ]]; then
  echo "使い方: $0 <コミットの SHA（40 桁）>" >&2
  exit 1
fi
sha=$1

subject=$(gh api "repos/{owner}/{repo}/commits/$sha" --jq '.commit.message | split("\n")[0]')
# デフォルトブランチにないコミットでは、マージされていない PR も返る https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit
# squash マージのコミットのタイトルは、PR タイトルに「 (#番号)」を付けたものになる（これまでの 35 件で確認。https://github.com/kentayamada-dev/playground/pull/102）
expected=$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq '.[] | select(.merged_at != null) | .title') || true
if [ "${subject% (#*)}" != "$expected" ]; then
  echo "::error::コミットのタイトルが、pr-title で検査した PR タイトルと違います。マージ時に書き換えられた可能性があります"
  echo "コミット: $subject"
  echo "PR: $expected"
  exit 1
fi
echo "コミットのタイトルは PR タイトルと一致しています: $subject"
