#!/usr/bin/env bash
set -euo pipefail

sync_rulesets() {
  local files=(.github/rulesets/*.json)
  # 一致するファイルがないとパターンが文字列のまま残る。macOS の bash 3.2 は nullglob の空配列を set -u でエラーにするため、存在で判定する
  if [ ! -e "${files[0]}" ]; then
    return 0
  fi

  # 途中まで適用した状態で止まらないよう、作成・更新の前にすべての定義と照合先を検査する
  local file
  for file in "${files[@]}"; do
    if ! jq -e '.name | type == "string" and length > 0' "$file" >/dev/null; then
      echo "エラー: $file は name（空でない文字列）を持つ JSON オブジェクトではありません" >&2
      return 1
    fi
  done
  local names duplicates
  names=$(jq -cs 'map(.name)' "${files[@]}")
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
}

# jq がないと定義の検査（if ! jq）が失敗し、定義の不備と誤って示すため、先に確かめる
for command in gh jq; do
  if ! command -v "$command" >/dev/null; then
    echo "エラー: $command が見つかりません。インストールしてから実行してください" >&2
    exit 1
  fi
done

# gh はカレントディレクトリの remote から対象のリポジトリを決めるため、定義と同じリポジトリのルートで実行する
cd "$(dirname "$0")/../.."
sync_rulesets
