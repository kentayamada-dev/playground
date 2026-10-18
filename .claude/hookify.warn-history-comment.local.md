---
name: warn-history-comment
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.(?:sh|bash|zsh|bats|py|js|mjs|cjs|ts|tsx|jsx|ya?ml|toml|jsonc|json5|editorconfig|gitignore)$
  - field: content
    operator: regex_match
    pattern: (?:#|//|/\*|<!--|\n\s*\*)[^\n]*(?:以前は|旧実装|元々は|もともとは|(?:に|へ)変更(?:した|しました)?(?:[。.]|\s*(?:\n|$|\*/|-->)))
---

コードのコメントに変更履歴（「以前は〜」「〜に変更」など）を書こうとしています。

CONTRIBUTING.md「コメント」のとおり、変更履歴はコメントに書きません。経緯はコミットメッセージや PR に書き、コメントには「なぜ」の結論だけを残してください。既存のコメントを Edit の範囲に含めただけなら、この警告は無視してかまいません。

検出条件: 拡張子が `.sh`・`.bats`・`.yml`・`.toml` などのファイルへの Edit・Write で、コメント記号（`#`・`//`・`/*`・`<!--`）のある行に次のどれかを含むもの。

- 「以前は」「旧実装」「元々は」「もともとは」
- 行末・句点・コメントの閉じ記号の直前にある「に変更」「へ変更」（「〜変更した」「〜変更しました」を含む）
