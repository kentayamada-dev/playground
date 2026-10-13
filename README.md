# playground

## リポジトリの設定

ルールセットは [`.github/rulesets`](.github/rulesets) に JSON で定義します。マージの方法や Wiki の有無などのリポジトリの設定は [`.github/repository.json`](.github/repository.json) に定義します。Dependabot や CodeQL などのセキュリティの設定は [`.github/security.json`](.github/security.json) に定義します。実行できるアクションなどの GitHub Actions の設定は [`.github/actions.json`](.github/actions.json) に定義します。どれも次のコマンドで GitHub に反映します。何度実行しても同じ状態になります。

- ルールセット: 定義の `name` と同じ名前のルールセットがあれば定義の内容で更新し、なければ作成する。定義にないルールセットは削除し、リポジトリのルールセットを定義と一致させる
- リポジトリの設定: 定義に書いた項目だけを更新する。シークレットスキャンとプッシュ保護は、リポジトリの設定と同じ API で変えるため、ここの `security_and_analysis` に書く
- セキュリティの設定: 定義に書いた項目だけを、`true` なら有効に、`false` なら無効にする。CodeQL のデフォルトセットアップは、今の設定と違うときだけ更新する
- GitHub Actions の設定: 実行できるのは、GitHub 公式と検証済み作成者のアクション、`patterns_allowed` に書いたアクションだけ。どれも完全なコミット SHA で固定する必要がある。ほかの作成者のアクションを使うときは、`patterns_allowed` に足す

```bash
.github/scripts/sync-github-settings.sh
```

- `gh` と `jq` が必要
- GitHub の画面で作ったルールセットも、定義になければ削除される。Organization のルールセットは対象外

## Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml) が毎時 23 分に Renovate を実行します。設定は [`.github/renovate.json5`](.github/renovate.json5) にあります。

### トークンの準備

Renovate は、リポジトリの secret `RENOVATE_TOKEN` に登録した Fine-grained personal access token で操作します。トークンは [作成画面](https://github.com/settings/personal-access-tokens/new) で次のように設定します。

| 項目 | 設定する値 |
| --- | --- |
| Token name | 任意（例: `renovate-playground`） |
| Description | 任意 |
| Resource owner | `kentayamada-dev` |
| Expiration | 任意。期限が切れると Renovate の実行が失敗する |
| Repository access | Only select repositories で `kentayamada-dev/playground` を選ぶ |

Repository permissions は次の表のとおりに設定し、ほかは No access のままにします。Account permissions もすべて No access のままにします。

| Permission | Access | 用途 |
| --- | --- | --- |
| Contents | Read and write | リポジトリの取得と、更新用ブランチの push |
| Pull requests | Read and write | 更新 PR の作成・更新と、自動マージの有効化 |
| Issues | Read and write | Dependency Dashboard の issue の作成・更新 |
| Commit statuses | Read and write | `renovate/stability-days` など、Renovate 自身のステータスの書き込み |
| Workflows | Read and write | `.github/workflows` 配下のファイルの更新 |
| Dependabot alerts | Read-only | 脆弱性アラートの読み取り。アラートがあると、Renovate が脆弱性を直す PR を作る |
| Metadata | Read-only | 自動で付く（必須） |

権限の一覧は [Renovate のドキュメント](https://docs.renovatebot.com/modules/platform/github/) に従っています。作成したトークンは、次のコマンドで secret に登録します。

```bash
gh secret set RENOVATE_TOKEN --repo kentayamada-dev/playground
```
