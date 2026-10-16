#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0

  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project"
  export CLAUDE_PROJECT_DIR="$project"
  script="$BATS_TEST_DIRNAME/tmp-session-dir.sh"
}

# session_id は null も試すため、JSON の値として受け取る
session_start() {
  run "$script" <<<"$(jq -n --argjson id "$1" '{hook_event_name: "SessionStart", source: "startup", session_id: $id}')"
}

@test ".tmp/ の下にセッション ID のディレクトリを作り、その絶対パスを Claude に伝える" {
  session_start '"session-a"'

  [ "$status" -eq 0 ]
  [ -d "$project/.tmp/session-a" ]
  [[ $output == *"$project/.tmp/session-a/"* ]]
}

@test "session_id が空なら、ディレクトリを作らずに失敗する" {
  session_start '""'

  [ "$status" -eq 1 ]
  [ ! -e "$project/.tmp" ]
}

@test "session_id が null なら、null という名前のディレクトリを作らずに失敗する" {
  session_start null

  [ "$status" -eq 1 ]
  [ ! -e "$project/.tmp" ]
}

@test "session_id に .. や / が含まれていれば、何も作らずに失敗する" {
  session_start '"../escape"'

  [ "$status" -eq 1 ]
  [ ! -e "$project/escape" ]
  [ ! -e "$project/.tmp" ]
}
