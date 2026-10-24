#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "使い方: $0 <osv-scanner の Markdown のレポート>" >&2
  exit 1
fi
report=$1

title='fix(deps): 依存関係の検査で見つかった脆弱性を直す'
# GITHUB_* は GitHub Actions が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定するため、:? で設定されている前提を示す
run_link="[依存関係の脆弱性の検査](${GITHUB_SERVER_URL:?}/${GITHUB_REPOSITORY:?}/actions/runs/${GITHUB_RUN_ID:?})"
# スキャナー自体が失敗するとレポートが書かれないが、検査が止まっていることも知らせるため、一覧なしで issue を作る
if [[ -s ${report} ]]; then
  body="${run_link} が失敗しました。同じ内容をもう一度スキャンした結果です。

$(cat "${report}")"
else
  body="${run_link} が失敗しました。もう一度スキャンした結果を取得できなかったため、実行のログで原因を確認してください。"
fi

# 失敗のたびに issue を増やさず、開いている issue があれば本文を最新の結果に書き換える
number=$(TITLE=${title} gh issue list --state open --limit 1000 --json number,title --jq '[.[] | select(.title == env.TITLE) | .number] | max // empty')
if [[ -n ${number} ]]; then
  gh issue edit "${number}" --body-file - <<<"${body}"
else
  gh issue create --title "${title}" --body-file - <<<"${body}"
fi
