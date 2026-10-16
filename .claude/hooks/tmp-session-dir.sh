#!/usr/bin/env bash
set -euo pipefail

# 並行するセッションが同じファイル名で中間ファイルを上書きし合わないよう、.tmp/ の下にセッションごとのディレクトリを作って伝える

session_id=$(jq -r '.session_id // ""')

# .. や / を含む値で .tmp/ の外やほかのセッションのディレクトリを指せないよう、ディレクトリ名に使える文字だけを受け付ける
case $session_id in
'' | *[!A-Za-z0-9_-]*)
  echo "セッション ID を取得できないため、中間ファイルのディレクトリを作れません" >&2
  exit 1
  ;;
esac

dir=${CLAUDE_PROJECT_DIR:?}/.tmp/$session_id
mkdir -p "$dir"
echo "このセッションの中間ファイルは $dir/ に作る。.tmp/ のほかの場所は並行するほかのセッションのものなので書き込まない"
