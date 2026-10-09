#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0

  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/.github/textlint/node_modules/.bin" "$repo/docs"
  cp "$BATS_TEST_DIRNAME/lint.sh" "$repo/.github/textlint/lint.sh"
  touch "$repo/.github/textlint/.textlintrc.json"
  # ルート直下と下層の両方に置き、シェルが glob を展開するとルート直下が対象から漏れる状態にする
  touch "$repo/README.md" "$repo/docs/guide.md"
  repo=$(cd "$repo" && pwd -P)

  export STUB_LOG_DIR="$BATS_TEST_TMPDIR"
  cat > "$repo/.github/textlint/node_modules/.bin/textlint" <<'EOF'
#!/usr/bin/env bash
pwd -P > "$STUB_LOG_DIR/textlint.pwd"
printf '%s\n' "$@" > "$STUB_LOG_DIR/textlint.args"
printf '%s' "${STUB_TEXTLINT_OUTPUT-}"
exit "${STUB_TEXTLINT_STATUS:-0}"
EOF
  chmod +x "$repo/.github/textlint/node_modules/.bin/textlint"
}

textlint_arg_after() {
  awk -v flag="$1" 'found { print; exit } $0 == flag { found = 1 }' "$STUB_LOG_DIR/textlint.args"
}

@test "textlint に指摘があれば、その出力を示して失敗する" {
  export STUB_TEXTLINT_STATUS=1
  export STUB_TEXTLINT_OUTPUT='README.md: 1:1 error 文末が"。"で終わっていません。'

  run -1 "$repo/.github/textlint/lint.sh"

  [[ "$output" == *"$STUB_TEXTLINT_OUTPUT"* ]]
}

@test "textlint が異常終了したら、その終了コードで失敗する" {
  export STUB_TEXTLINT_STATUS=2

  run -2 "$repo/.github/textlint/lint.sh"
}

@test "textlint が未インストールなら失敗する" {
  rm "$repo/.github/textlint/node_modules/.bin/textlint"

  run -127 "$repo/.github/textlint/lint.sh"
}

@test "どのディレクトリから実行しても、リポジトリ全体の Markdown を検査する" {
  cd "$repo/docs"

  run -0 ../.github/textlint/lint.sh

  [ "$(< "$STUB_LOG_DIR/textlint.pwd")" = "$repo" ]
  grep -qFx '**/*.md' "$STUB_LOG_DIR/textlint.args"
}

@test "相対パスで実行しても、ルールの基準ディレクトリを絶対パスで渡す" {
  cd "$repo"

  run -0 .github/textlint/lint.sh

  [ "$(textlint_arg_after --rules-base-directory)" = "$repo/.github/textlint/node_modules" ]
}

@test "設定ファイルは textlint の自動探索に任せず、.github/textlint にあるものを渡す" {
  run -0 "$repo/.github/textlint/lint.sh"

  [ "$(textlint_arg_after --config)" = "$repo/.github/textlint/.textlintrc.json" ]
  [ -f "$BATS_TEST_DIRNAME/.textlintrc.json" ]
}

@test "設定ファイルが無ければ、textlint を実行せず、設定ファイルのパスを示して失敗する" {
  rm "$repo/.github/textlint/.textlintrc.json"

  run -1 "$repo/.github/textlint/lint.sh"

  [[ "$output" == *"$repo/.github/textlint/.textlintrc.json"* ]]
  [ ! -e "$STUB_LOG_DIR/textlint.args" ]
}
