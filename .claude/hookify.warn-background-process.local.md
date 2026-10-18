---
name: warn-background-process
enabled: true
event: bash
action: warn
conditions:
  - field: command
    operator: regex_match
    pattern: ^(?:[^'"\\]|\\[\s\S]|'[^']*'|"(?:[^"\\]|\\[\s\S])*")*?(?<![&>|])&(?![&>])
  - field: command
    operator: not_contains
    pattern: kill -0
---

`&` でバックグラウンドのプロセスを起動していますが、親の shell の生存確認（`kill -0`）が見当たりません。

親の shell が `trap` や末尾の `kill` を実行せずに終わると、子は PPID 1 のまま残り続けます。CLAUDE.md「バックグラウンドのプロセス」の例のとおり、期限と親の shell の生存確認をループ自身に持たせてください。zsh が回すループには `ulimit -t` が効かず、macOS には標準で `timeout` がありません。

検出条件: クォートの外に単独の `&`（`&&`・`>&`・`&>`・`|&` を除く）があり、`kill -0` を含まないコマンド。
