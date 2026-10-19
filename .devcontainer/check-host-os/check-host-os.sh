#!/usr/bin/env bash
set -euo pipefail

# 警告だけでは Dev Containers のログに埋もれて見落とされる見込み（推測）のため、続けずに止める
os=$(uname -s)
if [ "$os" != Darwin ]; then
  echo "エラー: 開発環境は macOS だけをサポートしています（このホストの OS は $os）" >&2
  exit 1
fi
