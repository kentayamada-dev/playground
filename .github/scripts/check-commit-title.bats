#!/usr/bin/env bats
# bats はテストごとに別のプロセスで動かすので、テスト内で変えた変数がほかのテストに漏れないのは意図どおり https://bats-core.readthedocs.io/en/v1.14.0/writing-tests.html
# shellcheck disable=SC2030,SC2031

setup() {
  bats_require_minimum_version 1.5.0

  script="$BATS_TEST_DIRNAME/check-commit-title.sh"
  sha=0123456789abcdef0123456789abcdef01234567

  # gh api の偽物。$STUB_DIR の commit.json と pulls.json を、$STUB_SHA のコミットとその PR の一覧として返す
  export STUB_DIR="$BATS_TEST_TMPDIR/stub" STUB_SHA="$sha"
  mkdir -p "$STUB_DIR/bin"
  PATH="$STUB_DIR/bin:$PATH"
  cat > "$STUB_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] && shift
endpoint='' filter=.
while [ $# -gt 0 ]; do
  case "$1" in
    -q | --jq) filter=$2; shift 2 ;;
    -*) echo "gh スタブ: 未対応のフラグ $1" >&2; exit 1 ;;
    *) endpoint=$1; shift ;;
  esac
done

# STUB_FAIL はエンドポイントに一致させるパターン
if [ -n "${STUB_FAIL-}" ] && [[ $endpoint == $STUB_FAIL ]]; then
  echo "gh: Server Error (HTTP 500)" >&2
  exit 1
fi

case "$endpoint" in
  "repos/{owner}/{repo}/commits/$STUB_SHA") response="$STUB_DIR/commit.json" ;;
  "repos/{owner}/{repo}/commits/$STUB_SHA/pulls") response="$STUB_DIR/pulls.json" ;;
  *) echo "gh スタブ: 未対応のリクエスト $endpoint" >&2; exit 1 ;;
esac
# gh の --jq と同じく、文字列は引用符を付けずに出力する
jq -r "$filter" "$response"
EOF
  chmod +x "$STUB_DIR/bin/gh"
}

given_commit_message() {
  jq -n --arg message "$1" '{commit: {message: $message}}' > "$STUB_DIR/commit.json"
}

given_pulls() {
  echo "$1" > "$STUB_DIR/pulls.json"
}

@test "コミットのタイトルが「PR タイトル (#番号)」と一致すれば成功する" {
  given_commit_message 'feat: ログインを追加する (#12)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -0 "$script" "$sha"
}

@test "コミットメッセージに本文があっても、1 行目だけを比べる" {
  given_commit_message $'feat: ログインを追加する (#12)\n\n本文の 1 行目'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -0 "$script" "$sha"
}

@test "コミットのタイトルが PR タイトルと違えば失敗し、両方を表示する" {
  given_commit_message 'feat: マージ時に書き換えたタイトル (#12)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -1 "$script" "$sha"

  [[ $output == *"コミット: feat: マージ時に書き換えたタイトル (#12)"* ]]
  [[ $output == *"PR: feat: ログインを追加する (#12)"* ]]
}

@test "タイトルが同じでも、PR の番号が違えば失敗する" {
  given_commit_message 'feat: ログインを追加する (#13)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -1 "$script" "$sha"
}

@test "コミットをマージした PR がなければ失敗する" {
  given_commit_message 'feat: ログインを追加する (#12)'
  given_pulls '[]'

  run -1 "$script" "$sha"

  [[ $output == *"コミット $sha をマージした PR が見つかりません"* ]]
}

@test "マージされていない PR は、タイトルが一致しても照合に使わない" {
  given_commit_message 'feat: ログインを追加する (#12)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": null}]'

  run -1 "$script" "$sha"

  [[ $output == *"コミット $sha をマージした PR が見つかりません"* ]]
}

@test "コミットを取得できなければ、照合せずに失敗する" {
  export STUB_FAIL="repos/{owner}/{repo}/commits/$sha"
  given_commit_message 'feat: ログインを追加する (#12)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -1 "$script" "$sha"

  [[ $output == *"HTTP 500"* ]]
  [[ $output != *"::error::"* ]]
}

@test "PR の一覧を取得できなければ、照合せずに失敗する" {
  export STUB_FAIL="*/pulls"
  given_commit_message 'feat: ログインを追加する (#12)'
  given_pulls '[{"number": 12, "title": "feat: ログインを追加する", "merged_at": "2026-10-14T00:00:00Z"}]'

  run -1 "$script" "$sha"

  [[ $output == *"HTTP 500"* ]]
  [[ $output != *"::error::"* ]]
}

@test "SHA を渡さなければ、使い方を表示して失敗する" {
  run -1 "$script"

  [[ $output == *"使い方:"* ]]
}

@test "40 桁の SHA でなければ、使い方を表示して失敗する" {
  run -1 "$script" main

  [[ $output == *"使い方:"* ]]
}
