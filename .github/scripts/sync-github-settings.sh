#!/usr/bin/env bash
set -euo pipefail

# GET の応答は Cache-Control: private, max-age=60 で、変更の直後に古い値が返ることがあったため、キャッシュを使わせない
# https://github.com/kentayamada-dev/playground/pull/53
gh_get() {
  gh api -H 'Cache-Control: no-cache' "$@"
}

sync_rulesets() {
  local files=(.github/rulesets/*.json) has_definitions=false
  # 一致するファイルがないとパターンが文字列のまま残る。macOS の bash 3.2 は空配列の展開を set -u でエラーにするため、配列は空にせず存在で判定する
  if [ -e "${files[0]}" ]; then
    has_definitions=true
  fi

  # 途中まで適用した状態で止まらないよう、作成・更新・削除の前にすべての定義と照合先を検査する
  local file names='[]' duplicates
  if $has_definitions; then
    for file in "${files[@]}"; do
      if ! jq -e '.name | type == "string" and length > 0' "$file" >/dev/null; then
        echo "エラー: $file は name（空でない文字列）を持つ JSON オブジェクトではありません" >&2
        return 1
      fi
    done
    names=$(jq -cs 'map(.name)' "${files[@]}")
  fi
  duplicates=$(jq -r 'group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$names")
  if [ -n "$duplicates" ]; then
    echo "エラー: 同じ name のルールセットが複数のファイルにあります: $duplicates" >&2
    return 1
  fi

  # includes_parents のデフォルトは true で、Organization のルールセットも返り、名前が同じだと誤って照合するため外す
  # https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28#get-all-repository-rulesets
  local existing
  existing=$(gh_get --paginate --slurp 'repos/{owner}/{repo}/rulesets?includes_parents=false&per_page=100')
  duplicates=$(jq -r --argjson names "$names" '[.[][] | .name | select(IN($names[]))] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$existing")
  if [ -n "$duplicates" ]; then
    echo "エラー: GitHub に同じ名前のルールセットが複数あり、更新先を決められません: $duplicates" >&2
    return 1
  fi

  local name id
  if $has_definitions; then
    for file in "${files[@]}"; do
      name=$(jq -r '.name' "$file")
      id=$(jq -r --arg name "$name" '.[][] | select(.name == $name) | .id' <<<"$existing")
      if [ -z "$id" ]; then
        gh api --method POST 'repos/{owner}/{repo}/rulesets' --input "$file" --silent
        echo "作成: $name ($file)"
      else
        gh api --method PUT "repos/{owner}/{repo}/rulesets/$id" --input "$file" --silent
        echo "更新: $name ($file)"
      fi
    done
  fi

  # 定義の name を変えたときに、古いルールセットを先に消して保護が途切れないよう、作成・更新のあとで削除する
  local stale
  stale=$(jq -r --argjson names "$names" '.[][] | select(.name | IN($names[]) | not) | .id' <<<"$existing")
  for id in $stale; do
    name=$(jq -r --argjson id "$id" '.[][] | select(.id == $id) | .name' <<<"$existing")
    gh api --method DELETE "repos/{owner}/{repo}/rulesets/$id" --silent
    echo "削除: $name"
  done
}

repository_definition=.github/repository.json

validate_repository() {
  if ! jq -e 'type == "object"' "$repository_definition" >/dev/null; then
    echo "エラー: $repository_definition を JSON オブジェクトとして読めません" >&2
    return 1
  fi
}

sync_repository() {
  # has_discussions は API のドキュメントの項目にないが、gh repo edit も同じ API に送っている
  # https://github.com/cli/cli/blob/v2.102.0/pkg/cmd/repo/edit/edit.go
  gh api --method PATCH 'repos/{owner}/{repo}' --input "$repository_definition" --silent
  echo "更新: リポジトリの設定 ($repository_definition)"
}

security_definition=.github/security.json
# true なら PUT、false なら DELETE で切り替える項目。_ を - にすると API のパスになる
security_features='vulnerability_alerts automated_security_fixes private_vulnerability_reporting immutable_releases'

validate_security() {
  if ! jq -e --arg features "$security_features" '
    ($features | split(" ")) as $features
    | type == "object"
    and (keys - $features - ["code_scanning_default_setup"] | length == 0)
    and ([.[$features[]] | select(. != null) | type == "boolean"] | all)
    and ((has("code_scanning_default_setup") | not) or (.code_scanning_default_setup | type == "object"))
  ' "$security_definition" >/dev/null; then
    echo "エラー: $security_definition は、項目が $security_features code_scanning_default_setup のどれかで、有効・無効が true か false、code_scanning_default_setup が JSON オブジェクトの定義ではありません" >&2
    return 1
  fi
}

sync_security() {
  local feature enabled
  for feature in $security_features; do
    enabled=$(jq -r --arg feature "$feature" 'if has($feature) then .[$feature] else empty end' "$security_definition")
    if [ "$enabled" = true ]; then
      gh api --method PUT "repos/{owner}/{repo}/${feature//_/-}" --silent
      echo "有効化: $feature"
    elif [ "$enabled" = false ]; then
      gh api --method DELETE "repos/{owner}/{repo}/${feature//_/-}" --silent
      echo "無効化: $feature"
    fi
  done

  local desired current
  desired=$(jq -c 'if has("code_scanning_default_setup") then .code_scanning_default_setup else empty end' "$security_definition")
  if [ -z "$desired" ]; then
    return 0
  fi
  current=$(gh_get 'repos/{owner}/{repo}/code-scanning/default-setup')
  # 設定が同じでも送ると解析が走るかは未確認のため、違うときだけ送る
  if jq -e --argjson desired "$desired" '. as $current | $desired | to_entries | all(.value == $current[.key])' <<<"$current" >/dev/null; then
    echo "変更なし: CodeQL のデフォルトセットアップ"
  else
    gh api --method PATCH 'repos/{owner}/{repo}/code-scanning/default-setup' --input - --silent <<<"$desired"
    echo "更新: CodeQL のデフォルトセットアップ"
  fi
}

actions_definition=.github/actions.json

validate_actions() {
  if ! jq -e '
    type == "object"
    and (keys - ["permissions", "selected_actions", "fork_pr_contributor_approval"] | length == 0)
    and ([.[]] | all(type == "object"))
    and ((has("permissions") | not) or (.permissions.enabled | type == "boolean"))
    and ((has("selected_actions") | not) or .permissions.allowed_actions == "selected")
  ' "$actions_definition" >/dev/null; then
    echo "エラー: $actions_definition は、項目が permissions・selected_actions・fork_pr_contributor_approval のどれかで、どれも JSON オブジェクト、permissions の enabled が true か false、selected_actions を書くなら permissions の allowed_actions が selected の定義ではありません" >&2
    return 1
  fi
}

sync_actions() {
  local body
  body=$(jq -c 'if has("permissions") then .permissions else empty end' "$actions_definition")
  if [ -n "$body" ]; then
    gh api --method PUT 'repos/{owner}/{repo}/actions/permissions' --input - --silent <<<"$body"
    echo "更新: Actions の権限"
  fi
  body=$(jq -c 'if has("selected_actions") then .selected_actions else empty end' "$actions_definition")
  if [ -n "$body" ]; then
    # allowed_actions が selected でないと受け付けないため、権限のあとで送る
    # https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28#set-allowed-actions-and-reusable-workflows-for-a-repository
    gh api --method PUT 'repos/{owner}/{repo}/actions/permissions/selected-actions' --input - --silent <<<"$body"
    echo "更新: 実行できるアクション"
  fi
  body=$(jq -c 'if has("fork_pr_contributor_approval") then .fork_pr_contributor_approval else empty end' "$actions_definition")
  if [ -n "$body" ]; then
    gh api --method PUT 'repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval' --input - --silent <<<"$body"
    echo "更新: フォークからの PR の承認の方針"
  fi
}

labels_definition=.github/labels.json

validate_labels() {
  if ! jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (keys - ["name", "color", "description"] | length == 0)
      and (.name | type == "string" and length > 0)
      and (.color | type == "string" and test("^[0-9a-fA-F]{6}$"))
      and ((has("description") | not) or (.description | type == "string")))
  ' "$labels_definition" >/dev/null; then
    echo "エラー: $labels_definition は、name（空でない文字列）・color（6 桁の 16 進数）・description（文字列。省略可）だけを持つオブジェクトの配列ではありません" >&2
    return 1
  fi
  local duplicates
  duplicates=$(jq -r 'map(.name) | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$labels_definition")
  if [ -n "$duplicates" ]; then
    echo "エラー: 同じ名前のラベルが $labels_definition に複数あります: $duplicates" >&2
    return 1
  fi
}

# ラベル名は空白などを含むため、API のパスに入れる前にエンコードする
uri_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

sync_labels() {
  local existing
  existing=$(gh_get --paginate --slurp 'repos/{owner}/{repo}/labels?per_page=100')

  local count i label name
  count=$(jq length "$labels_definition")
  for ((i = 0; i < count; i++)); do
    label=$(jq -c ".[$i]" "$labels_definition")
    name=$(jq -r '.name' <<<"$label")
    if jq -e --arg name "$name" 'any(.[][]; .name == $name)' <<<"$existing" >/dev/null; then
      gh api --method PATCH "repos/{owner}/{repo}/labels/$(uri_encode "$name")" --input - --silent <<<"$(jq -c 'del(.name)' <<<"$label")"
      echo "更新: ラベル $name"
    else
      gh api --method POST 'repos/{owner}/{repo}/labels' --input - --silent <<<"$label"
      echo "作成: ラベル $name"
    fi
  done

  local stale
  stale=$(jq -r --slurpfile defined "$labels_definition" '.[][] | .name | select(IN($defined[0][].name) | not)' <<<"$existing")
  while IFS= read -r name; do
    if [ -n "$name" ]; then
      gh api --method DELETE "repos/{owner}/{repo}/labels/$(uri_encode "$name")" --silent
      echo "削除: ラベル $name"
    fi
  done <<<"$stale"
}

# jq がないと定義の検査（if ! jq）が失敗し、定義の不備と誤って示すため、先に確かめる
for command in gh jq; do
  if ! command -v "$command" >/dev/null; then
    echo "エラー: $command が見つかりません。インストールしてから実行してください" >&2
    exit 1
  fi
done

# gh は GH_REPO があればそれを対象にするため外し、定義と同じリポジトリのルートで remote から決めさせる
# https://github.com/cli/cli/blob/v2.102.0/pkg/cmdutil/repo_override.go
unset GH_REPO
cd "$(dirname "$0")/../.."
# ルールセットだけ反映して止まらないよう、ほかの定義はルールセットより先に検査する
validate_repository
validate_security
validate_actions
validate_labels
sync_rulesets
sync_repository
sync_security
sync_actions
sync_labels
