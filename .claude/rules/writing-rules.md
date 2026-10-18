---
paths:
  - "CLAUDE.md"
  - "CONTRIBUTING.md"
  - "README.md"
  - ".claude/**/*.md"
  - ".github/**/*.md"
---

## ルールや手順を書くとき

<!--
例は Claude の出力の形式や構造をそろえる、もっとも確実な方法の 1 つとされている
https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#use-examples-effectively
-->

- 書き方や形式が文だけでは伝わりにくいルールには、例を添える
- 例は実際に動かして確認したものだけを載せる。確認できないものは載せないか、「未確認」と明記する
- 例が 1 つだと、その場面にしか当てはまらないと読まれやすいので、場面の違う例を並べるか、当てはまる範囲を文で補う

## textlint と markdownlint

- `.md` はすべて CI の textlint（設定は `.github/textlint`）と markdownlint で検査される
- 1 文を 100 文字以内にし、表記は `prh.yml` と ja-hiraku に合わせる（例: `クォートの中` ではなく `クォートのなか`）
