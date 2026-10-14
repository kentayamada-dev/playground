# playground

## リポジトリの設定

GitHub の設定は [`.github/settings`](.github/settings) に JSON で定義し、次のコマンドで反映します。何度実行しても同じ状態になります。`gh` と `jq` が必要です。

```bash
.github/scripts/sync-github-settings.sh
```

| 定義 | 対象 | 反映のしかた |
| --- | --- | --- |
| [`rulesets`](.github/settings/rulesets) | ルールセット | `name` が同じルールセットを更新し、なければ作成する。定義にないものは削除する |
| [`repository.json`](.github/settings/repository.json) | マージの方法・Wiki の有無・シークレットスキャン・プッシュ保護など | 定義に書いた項目だけを更新する |
| [`security.json`](.github/settings/security.json) | Dependabot・CodeQL など | 定義に書いた項目だけを、`true` なら有効に、`false` なら無効にする |
| [`actions.json`](.github/settings/actions.json) | GitHub Actions | 定義に書いた項目だけを更新する |
| [`labels.json`](.github/settings/labels.json) | issue と PR のラベル | 名前が同じラベルの色と説明を更新し、なければ作成する。定義にないものは削除する |

- 定義にないルールセットとラベルは、GitHub の画面で作ったものも削除される。消したラベルは issue や PR からも外れる。Organization のルールセットは対象外
- シークレットスキャンとプッシュ保護は、リポジトリの設定と同じ API で変えるため、`repository.json` の `security_and_analysis` に書く
- CodeQL のデフォルトセットアップは、今の設定と違うときだけ更新する

### GitHub Actions の設定

| 項目 | 設定 |
| --- | --- |
| 実行できるアクション | GitHub 公式と検証済み作成者のアクション、`patterns_allowed` に書いたアクションと再利用ワークフローだけ。ほかの作成者のアクションと、再利用ワークフローを使うときは `patterns_allowed` に足す |
| アクションのバージョン | 完全なコミット SHA で固定する |
| フォークからの PR | 外部の貢献者の PR のワークフローは、毎回承認してから動く |
| `GITHUB_TOKEN` の権限 | `permissions` を書かないワークフローでは読み取りだけ。ワークフローから PR を承認できない |

## 脆弱性とマルウェアの検査

依存関係に既知の脆弱性やマルウェアがないかを、[OSV-Scanner](https://google.github.io/osv-scanner/) と Dependabot で検査しています。結果はどれも Security タブに出ます。

| 仕組み | 実行のタイミング | 結果 |
| --- | --- | --- |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) の `osv-scanner` | PR ごと | PR のベースと比べて新しく入ったものがあると失敗する。必須チェックなので、失敗するとマージできない |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) の `osv-scanner-full` | `main` への push と毎日 | 見つかったものを Code scanning に出し、1 件でもあれば失敗する |
| Dependabot アラート | アドバイザリが公開されたときと、依存関係を変えて push したとき | 脆弱性を Dependabot のアラートに出す |

- GitHub の依存関係グラフは、`pnpm-lock.yaml` の 1 つ目の文書しか読まない（文書の順番を入れ替えて確認した）。pnpm 12 は、1 つ目の文書に pnpm 本体の版を書く。依存関係があるのは 2 つ目の文書（[Reading pnpm-lock.yaml](https://pnpm.io/lockfile)）。そのため、グラフに載るのは textlint の `package.json` にある直接の依存関係と pnpm 本体だけ。間接的な依存関係を検査しているのは OSV-Scanner だけ
- Dependabot のマルウェアアラートは有効にしていない。Dependabot が読むパッケージは、すべて OSV-Scanner でも検査しているため
- Actions のアクションは SHA で固定しているため、Dependabot のアラートは出ない（[Dependabot alerts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)）。OSV-Scanner もデフォルトでは Actions を検査しない
- 修正版がなく影響もない脆弱性は、ロックファイルと同じディレクトリの `osv-scanner.toml` に、理由と期限（`ignoreUntil`）を付けて除外する。設定はそのディレクトリのロックファイルにだけ効く（[Configuration](https://google.github.io/osv-scanner/configuration/)）

## シークレットの検査

トークンやパスワードなどのシークレットがコミットに含まれていないかを、[Betterleaks](https://github.com/betterleaks/betterleaks) で検査しています。

[`betterleaks.yml`](.github/workflows/betterleaks.yml) は、PR ごとと `main` への push で、`HEAD` からたどれる git 履歴全体を走査します。1 件でも見つかると失敗します。必須チェックなので、失敗するとマージできません。

- 見つかった値を実行ログに出さない（`--redact`）
- プロバイダーの API に問い合わせて、見つかったシークレットが有効かどうかは確認しない（`--validation` を付けていない）
- 誤検知は、その行のコメントに `betterleaks:allow` と書いて除外する
- 行にコメントを書けないときは、ルートの `.betterleaksignore` に fingerprint を 1 行ずつ書いて除外する。fingerprint の形式は `<コミット>:<パス>:<ルール ID>:<行番号>` で、`--report-format json` のレポートでは `Fingerprint` に出る
- Betterleaks は [mise](https://mise.jdx.dev/) で入れる。版はルートの [`mise.toml`](mise.toml) で固定し、Renovate が更新する。手元では `mise install` で同じ版を入れられる
- ダウンロードしたファイルは、mise がリリースの `checksums.txt` と、その cosign 署名で検証する（[aqua レジストリの定義](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/betterleaks/betterleaks/registry.yaml)）

## Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml) が日本時間の 0:23 から 3 時間ごとに Renovate を実行します。設定は [`.github/renovate.json5`](.github/renovate.json5) にあります。

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
