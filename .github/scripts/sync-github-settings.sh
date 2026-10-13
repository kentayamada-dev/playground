#!/usr/bin/env bash
set -euo pipefail

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
  existing=$(gh api --paginate --slurp 'repos/{owner}/{repo}/rulesets?includes_parents=false&per_page=100')
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
# ルールセットだけ反映して止まらないよう、リポジトリの設定の定義はルールセットより先に検査する
validate_repository
sync_rulesets
sync_repository
