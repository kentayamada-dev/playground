#!/usr/bin/env bats

# 検証用: SC2086（引用符なしの変数展開）を起こす
@test "ShellCheck の検証用" {
  dir="a b"
  ls $dir
}
