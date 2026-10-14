#!/usr/bin/env bash
# 検証用: SC2086（引用符なしの変数展開）を起こす
dir="a b"
ls $dir
