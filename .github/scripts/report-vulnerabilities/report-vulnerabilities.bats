#!/usr/bin/env bats
# bats はテストごとに別のプロセスで動かすので、テスト内で変えた変数がほかのテストに漏れないのは意図どおり https://bats-core.readthedocs.io/en/v1.14.0/writing-tests.html
# shellcheck disable=SC2030,SC2031

setup() {
  bats_require_minimum_version 1.5.0

  # shellcheck disable=SC2154 # BATS_TEST_DIRNAME は bats が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定する
  script="${BATS_TEST_DIRNAME}/report-vulnerabilities.sh"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR は bats が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定する
  report="${BATS_TEST_TMPDIR}/osv-scanner.md"
  echo '| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |' >"${report}"
  # 外部リンクの定期検査はこのファイルも読むため、lychee が検査しない example.com をダミーの URL に使う
  # https://github.com/lycheeverse/lychee/blob/lychee-v0.24.2/README.md?plain=1#L175
  export GITHUB_SERVER_URL=https://example.com GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=123

  # gh issue の偽物。GitHub 上の issue を $STUB_DIR/issues.json として読み書きする
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  PATH="${STUB_DIR}/bin:${PATH}"
  cat >"${STUB_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issues="$STUB_DIR/issues.json"

if [ "$1" != issue ]; then
  echo "gh スタブ: 未対応のコマンド $1" >&2
  exit 1
fi
command=$2
shift 2

# STUB_FAIL は「issue サブコマンド」に一致させるパターン
if [ -n "${STUB_FAIL-}" ] && [[ "issue $command" == $STUB_FAIL ]]; then
  echo "gh: Server Error (HTTP 500)" >&2
  exit 1
fi

number='' state=open fields='' filter=. title='' body_file=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state=$2; shift 2 ;;
    --limit) shift 2 ;;
    --json) fields=$2; shift 2 ;;
    --jq) filter=$2; shift 2 ;;
    --title) title=$2; shift 2 ;;
    --body-file) body_file=$2; shift 2 ;;
    -*) echo "gh スタブ: 未対応のフラグ $1" >&2; exit 1 ;;
    *) number=$1; shift ;;
  esac
done
if [ "$body_file" = - ]; then
  body_file="$STUB_DIR/stdin.md"
  cat >"$body_file"
fi

case "$command" in
  list)
    jq -r --arg state "$state" --arg fields "$fields" \
      "map(select(\$state == \"all\" or .state == \$state)) | map(with_entries(select(.key | IN(\$fields | split(\",\")[])))) | $filter" \
      "$issues"
    ;;
  edit)
    if ! jq -e --argjson number "$number" 'any(.number == $number)' "$issues" >/dev/null; then
      echo "gh: Could not resolve to an issue with the number of $number" >&2
      exit 1
    fi
    jq --argjson number "$number" --rawfile body "$body_file" \
      'map(if .number == $number then .body = $body else . end)' "$issues" >"$issues.new"
    mv "$issues.new" "$issues"
    ;;
  create)
    jq --arg title "$title" --rawfile body "$body_file" \
      '. + [{number: ((map(.number) | max // 0) + 1), title: $title, state: "open", body: $body}]' "$issues" >"$issues.new"
    mv "$issues.new" "$issues"
    ;;
  *)
    echo "gh スタブ: 未対応のサブコマンド issue $command" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${STUB_DIR}/bin/gh"
  echo '[]' >"${STUB_DIR}/issues.json"
}

given_github_issues() {
  echo "$1" >"${STUB_DIR}/issues.json"
}

assert_github_issues() {
  if ! jq -e --argjson expected "$1" '. == $expected' "${STUB_DIR}/issues.json" >/dev/null; then
    local actual
    actual=$(jq -c . "${STUB_DIR}/issues.json")
    echo "GitHub 上の issue: ${actual}"
    return 1
  fi
}

@test "同じタイトルの issue が開いていなければ、実行の URL とレポートを本文にして issue を作る" {
  given_github_issues '[{"number": 22, "title": "chore(deps): 依存関係の更新状況", "state": "open", "body": "ダッシュボード"}]'

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 22, "title": "chore(deps): 依存関係の更新状況", "state": "open", "body": "ダッシュボード"},
    {"number": 23, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。同じ内容をもう一度スキャンした結果です。\n\n| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |\n"}
  ]'
}

@test "同じタイトルの issue が開いていれば、新しく作らずに本文を書き換える" {
  given_github_issues '[
    {"number": 22, "title": "chore(deps): 依存関係の更新状況", "state": "open", "body": "ダッシュボード"},
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "前回の結果"}
  ]'

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 22, "title": "chore(deps): 依存関係の更新状況", "state": "open", "body": "ダッシュボード"},
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。同じ内容をもう一度スキャンした結果です。\n\n| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |\n"}
  ]'
}

@test "同じタイトルの issue が閉じていれば、書き換えずに新しく作る" {
  given_github_issues '[{"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "closed", "body": "前回の結果"}]'

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "closed", "body": "前回の結果"},
    {"number": 301, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。同じ内容をもう一度スキャンした結果です。\n\n| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |\n"}
  ]'
}

@test "タイトルの一部だけが一致する issue は書き換えずに、新しく作る" {
  given_github_issues '[{"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す（fast-uri）", "state": "open", "body": "手で立てた issue"}]'

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す（fast-uri）", "state": "open", "body": "手で立てた issue"},
    {"number": 301, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。同じ内容をもう一度スキャンした結果です。\n\n| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |\n"}
  ]'
}

@test "同じタイトルの issue が複数開いていれば、新しく作らずに最も新しいものだけを書き換える" {
  given_github_issues '[
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "前々回の結果"},
    {"number": 305, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "前回の結果"}
  ]'

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 300, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "前々回の結果"},
    {"number": 305, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。同じ内容をもう一度スキャンした結果です。\n\n| https://example.com/GHSA-1 | npm | fast-uri | 3.1.9 | 3.1.8 |\n"}
  ]'
}

@test "レポートが空なら、一覧の代わりにログを確認するよう書いて issue を作る" {
  : >"${report}"

  run -0 "${script}" "${report}"

  assert_github_issues '[
    {"number": 1, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。もう一度スキャンした結果を取得できなかったため、実行のログで原因を確認してください。\n"}
  ]'
}

@test "レポートのファイルがなければ、一覧の代わりにログを確認するよう書いて issue を作る" {
  run -0 "${script}" "${BATS_TEST_TMPDIR}/missing.md"

  assert_github_issues '[
    {"number": 1, "title": "fix(deps): 依存関係の検査で見つかった脆弱性を直す", "state": "open", "body": "[依存関係の脆弱性の検査](https://example.com/owner/repo/actions/runs/123) が失敗しました。もう一度スキャンした結果を取得できなかったため、実行のログで原因を確認してください。\n"}
  ]'
}

@test "issue の一覧を取得できなければ、issue を作らずに失敗する" {
  export STUB_FAIL="issue list"

  run -1 "${script}" "${report}"

  assert_github_issues '[]'
}

@test "issue を作れなければ、失敗する" {
  export STUB_FAIL="issue create"

  run -1 "${script}" "${report}"

  assert_github_issues '[]'
}
