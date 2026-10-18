---
name: block-git-push-not-standalone
enabled: true
event: bash
action: block
conditions:
  - field: command
    operator: regex_match
    pattern: (?:^|[;&|(\n`])\s*git\s+(?:-[Cc]\s+\S+\s+|--?[\w-]+(?:=\S+)?\s+)*push\b
  - field: command
    operator: regex_match
    pattern: \$\(|`|^(?!\s*git\s+push\b)|^(?:[^'"\\]|\\[\s\S]|'[^']*'|"(?:[^"\\]|\\[\s\S])*")*?(?:[;&|<>]|\n(?!\s*$))
---

`git push` を単独のコマンドとして実行していません。

この形はサンドボックスの `excludedCommands`（`git push *`）に一致せず、サンドボックス内で認証に失敗します。サンドボックス外での再実行も deny で禁止しています（CLAUDE.md「gh と git push の実行」）。

作業ディレクトリで、`git push` で始まる単独のコマンドとして実行してください。`git -C`・`cd`・ほかのコマンドとの連結・`$(...)` は使いません。ブランチ名などが必要なら、先に別のコマンドで調べて値をそのまま書いてください。

検出条件: `git` の後にオプションを挟んで `push` を呼び出し、次のどれかに当てはまるコマンド。

- `git push` で始まらない（`git -C <dir> push` など）
- `$(`・バッククォートを含む
- クォートの外に `|`・`&`・`;`・`<`・`>`・改行がある
