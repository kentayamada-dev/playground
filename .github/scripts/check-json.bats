#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0

  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/.github/scripts"
  repo=$(cd "$repo" && pwd -P)
  script="$repo/.github/scripts/check-json.sh"
  cp "$BATS_TEST_DIRNAME/check-json.sh" "$script"
  git -C "$repo" init -q
}

# 中身を書いたファイルを Git で管理する
add_file() {
  mkdir -p "$(dirname "$repo/$1")"
  printf '%s' "$2" >"$repo/$1"
  git -C "$repo" add -- "$1"
}

# スクリプトが使うコマンドのうち、指定したものだけがない PATH を作る
path_without() {
  local dir="$BATS_TEST_TMPDIR/path-without-$1" command
  mkdir -p "$dir"
  for command in bash dirname git jq; do
    if [ "$command" != "$1" ]; then
      ln -s "$(command -v "$command")" "$dir/$command"
    fi
  done
  echo "$dir"
}

@test "正しい JSON のオブジェクトと配列だけなら、何も示さずに成功する" {
  add_file object.json '{"a": 1}'
  add_file array.json '[1, 2]'

  run -0 "$script"

  [ "$output" = '' ]
}

@test "JSON として読めないファイルがあれば、その名前を示して失敗する" {
  add_file ok.json '{"a": 1}'
  add_file broken.json '{"a": 1,}'

  run -1 "$script"

  [[ $output == *'::error file=broken.json::JSON として読めないか、値がちょうど 1 つではありません'* ]]
  [[ $output != *'file=ok.json'* ]]
}

@test "空のファイルは、値がちょうど 1 つではないとして失敗する" {
  add_file empty.json ''

  run -1 "$script"

  [[ $output == *'::error file=empty.json::'* ]]
}

@test "値が 2 つ並ぶファイルは、値がちょうど 1 つではないとして失敗する" {
  add_file two.json $'{"a": 1}\n{"b": 2}\n'

  run -1 "$script"

  [[ $output == *'::error file=two.json::'* ]]
}

@test "壊れたファイルが複数あっても、最初で止まらずにすべて示す" {
  add_file first.json '{'
  add_file second.json '}'

  run -1 "$script"

  [[ $output == *'::error file=first.json::'* ]]
  [[ $output == *'::error file=second.json::'* ]]
}

@test "ドットで始まるディレクトリや空白を含むパスの .json も検査する" {
  add_file .claude/settings.json '{"a": 1,}'
  add_file 'dir with space/x.json' '{"a": 1,}'

  run -1 "$script"

  [[ $output == *'::error file=.claude/settings.json::'* ]]
  [[ $output == *'::error file=dir with space/x.json::'* ]]
}

@test "Git で管理していない .json は検査しない" {
  add_file ok.json '{"a": 1}'
  printf '{"a": 1,}' >"$repo/untracked.json"

  run -0 "$script"
}

@test ".json 以外の拡張子のファイルは検査しない" {
  add_file renovate.json5 '{a: 1,}'
  add_file notes.txt 'not json'

  run -0 "$script"
}

@test "どのディレクトリから実行しても、リポジトリのルートで .json を探す" {
  add_file broken.json '{'
  cd "$BATS_TEST_TMPDIR"

  run -1 "$script"

  [[ $output == *'::error file=broken.json::'* ]]
}

@test "Git のリポジトリの中になければ、検査できたことにせずに失敗する" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside/.github/scripts"
  cp "$script" "$outside/.github/scripts/check-json.sh"

  run ! "$outside/.github/scripts/check-json.sh"
}

@test "jq がなければ、JSON の不備とは示さず、jq が見つからないと示して失敗する" {
  add_file ok.json '{"a": 1}'

  run -1 env PATH="$(path_without jq)" "$script"

  [[ $output == *'jq が見つかりません'* ]]
  [[ $output != *'::error'* ]]
}
