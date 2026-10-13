#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0

  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/.github/scripts" "$repo/.github/settings/rulesets"
  cp "$BATS_TEST_DIRNAME/sync-github-settings.sh" "$repo/.github/scripts/"
  echo '{}' > "$repo/.github/settings/repository.json"
  echo '{}' > "$repo/.github/settings/security.json"
  echo '{}' > "$repo/.github/settings/actions.json"
  echo '[]' > "$repo/.github/settings/labels.json"
  repo=$(cd "$repo" && pwd -P)

  # gh api の偽物。$STUB_DIR 配下の JSON を、GitHub 上のルールセット・リポジトリの設定・セキュリティの設定として読み書きする
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR/bin"
  PATH="$STUB_DIR/bin:$PATH"
  cat > "$STUB_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pwd -P >> "$STUB_DIR/gh.pwd"
github="$STUB_DIR/"
# gh と同じく、GH_REPO があればカレントディレクトリのリポジトリではなく、そのリポジトリを操作する
if [ -n "${GH_REPO-}" ]; then
  github="$STUB_DIR/other-repo-"
fi
state="${github}rulesets.json"
repository="${github}repository.json"
security="${github}security.json"
code_scanning="${github}code-scanning.json"
actions_permissions="${github}actions-permissions.json"
selected_actions="${github}selected-actions.json"
labels="${github}labels.json"
fork_pr_approval="${github}fork-pr-approval.json"
workflow_permissions="${github}workflow-permissions.json"

[ "$1" = api ] && shift
method=GET endpoint='' input='' slurp=false headers=''
while [ $# -gt 0 ]; do
  case "$1" in
    -X | --method) method=$2; shift 2 ;;
    -H | --header) headers="$headers$2;"; shift 2 ;;
    --input) input=$2; shift 2 ;;
    --slurp) slurp=true; shift ;;
    --paginate | --silent) shift ;;
    -*) echo "gh スタブ: 未対応のフラグ $1" >&2; exit 1 ;;
    *) endpoint=$1; shift ;;
  esac
done
# gh と同じく、--input - なら本文を標準入力から読む
if [ "$input" = - ]; then
  input="$STUB_DIR/stdin.json"
  cat > "$input"
fi

# GitHub の GET の応答はキャッシュされうるため、Cache-Control: no-cache がなければ、.stale.json があればその古い応答を返す
fresh_or_stale() {
  if [[ $headers != *"Cache-Control: no-cache;"* ]] && [ -f "${1%.json}.stale.json" ]; then
    echo "${1%.json}.stale.json"
  else
    echo "$1"
  fi
}

# STUB_FAIL は「メソッド エンドポイント」に一致させるパターン
if [ -n "${STUB_FAIL-}" ] && [[ "$method $endpoint" == $STUB_FAIL ]]; then
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
    jq -c "$filter" "$(fresh_or_stale "$state")"
    ;;
  "POST repos/{owner}/{repo}/rulesets")
    # 作成と削除の順序で ID が変わらないよう、削除した ID を使い回さず連番で振る
    id=$(cat "$STUB_DIR/next_id")
    echo $((id + 1)) > "$STUB_DIR/next_id"
    jq --slurpfile body "$input" --argjson id "$id" \
      '. + [$body[0] + {id: $id, source_type: "Repository"}]' \
      "$state" > "$state.new"
    mv "$state.new" "$state"
    ;;
  "PUT repos/{owner}/{repo}/rulesets/"* | "DELETE repos/{owner}/{repo}/rulesets/"*)
    id=${endpoint##*/}
    if ! jq -e --argjson id "$id" 'any(.id == $id and .source_type == "Repository")' "$state" >/dev/null; then
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    if [ "$method" = PUT ]; then
      jq --slurpfile body "$input" --argjson id "$id" \
        'map(if .id == $id then $body[0] + {id, source_type} else . end)' \
        "$state" > "$state.new"
    else
      jq --argjson id "$id" 'map(select(.id != $id))' "$state" > "$state.new"
    fi
    mv "$state.new" "$state"
    ;;
  "GET repos/{owner}/{repo}/labels?"*)
    if $slurp; then jq -c '[.]' "$(fresh_or_stale "$labels")"; else jq -c . "$(fresh_or_stale "$labels")"; fi
    ;;
  "POST repos/{owner}/{repo}/labels")
    if jq -e --slurpfile body "$input" 'any(.name == $body[0].name)' "$labels" >/dev/null; then
      echo "gh: Validation Failed (HTTP 422)" >&2
      exit 1
    fi
    jq --slurpfile body "$input" '. + [$body[0]]' "$labels" > "$labels.new"
    mv "$labels.new" "$labels"
    ;;
  "PATCH repos/{owner}/{repo}/labels/"* | "DELETE repos/{owner}/{repo}/labels/"*)
    # パスのラベル名は URL エンコードされている
    encoded=${endpoint##*/}
    if ! jq -e --arg encoded "$encoded" 'any((.name | @uri) == $encoded)' "$labels" >/dev/null; then
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    if [ "$method" = PATCH ]; then
      jq --slurpfile body "$input" --arg encoded "$encoded" \
        'map(if (.name | @uri) == $encoded then . + $body[0] else . end)' "$labels" > "$labels.new"
    else
      jq --arg encoded "$encoded" 'map(select((.name | @uri) != $encoded))' "$labels" > "$labels.new"
    fi
    mv "$labels.new" "$labels"
    ;;
  "PUT repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval")
    cp "$input" "$fork_pr_approval"
    ;;
  "PUT repos/{owner}/{repo}/actions/permissions/workflow")
    jq -s '.[0] + .[1]' "$workflow_permissions" "$input" > "$workflow_permissions.new"
    mv "$workflow_permissions.new" "$workflow_permissions"
    ;;
  "PUT repos/{owner}/{repo}/actions/permissions")
    jq -s '.[0] + .[1]' "$actions_permissions" "$input" > "$actions_permissions.new"
    mv "$actions_permissions.new" "$actions_permissions"
    ;;
  "PUT repos/{owner}/{repo}/actions/permissions/selected-actions")
    # GitHub と同じく、allowed_actions が selected でなければ受け付けない
    if ! jq -e '.allowed_actions == "selected"' "$actions_permissions" >/dev/null; then
      echo "gh: allowed_actions must be selected (HTTP 409)" >&2
      exit 1
    fi
    cp "$input" "$selected_actions"
    ;;
  "PATCH repos/{owner}/{repo}")
    jq -s '.[0] + .[1]' "$repository" "$input" > "$repository.new"
    mv "$repository.new" "$repository"
    ;;
  "PUT repos/{owner}/{repo}/"* | "DELETE repos/{owner}/{repo}/"*)
    feature=${endpoint#repos/\{owner\}/\{repo\}/}
    case "$feature" in
      vulnerability-alerts | automated-security-fixes | private-vulnerability-reporting | immutable-releases) ;;
      *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    esac
    jq --arg key "${feature//-/_}" --argjson enabled "$([ "$method" = PUT ] && echo true || echo false)" \
      '.[$key] = $enabled' "$security" > "$security.new"
    mv "$security.new" "$security"
    ;;
  "GET repos/{owner}/{repo}/code-scanning/default-setup")
    jq -c 'del(.runs)' "$(fresh_or_stale "$code_scanning")"
    ;;
  "PATCH repos/{owner}/{repo}/code-scanning/default-setup")
    # 設定の更新を受け付けると解析を始めたとみなし、その回数を runs に数える
    jq --slurpfile body "$input" '. + $body[0] | .runs += 1' "$code_scanning" > "$code_scanning.new"
    mv "$code_scanning.new" "$code_scanning"
    ;;
  *)
    echo "gh スタブ: 未対応のリクエスト $method $endpoint" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_DIR/bin/gh"
  echo '[]' > "$STUB_DIR/rulesets.json"
  echo '{}' > "$STUB_DIR/repository.json"
  echo '{}' > "$STUB_DIR/security.json"
  echo '{"state": "not-configured", "query_suite": "default", "languages": ["actions"], "runs": 0}' > "$STUB_DIR/code-scanning.json"
  echo '{"enabled": true, "allowed_actions": "all", "sha_pinning_required": false}' > "$STUB_DIR/actions-permissions.json"
  echo '{}' > "$STUB_DIR/selected-actions.json"
  echo '[]' > "$STUB_DIR/labels.json"
  echo '{"approval_policy": "first_time_contributors"}' > "$STUB_DIR/fork-pr-approval.json"
  echo '{"default_workflow_permissions": "write", "can_approve_pull_request_reviews": true}' > "$STUB_DIR/workflow-permissions.json"
  echo 100 > "$STUB_DIR/next_id"
}

given_github_rulesets() {
  echo "$1" > "$STUB_DIR/rulesets.json"
}

given_github_repository() {
  echo "$1" > "$STUB_DIR/repository.json"
}

define_repository() {
  echo "$1" > "$repo/.github/settings/repository.json"
}

assert_github_repository() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/repository.json" >/dev/null; then
    echo "GitHub 上のリポジトリの設定: $(jq -c . "$STUB_DIR/repository.json")"
    return 1
  fi
}

given_github_security() {
  echo "$1" > "$STUB_DIR/security.json"
}

given_github_labels() {
  echo "$1" > "$STUB_DIR/labels.json"
}

define_labels() {
  echo "$1" > "$repo/.github/settings/labels.json"
}

assert_github_labels() {
  if ! jq -e --argjson expected "$1" 'sort_by(.name) == ($expected | sort_by(.name))' "$STUB_DIR/labels.json" >/dev/null; then
    echo "GitHub 上のラベル: $(jq -c . "$STUB_DIR/labels.json")"
    return 1
  fi
}

assert_github_fork_pr_approval() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/fork-pr-approval.json" >/dev/null; then
    echo "GitHub 上のフォークからの PR の承認の方針: $(jq -c . "$STUB_DIR/fork-pr-approval.json")"
    return 1
  fi
}

assert_github_workflow_permissions() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/workflow-permissions.json" >/dev/null; then
    echo "GitHub 上の GITHUB_TOKEN の既定の権限: $(jq -c . "$STUB_DIR/workflow-permissions.json")"
    return 1
  fi
}

define_actions() {
  echo "$1" > "$repo/.github/settings/actions.json"
}

assert_github_actions() {
  local actual
  actual=$(jq -cs '{permissions: .[0], selected_actions: .[1]}' "$STUB_DIR/actions-permissions.json" "$STUB_DIR/selected-actions.json")
  if ! jq -e --argjson expected "$1" '. == $expected' <<<"$actual" >/dev/null; then
    echo "GitHub 上の Actions の設定: $actual"
    return 1
  fi
}

given_github_code_scanning() {
  echo "$1" > "$STUB_DIR/code-scanning.json"
}

define_security() {
  echo "$1" > "$repo/.github/settings/security.json"
}

assert_github_security() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/security.json" >/dev/null; then
    echo "GitHub 上のセキュリティの設定: $(jq -c . "$STUB_DIR/security.json")"
    return 1
  fi
}

# runs は、CodeQL の解析を始めた回数
assert_github_code_scanning() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/code-scanning.json" >/dev/null; then
    echo "GitHub 上の CodeQL のデフォルトセットアップ: $(jq -c . "$STUB_DIR/code-scanning.json")"
    return 1
  fi
}

define_ruleset() {
  echo "$2" > "$repo/.github/settings/rulesets/$1"
}

assert_github_rulesets() {
  if ! jq -e --argjson expected "$1" '. == $expected' "$STUB_DIR/rulesets.json" >/dev/null; then
    echo "GitHub 上のルールセット: $(jq -c . "$STUB_DIR/rulesets.json")"
    return 1
  fi
}

# スクリプトが使うコマンドのうち、指定したものだけがない PATH を作る
path_without() {
  local dir="$BATS_TEST_TMPDIR/path-without-$1" command
  mkdir -p "$dir"
  for command in bash dirname gh jq; do
    if [ "$command" != "$1" ]; then
      ln -s "$(command -v "$command")" "$dir/$command"
    fi
  done
  echo "$dir"
}

@test "同じ名前のルールセットが GitHub になければ作成する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  [[ $output == *"作成: ルールセット main (.github/settings/rulesets/main.json)"* ]]
}

@test "ファイル名ではなく name が同じルールセットを、ID を変えずに定義の内容で置き換える" {
  given_github_rulesets '[{"id": 42, "source_type": "Repository", "name": "main", "enforcement": "disabled", "bypass_actors": [{"actor_id": 5}]}]'
  define_ruleset default-branch.json '{"name": "main", "enforcement": "active", "bypass_actors": []}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 42, "source_type": "Repository", "name": "main", "enforcement": "active", "bypass_actors": []}]'
}

@test "2 回実行しても、1 回目と同じ状態になる" {
  given_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"},
    {"id": 2, "source_type": "Repository", "name": "legacy", "enforcement": "active"}
  ]'
  given_github_repository '{"has_wiki": true, "allow_merge_commit": true}'
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}, {"name": "wontfix", "color": "ffffff", "description": "Will not be worked on"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  define_ruleset release.json '{"name": "release", "enforcement": "evaluate"}'
  define_repository '{"has_wiki": false, "allow_merge_commit": false}'
  define_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}, {"name": "maintenance", "color": "fbca04", "description": "保守作業"}]'
  expected_labels='[{"name": "bug", "color": "d73a4a", "description": "不具合"}, {"name": "maintenance", "color": "fbca04", "description": "保守作業"}]'
  expected='[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 100, "source_type": "Repository", "name": "release", "enforcement": "evaluate"}
  ]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"
  assert_github_rulesets "$expected"
  assert_github_repository '{"has_wiki": false, "allow_merge_commit": false}'
  assert_github_labels "$expected_labels"

  run -0 "$repo/.github/scripts/sync-github-settings.sh"
  assert_github_rulesets "$expected"
  assert_github_repository '{"has_wiki": false, "allow_merge_commit": false}'
  assert_github_labels "$expected_labels"
}

@test "Organization のルールセットと名前が同じでも、それを更新せずリポジトリに作成する" {
  given_github_rulesets '[{"id": 7, "source_type": "Organization", "name": "main", "enforcement": "evaluate"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[
    {"id": 7, "source_type": "Organization", "name": "main", "enforcement": "evaluate"},
    {"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}
  ]'
}

@test "定義にないルールセットは削除する" {
  given_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "legacy", "enforcement": "active"}
  ]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  [[ $output == *"削除: ルールセット legacy"* ]]
}

@test "定義の name を変えると、古い名前のルールセットを残さず新しい名前で作成する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  define_ruleset main.json '{"name": "default-branch", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 100, "source_type": "Repository", "name": "default-branch", "enforcement": "active"}]'
}

@test "Organization のルールセットは、定義になくても削除しない" {
  given_github_rulesets '[{"id": 7, "source_type": "Organization", "name": "org-wide", "enforcement": "active"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[
    {"id": 7, "source_type": "Organization", "name": "org-wide", "enforcement": "active"},
    {"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}
  ]'
}

@test "ルールセットの定義がなければ、リポジトリのルールセットをすべて削除する" {
  given_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 7, "source_type": "Organization", "name": "org-wide", "enforcement": "active"}
  ]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 7, "source_type": "Organization", "name": "org-wide", "enforcement": "active"}]'
}

@test "JSON として読めない定義があれば、ほかの定義も適用せず、何も削除せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"name": "b",'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/rulesets/b.json"* ]]
}

@test "name のない定義があれば、ほかの定義も適用せず、何も削除せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"enforcement": "active"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/rulesets/b.json"* ]]
}

@test "name が空の定義があれば、ほかの定義も適用せず、何も削除せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset b.json '{"name": "", "enforcement": "active"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/rulesets/b.json"* ]]
}

@test "name が同じ定義が複数あれば、どれも適用せず、何も削除せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset a.json '{"name": "main", "enforcement": "active"}'
  define_ruleset b.json '{"name": "main", "enforcement": "disabled"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *"main"* ]]
}

@test "定義と同じ名前のルールセットが GitHub に複数あれば、ほかの定義も適用せず、何も削除せずに失敗する" {
  rulesets='[
    {"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "main", "enforcement": "active"},
    {"id": 3, "source_type": "Repository", "name": "legacy", "enforcement": "active"}
  ]'
  given_github_rulesets "$rulesets"
  define_ruleset a.json '{"name": "a", "enforcement": "active"}'
  define_ruleset main.json '{"name": "main", "enforcement": "disabled"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets "$rulesets"
  [[ $output == *"main"* ]]
  [[ $output != *"で失敗しました"* ]]
}

@test "定義にない名前なら、GitHub で重複していても失敗せず、すべて削除する" {
  given_github_rulesets '[
    {"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"},
    {"id": 2, "source_type": "Repository", "name": "legacy", "enforcement": "active"}
  ]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
}

@test "リポジトリの設定を、定義に書いた値で更新する" {
  given_github_repository '{"has_wiki": true, "delete_branch_on_merge": false}'
  define_repository '{"has_wiki": false, "delete_branch_on_merge": true}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_repository '{"has_wiki": false, "delete_branch_on_merge": true}'
}

@test "リポジトリの設定の定義が JSON として読めなければ、ルールセットも含めて何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  given_github_repository '{"has_wiki": true}'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  define_repository '{"has_wiki": false,'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  assert_github_repository '{"has_wiki": true}'
  [[ $output == *".github/settings/repository.json"* ]]
  [[ $output != *"適用しています"* ]]
}

@test "リポジトリの設定の定義が JSON オブジェクトでなければ、何も変更せずに失敗する" {
  given_github_repository '{"has_wiki": true}'
  define_repository '[{"has_wiki": false}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_repository '{"has_wiki": true}'
  [[ $output == *".github/settings/repository.json"* ]]
}

@test "リポジトリの設定の定義がなければ、ルールセットも含めて何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  rm "$repo/.github/settings/repository.json"

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/repository.json"* ]]
}

@test "ルールセットの定義に不備があれば、リポジトリの設定も変更せずに失敗する" {
  given_github_repository '{"has_wiki": true}'
  define_ruleset main.json '{"enforcement": "active"}'
  define_repository '{"has_wiki": false}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_repository '{"has_wiki": true}'
}

@test "セキュリティの設定を、定義に書いた値で有効・無効にし、書いていないものは変えない" {
  given_github_security '{"vulnerability_alerts": false, "automated_security_fixes": false, "private_vulnerability_reporting": true, "immutable_releases": false}'
  define_security '{"vulnerability_alerts": true, "automated_security_fixes": true, "private_vulnerability_reporting": false}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_security '{"vulnerability_alerts": true, "automated_security_fixes": true, "private_vulnerability_reporting": false, "immutable_releases": false}'
}

@test "CodeQL のデフォルトセットアップが定義と違えば、定義の値で更新する" {
  define_security '{"code_scanning_default_setup": {"state": "configured", "query_suite": "extended"}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_code_scanning '{"state": "configured", "query_suite": "extended", "languages": ["actions"], "runs": 1}'
  [[ $output == *"更新: CodeQL のデフォルトセットアップ"* ]]
}

@test "CodeQL のデフォルトセットアップが定義と同じなら、更新せず解析も始めない" {
  given_github_code_scanning '{"state": "configured", "query_suite": "default", "languages": ["actions"], "runs": 0}'
  define_security '{"code_scanning_default_setup": {"state": "configured", "query_suite": "default"}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_code_scanning '{"state": "configured", "query_suite": "default", "languages": ["actions"], "runs": 0}'
}

@test "セキュリティの設定の定義がなければ、ルールセットも含めて何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  rm "$repo/.github/settings/security.json"

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/security.json"* ]]
}

@test "セキュリティの設定の定義に知らない項目があれば、書き間違いとみなして何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_security '{"vulnerability_alert": true}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  assert_github_security '{}'
  [[ $output == *".github/settings/security.json"* ]]
}

@test "セキュリティの設定の有効・無効が true か false でなければ、何も変更せずに失敗する" {
  define_security '{"vulnerability_alerts": "enabled"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_security '{}'
  [[ $output == *".github/settings/security.json"* ]]
}

@test "CodeQL のデフォルトセットアップの定義が JSON オブジェクトでなければ、何も変更せずに失敗する" {
  define_security '{"code_scanning_default_setup": "configured"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_code_scanning '{"state": "not-configured", "query_suite": "default", "languages": ["actions"], "runs": 0}'
  [[ $output == *".github/settings/security.json"* ]]
}

@test "フォークからの PR のワークフローの承認の方針を、定義の値で更新する" {
  define_actions '{"fork_pr_contributor_approval": {"approval_policy": "all_external_contributors"}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_fork_pr_approval '{"approval_policy": "all_external_contributors"}'
}

@test "フォークからの PR の承認の方針が JSON オブジェクトでなければ、何も変更せずに失敗する" {
  define_actions '{"fork_pr_contributor_approval": "all_external_contributors"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_fork_pr_approval '{"approval_policy": "first_time_contributors"}'
  [[ $output == *".github/settings/actions.json"* ]]
}

@test "GITHUB_TOKEN の既定の権限と PR を承認できるかを、定義の値で更新する" {
  define_actions '{"workflow_permissions": {"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_workflow_permissions '{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}'
}

@test "Actions の権限と実行できるアクションを、定義の値で更新する" {
  define_actions '{"permissions": {"enabled": true, "allowed_actions": "selected", "sha_pinning_required": true}, "selected_actions": {"github_owned_allowed": true, "verified_allowed": true, "patterns_allowed": ["dorny/paths-filter@*"]}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_actions '{"permissions": {"enabled": true, "allowed_actions": "selected", "sha_pinning_required": true}, "selected_actions": {"github_owned_allowed": true, "verified_allowed": true, "patterns_allowed": ["dorny/paths-filter@*"]}}'
}

@test "Actions の設定の定義がなければ、ルールセットも含めて何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  rm "$repo/.github/settings/actions.json"

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/actions.json"* ]]
}

@test "Actions の設定の定義に知らない項目があれば、何も変更せずに失敗する" {
  define_actions '{"permission": {"enabled": true}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_actions '{"permissions": {"enabled": true, "allowed_actions": "all", "sha_pinning_required": false}, "selected_actions": {}}'
  [[ $output == *".github/settings/actions.json"* ]]
}

@test "Actions の権限に enabled がなければ、何も変更せずに失敗する" {
  define_actions '{"permissions": {"allowed_actions": "selected"}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_actions '{"permissions": {"enabled": true, "allowed_actions": "all", "sha_pinning_required": false}, "selected_actions": {}}'
  [[ $output == *".github/settings/actions.json"* ]]
}

@test "実行できるアクションを書くのに allowed_actions が selected でなければ、何も変更せずに失敗する" {
  define_actions '{"permissions": {"enabled": true, "allowed_actions": "local_only"}, "selected_actions": {"github_owned_allowed": true}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_actions '{"permissions": {"enabled": true, "allowed_actions": "all", "sha_pinning_required": false}, "selected_actions": {}}'
  [[ $output == *".github/settings/actions.json"* ]]
}

@test "定義のラベルを作成・更新し、名前に空白があっても、定義にないラベルは削除する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}, {"name": "good first issue", "color": "7057ff", "description": "Good for newcomers"}]'
  define_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}, {"name": "maintenance", "color": "fbca04", "description": "保守作業"}]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}, {"name": "maintenance", "color": "fbca04", "description": "保守作業"}]'
  [[ $output == *"作成: ラベル maintenance"* ]]
  [[ $output == *"削除: ラベル good first issue"* ]]
}

@test "ラベルの定義がなければ、ルールセットも含めて何も変更せずに失敗する" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  rm "$repo/.github/settings/labels.json"

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  [[ $output == *".github/settings/labels.json"* ]]
}

@test "ラベルの定義が配列でなければ、何も変更せずに失敗する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_labels '{"maintenance": {"name": "maintenance", "color": "fbca04", "description": "保守作業"}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  [[ $output == *".github/settings/labels.json"* ]]
}

@test "名前のないラベルの定義があれば、何も変更せずに失敗する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_labels '[{"name": "maintenance", "color": "fbca04", "description": "保守作業"}, {"color": "0366d6"}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  [[ $output == *".github/settings/labels.json"* ]]
}

@test "ラベルの色が 6 桁の 16 進数でなければ、何も変更せずに失敗する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_labels '[{"name": "maintenance", "color": "#fbca04", "description": "保守作業"}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  [[ $output == *".github/settings/labels.json"* ]]
}

@test "ラベルの定義に知らない項目があれば、書き間違いとみなして何も変更せずに失敗する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_labels '[{"name": "maintenance", "color": "fbca04", "colour": "fbca04"}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  [[ $output == *".github/settings/labels.json"* ]]
}

@test "同じ名前のラベルが複数定義されていれば、何も変更せずに失敗する" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_labels '[{"name": "maintenance", "color": "fbca04"}, {"name": "maintenance", "color": "0366d6"}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  [[ $output == *"maintenance"* ]]
}

@test "ルールセットの一覧のキャッシュが古くても、今の一覧をもとに更新し、重複して作成しない" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"}]'
  echo '[]' > "$STUB_DIR/rulesets.stale.json"
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
}

@test "ラベルの一覧のキャッシュが古くても、今の一覧をもとに、もうないラベルを削除しようとしない" {
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}]'
  echo '[{"name": "bug", "color": "d73a4a", "description": "不具合"}, {"name": "wontfix", "color": "ffffff", "description": "Will not be worked on"}]' > "$STUB_DIR/labels.stale.json"
  define_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}]'
}

@test "CodeQL のデフォルトセットアップのキャッシュが古くても、今の設定と比べて更新する" {
  echo '{"state": "configured", "query_suite": "default", "languages": ["actions"]}' > "$STUB_DIR/code-scanning.stale.json"
  define_security '{"code_scanning_default_setup": {"state": "configured", "query_suite": "default"}}'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_code_scanning '{"state": "configured", "query_suite": "default", "languages": ["actions"], "runs": 1}'
}

@test "ルールセットの一覧を取得できなければ、作成せずに失敗する" {
  export STUB_FAIL="GET *"
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[]'
  [[ $output == *"エラー: ルールセットの一覧の取得で失敗しました"* ]]
}

@test "ルールセットの更新に失敗したら失敗する" {
  export STUB_FAIL="PUT repos/{owner}/{repo}/rulesets/*"
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"GitHub に定義を適用しました"* ]]
  [[ $output == *"エラー: ルールセット main の反映で失敗しました。それより前の設定は反映済みです"* ]]
}

@test "ルールセットの削除に失敗したら失敗する" {
  export STUB_FAIL="DELETE repos/{owner}/{repo}/rulesets/*"
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "legacy", "enforcement": "active"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"削除: ルールセット legacy"* ]]
  [[ $output == *"エラー: ルールセット legacy の削除で失敗しました"* ]]
}

@test "セキュリティの設定の切り替えに失敗したら失敗する" {
  export STUB_FAIL="PUT repos/{owner}/{repo}/vulnerability-alerts"
  define_security '{"vulnerability_alerts": true}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_security '{}'
  [[ $output == *"エラー: vulnerability_alerts の反映で失敗しました"* ]]
}

@test "CodeQL のデフォルトセットアップの更新に失敗したら失敗する" {
  export STUB_FAIL="PATCH repos/{owner}/{repo}/code-scanning/default-setup"
  define_security '{"code_scanning_default_setup": {"state": "configured"}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"更新: CodeQL"* ]]
  [[ $output == *"エラー: CodeQL のデフォルトセットアップの反映で失敗しました"* ]]
}

@test "フォークからの PR の承認の方針の更新に失敗したら失敗する" {
  export STUB_FAIL="PUT repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval"
  define_actions '{"fork_pr_contributor_approval": {"approval_policy": "all_external_contributors"}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"GitHub に定義を適用しました"* ]]
  [[ $output == *"エラー: フォークからの PR の承認の方針の反映で失敗しました"* ]]
}

@test "GITHUB_TOKEN の既定の権限の更新に失敗したら失敗する" {
  export STUB_FAIL="PUT repos/{owner}/{repo}/actions/permissions/workflow"
  define_actions '{"workflow_permissions": {"default_workflow_permissions": "read"}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"GitHub に定義を適用しました"* ]]
  [[ $output == *"エラー: GITHUB_TOKEN の既定の権限の反映で失敗しました"* ]]
}

@test "実行できるアクションの更新に失敗したら失敗する" {
  export STUB_FAIL="PUT repos/{owner}/{repo}/actions/permissions/selected-actions"
  define_actions '{"permissions": {"enabled": true, "allowed_actions": "selected"}, "selected_actions": {"github_owned_allowed": true}}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"GitHub に定義を適用しました"* ]]
  [[ $output == *"エラー: 実行できるアクションの反映で失敗しました"* ]]
}

@test "ラベルの削除に失敗したら失敗する" {
  export STUB_FAIL="DELETE repos/{owner}/{repo}/labels/*"
  given_github_labels '[{"name": "wontfix", "color": "ffffff", "description": "Will not be worked on"}]'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"削除: ラベル wontfix"* ]]
  [[ $output == *"エラー: ラベル wontfix の削除で失敗しました"* ]]
}

@test "リポジトリの設定の更新に失敗したら失敗する" {
  export STUB_FAIL="PATCH repos/{owner}/{repo}"
  define_repository '{"has_wiki": false}'

  run -1 "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output != *"GitHub に定義を適用しました"* ]]
  [[ $output == *"エラー: リポジトリの設定の反映で失敗しました"* ]]
}

@test "jq がなければ、定義の不備とは示さず、jq が見つからないと示して失敗する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 env PATH="$(path_without jq)" "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output == *"jq が見つかりません"* ]]
  [[ $output != *"main.json"* ]]
  assert_github_rulesets '[]'
}

@test "gh がなければ、gh が見つからないと示して失敗する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'

  run -1 env PATH="$(path_without gh)" "$repo/.github/scripts/sync-github-settings.sh"

  [[ $output == *"gh が見つかりません"* ]]
}

@test "GH_REPO が設定されていても、ほかのリポジトリには反映せず、このリポジトリに反映する" {
  other='[{"id": 1, "source_type": "Repository", "name": "other", "enforcement": "active"}]'
  echo "$other" > "$STUB_DIR/other-repo-rulesets.json"
  echo '{"has_wiki": true}' > "$STUB_DIR/other-repo-repository.json"
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  define_repository '{"has_wiki": false}'
  export GH_REPO=someone/other

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_rulesets '[{"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  assert_github_repository '{"has_wiki": false}'
  jq -e --argjson expected "$other" '. == $expected' "$STUB_DIR/other-repo-rulesets.json"
  jq -e '. == {"has_wiki": true}' "$STUB_DIR/other-repo-repository.json"
}

@test "どのディレクトリから実行しても、リポジトリのルートで定義を読み gh を実行する" {
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  cd "$repo/.github"

  run -0 scripts/sync-github-settings.sh

  assert_github_rulesets '[{"id": 100, "source_type": "Repository", "name": "main", "enforcement": "active"}]'
  [ "$(sort -u "$STUB_DIR/gh.pwd")" = "$repo" ]
}

@test "作成・削除がなければ、適用の開始と完了だけを示す" {
  given_github_rulesets '[{"id": 1, "source_type": "Repository", "name": "main", "enforcement": "disabled"}]'
  given_github_code_scanning '{"state": "configured", "query_suite": "default", "languages": ["actions"], "runs": 0}'
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}]'
  define_ruleset main.json '{"name": "main", "enforcement": "active"}'
  define_repository '{"has_wiki": false}'
  define_security '{"vulnerability_alerts": true, "automated_security_fixes": false, "code_scanning_default_setup": {"state": "configured"}}'
  define_actions '{"workflow_permissions": {"default_workflow_permissions": "read"}}'
  define_labels '[{"name": "bug", "color": "d73a4a", "description": "不具合"}]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  [ "$output" = 'GitHub に定義を適用しています...
GitHub に定義を適用しました' ]
}

@test "リポジトリにあるルールセットの定義を、すべて GitHub に作成できる" {
  cp "$BATS_TEST_DIRNAME"/../settings/rulesets/*.json "$repo/.github/settings/rulesets/"

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  [ "$(jq -c 'map(.name) | sort' "$STUB_DIR/rulesets.json")" = "$(jq -cs 'map(.name) | sort' "$repo"/.github/settings/rulesets/*.json)" ]
}

@test "リポジトリにあるリポジトリの設定の定義を、そのまま GitHub に反映できる" {
  cp "$BATS_TEST_DIRNAME/../settings/repository.json" "$repo/.github/settings/repository.json"

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_repository "$(cat "$repo/.github/settings/repository.json")"
}

@test "リポジトリにあるセキュリティの設定の定義を、GitHub に反映できる" {
  cp "$BATS_TEST_DIRNAME/../settings/security.json" "$repo/.github/settings/security.json"

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_security "$(jq -c 'del(.code_scanning_default_setup)' "$repo/.github/settings/security.json")"
  jq -e --slurpfile security "$repo/.github/settings/security.json" \
    '. as $current | $security[0].code_scanning_default_setup | to_entries | all(.value == $current[.key])' \
    "$STUB_DIR/code-scanning.json"
}

@test "リポジトリにある Actions の設定の定義を、そのまま GitHub に反映できる" {
  cp "$BATS_TEST_DIRNAME/../settings/actions.json" "$repo/.github/settings/actions.json"

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  jq -e --slurpfile actions "$repo/.github/settings/actions.json" '. == $actions[0].selected_actions' "$STUB_DIR/selected-actions.json"
  jq -e --slurpfile actions "$repo/.github/settings/actions.json" '. as $current | $actions[0].permissions | to_entries | all(.value == $current[.key])' "$STUB_DIR/actions-permissions.json"
  jq -e --slurpfile actions "$repo/.github/settings/actions.json" '. == $actions[0].fork_pr_contributor_approval' "$STUB_DIR/fork-pr-approval.json"
  jq -e --slurpfile actions "$repo/.github/settings/actions.json" '. == $actions[0].workflow_permissions' "$STUB_DIR/workflow-permissions.json"
}

@test "リポジトリにあるラベルの定義を、そのまま GitHub に反映できる" {
  cp "$BATS_TEST_DIRNAME/../settings/labels.json" "$repo/.github/settings/labels.json"
  given_github_labels '[{"name": "bug", "color": "d73a4a", "description": "Something is not working"}, {"name": "wontfix", "color": "ffffff", "description": "Will not be worked on"}]'

  run -0 "$repo/.github/scripts/sync-github-settings.sh"

  assert_github_labels "$(jq -c . "$repo/.github/settings/labels.json")"
}
