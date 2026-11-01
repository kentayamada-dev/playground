#!/usr/bin/env bats
# 検証用の一時ファイルで、マージしない。count-comments.sh を壊したコピーで count-comments.bats を動かし、狙ったテストが落ちることを確かめる
# 壊し方に awk の $1 などをそのまま書くため、シングルクォートのなかの $ を指摘させない
# shellcheck disable=SC2016

setup() {
  bats_require_minimum_version 1.5.0

  # shellcheck disable=SC2154 # BATS_TEST_DIRNAME は bats が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定する
  dir="${BATS_TEST_DIRNAME}"
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR は bats が設定する。ShellCheck の check-unassigned-uppercase は未代入と判定する
  work="${BATS_TEST_TMPDIR}/mutant"
  mkdir -p "${work}"
  cp "${dir}/count-comments.bats" "${work}/count-comments.bats"
}

# count-comments.sh の from を to に置き換えたコピーで count-comments.bats を動かし、expected 番目のテストが落ちることを確かめる
assert_killed() {
  local from=$1 to=$2 expected=$3
  local original mutated
  original=$(<"${dir}/count-comments.sh")
  mutated=${original/"${from}"/"${to}"}
  [[ ${mutated} != "${original}" ]]
  printf '%s\n' "${mutated}" >"${work}/count-comments.sh"
  chmod +x "${work}/count-comments.sh"

  run -1 bats "${work}/count-comments.bats"

  printf '# %s\n' "${lines[@]}" >&3
  [[ ${output} == *"not ok ${expected} "* ]]
}

@test "字下げしたコメントを数えないと、1 番目のテストが落ちる" {
  assert_killed 'line ~ /^[ \t]*(#|\/\/)/' 'line ~ /^(#|\/\/)/' 1
}

@test "行の途中から始まるコメントも数えると、1 番目のテストが落ちる" {
  assert_killed 'line ~ /^[ \t]*(#|\/\/)/' 'line ~ /(#|\/\/)/' 1
}

@test "1 行目のシバンも数えると、2 番目のテストが落ちる" {
  assert_killed ' && !($1 == 1 && line ~ /^#!/)' '' 2
}

@test "2 行目より後の #! も数えないと、2 番目のテストが落ちる" {
  assert_killed '!($1 == 1 && line ~ /^#!/)' '!(line ~ /^#!/)' 2
}

@test "ファイルの末尾で終わるかたまりを数えないと、3 番目のテストが落ちる" {
  assert_killed '    END {' '    END { block = 0' 3
}

@test "4 行ちょうどのかたまりを数えないと、3 番目のテストが落ちる" {
  assert_killed 'if (block >= 4)' 'if (block > 4)' 3
}

@test "ファイルの変わり目でかたまりを切らないと、4 番目のテストが落ちる" {
  assert_killed '$1 == 1 { end_block() }' '' 4
}

@test "Markdown も数えると、5 番目のテストが落ちる" {
  assert_killed "':!*.md' " '' 5
}

@test "JSON も数えると、5 番目のテストが落ちる" {
  assert_killed "':!*.json' " '' 5
}

@test ".lock も数えると、5 番目のテストが落ちる" {
  assert_killed "':!*.lock' " '' 5
}

@test ".sum も数えると、5 番目のテストが落ちる" {
  assert_killed "':!*.sum' " '' 5
}

@test "サブディレクトリの pnpm-lock.yaml も数えると、5 番目のテストが落ちる" {
  assert_killed " ':!*pnpm-lock.yaml'" '' 5
}

@test "バイナリも読むと、5 番目のテストが落ちる" {
  assert_killed 'git grep -I ' 'git grep ' 5
}

@test "追跡していないファイルも読むと、5 番目のテストが落ちる" {
  assert_killed 'git grep -I ' 'git grep --untracked -I ' 5
}

@test "リポジトリのルートに移動しないと、6 番目のテストが落ちる" {
  assert_killed 'cd "${top}"' ': "${top}"' 6
}

@test "対象がないときのエラーを出さないと、7 番目のテストが落ちる" {
  assert_killed 'if (total == 0) {' 'if (0) {' 7
}
