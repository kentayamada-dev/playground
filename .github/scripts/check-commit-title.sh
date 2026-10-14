#!/usr/bin/env bash
set -euo pipefail

sha=$1

subject=$(gh api "repos/{owner}/{repo}/commits/$sha" --jq '.commit.message') || true
# デフォルトブランチにないコミットでは、マージされていない PR も返る https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit
# squash マージのコミットのタイトルは、PR タイトルに「 (#番号)」を付けたものになる（これまでの 35 件で確認。https://github.com/kentayamada-dev/playground/pull/102）
expected=$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq '.[] | "\(.title) (#\(.number))"')
if [ -z "$expected" ]; then
  echo "::error::コミット $sha をマージした PR が見つかりません"
  exit 1
fi
if [ "$subject" != "$expected" ]; then
  echo "::error::コミットのタイトルが、pr-title で検査した PR タイトルと違います。マージ時に書き換えられた可能性があります"
  echo "コミット: $subject"
  echo "PR: $expected"
  exit 1
fi
echo "コミットのタイトルは PR タイトルと一致しています: $subject"
