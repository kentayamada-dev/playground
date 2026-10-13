#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0

  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/scripts" "$repo/.github/rulesets"
  cp "$BATS_TEST_DIRNAME/sync-github-settings.sh" "$repo/scripts/"
  repo=$(cd "$repo" && pwd -P)

  # gh api の偽物。$STUB_DIR/rulesets.json を GitHub 上のルールセットとして読み書きする
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR/bin"
  PATH="$STUB_DIR/bin:$PATH"
  cat > "$STUB_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pwd -P >> "$STUB_DIR/gh.pwd"
state="$STUB_DIR/rulesets.json"

[ "$1" = api ] && shift
method=GET endpoint='' input='' slurp=false
while [ $# -gt 0 ]; do
  case "$1" in
    -X | --method) method=$2; shift 2 ;;
    --input) input=$2; shift 2 ;;
    --slurp) slurp=true; shift ;;
    --paginate | --silent) shift ;;
    -*) echo "gh スタブ: 未対応のフラグ $1" >&2; exit 1 ;;
    *) endpoint=$1; shift ;;
  esac
done

if [ "$method" = "${STUB_FAIL_METHOD-}" ]; then
  echo "gh: Server Error (HTTP 500)" >&2
  exit 1
fi

case "$method $endpoint" in
  "GET repos/{owner}/{repo}/rulesets?"*)
    filter='.'
    if [[ $endpoint == *includes_parents=false* ]]; then
      filter='map(select(.source_type == "Repository"))'
    fi
    if $slurp; then filter="[$filter]"; fi
    jq -c "$filter" "$state"
    ;;
  "POST repos/{owner}/{repo}/rulesets")
    jq --slurpfile body "$input" \
      '. + [$body[0] + {id: ((map(.id) | max // 0) + 1), source_type: "Repository"}]' \
      "$state" > "$state.new"
    mv "$state.new" "$state"
    ;;
  "PUT repos/{owner}/{repo}/rulesets/"*)
    id=${endpoint##*/}
    if ! jq -e --argjson id "$id" 'any(.id == $id and .source_type == "Repository")' "$state" >/dev/null; then
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    jq --slurpfile body "$input" --argjson id "$id" \
      'map(if .id == $id then $body[0] + {id, source_type} else . end)' \
      "$state" > "$state.new"
    mv "$state.new" "$state"
    ;;
  *)
    echo "gh スタブ: 未対応のリクエスト $method $endpoint" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_DIR/bin/gh"
  echo '[]' > "$STUB_DIR/rulesets.json"
}

given_github_rulesets() {
  echo "$1" > "$STUB_DIR/rulesets.json"
}

define_ruleset() {
  echo "$2" > "$repo/.github/rulesets/$1"
}

assert_github_rulesets() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/rulesets.json" >/dev/null; then
    echo "GitHub 上のルールセット: $(jq -c . "$STUB_DIR/rulesets.json")"
    return 1
  fi
}

@test "同じ名前のルールセットが GitHub になければ作成する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  [[ $output == *"作成: main"* ]]
}

@test "ファイル名ではなく name が同じルールセットを、ID を変えずに定義の内容で置き換える" {
  given_github_rulesets '[{"id": 42, "source_type": "Repository", "name": "main", "enforcement": "disabled", "bypass_actors": [{"actor_id": 5}]}]'
  define_ruleset default-branch.json '{"name": "main", "enforcement": "active", "bypass_actors": []}'

  run -0 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 42, "source_type": "Repository", "name": "main", "enforcement": "active", "bypass_actors": []}]'
  [[ $output == *"更新: main"* ]]
}

@test "2 回実行しても、1 回目と同じ状態になる" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  define_ruleset release.json '{"name": "release", "enforcement": "evaluate"}'
  expected='[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "release", "enforcement": "evaluate"}
  ]'

  run -0 "$repo/scripts/sync-github-settings.sh"
  assert_github_rulesets "$expected"

  run -0 "$repo/scripts/sync-github-settings.sh"
  assert_github_rulesets "$expected"
}

@test "Organization のルールセットと名前が同じでも、それを更新せずリポジトリに作成する" {
  given_github_rulesets '[{"id": 7, "source_type": "Organization", "name": "main", "enforcement": "evaluate"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[
    {"id": 7, "source_type": "Organization", "name": "main", "enforcement": "evaluate"},
    {"id": 8, "source_type": "Repository", "name": "main", "enforcement": "active"}
  ]'
}

@test "ルールセットの定義がなければ、何もせずに成功する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'

  run -0 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
}

@test "JSON として読めない定義があれば、ほかの定義も適用せずに失敗する" {
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"name": "b",'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
  [[ $output == *".github/rulesets/b.json"* ]]
}

@test "name のない定義があれば、ほかの定義も適用せずに失敗する" {
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"enforcement": "active"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
  [[ $output == *".github/rulesets/b.json"* ]]
}

@test "name が空の定義があれば、ほかの定義も適用せずに失敗する" {
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"name": "", "enforcement": "active"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
  [[ $output == *".github/rulesets/b.json"* ]]
}

@test "name が同じ定義が複数あれば、どれも適用せずに失敗する" {
  define_ruleset a.json '{"name": "main", "enforcement": "active"}'
  define_ruleset b.json '{"name": "main", "enforcement": "disabled"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
  [[ $output == *"main"* ]]
}

@test "定義と同じ名前のルールセットが GitHub に複数あれば、ほかの定義も適用せずに失敗する" {
  rulesets='[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "main", "enforcement": "active"}
  ]'
  given_github_rulesets "$rulesets"
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset main.json '{"name": "main", "enforcement": "disabled"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets "$rulesets"
  [[ $output == *"main"* ]]
}

@test "GitHub で名前が重複していても、定義にない名前なら無視して適用する" {
  given_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "legacy", "enforcement": "active"}
  ]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "legacy", "enforcement": "active"},
    {"id": 3, "source_type": "Repository", "name": "main", "enforcement": "active"}
  ]'
}

@test "ルールセットの一覧を取得できなければ、作成せずに失敗する" {
  export STUB_FAIL_METHOD=GET
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
}

@test "ルールセットの更新に失敗したら失敗する" {
  export STUB_FAIL_METHOD=PUT
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 "$repo/scripts/sync-github-settings.sh"

  [[ $output != *"更新: main"* ]]
}

@test "どのディレクトリから実行しても、リポジトリのルートで定義を読み gh を実行する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  cd "$repo/.github"

  run -0 ../scripts/sync-github-settings.sh

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  [ "$(sort -u "$STUB_DIR/gh.pwd")" = "$repo" ]
}

@test "リポジトリにあるルールセットの定義を、すべて GitHub に作成できる" {
  cp "$BATS_TEST_DIRNAME"/../.github/rulesets/*.json "$repo/.github/rulesets/"

  run -0 "$repo/scripts/sync-github-settings.sh"

  [ "$(jq -c 'map(.name) | sort' "$STUB_DIR/rulesets.json")" = "$(jq -cs 'map(.name) | sort' "$repo"/.github/rulesets/*.json)" ]
}
