#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "使い方: $0 {<lychee の Markdown のレポート> | --resolved}" >&2
  exit 1
fi

title='docs: 外部リンクの定期検査で見つかったリンク切れを直す'
# GITHUB_* は GitHub Actions が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定するため、:? で設定されている前提を示す https://github.com/koalaman/shellcheck/blob/v0.11.0/src/ShellCheck/Analytics.hs#L256-L261
run_url="${GITHUB_SERVER_URL:?}/${GITHUB_REPOSITORY:?}/actions/runs/${GITHUB_RUN_ID:?}"

if [[ $1 == --resolved ]]; then
  # 開いている issue が複数あっても、どれも同じ検査の失敗のため、最も新しいものだけでなくすべて閉じる
  numbers=$(TITLE=${title} gh issue list --state open --limit 1000 --json number,title --jq '.[] | select(.title == env.TITLE) | .number')
  for number in ${numbers}; do
    gh issue close "${number}" --reason completed --comment "[外部リンクの定期検査](${run_url}) で、すべてのリンクが通りました。"
  done
  exit 0
fi
report=$1

body="[外部リンクの定期検査](${run_url}) で、次のリンクが通りませんでした。

$(cat "${report}")"

# 失敗のたびに issue を増やさず、開いている issue があれば本文を最新の結果に書き換える
number=$(TITLE=${title} gh issue list --state open --limit 1000 --json number,title --jq '[.[] | select(.title == env.TITLE) | .number] | max // empty')
if [[ -n ${number} ]]; then
  gh issue edit "${number}" --body-file - <<<"${body}"
else
  gh issue create --title "${title}" --body-file - <<<"${body}"
fi
