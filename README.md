# playground

個人の実験用リポジトリです。GitHub のリポジトリの設定・CI・依存関係の更新を、Git で管理する定義とワークフローにまとめています。

- [コントリビューションガイド](CONTRIBUTING.md): issue・ブランチ・PR・コードの規約
- [行動規範](CODE_OF_CONDUCT.md)
- [セキュリティポリシー](SECURITY.md): 脆弱性を非公開で報告する手順
- [ライセンス](LICENSE): MIT License

## CI の検査

GitHub Actions で次の検査を実行します。必須チェックが通らない PR はマージできません。必須チェックは [`rulesets/main.json`](.github/settings/rulesets/main.json) に定義しています。

| ワークフロー | 実行のタイミング | 検査する内容 | 必須チェック |
| --- | --- | --- | --- |
| [`textlint.yml`](.github/workflows/textlint.yml) | PR・`main` への push | リポジトリのすべての `.md` の表記。ルールは [`.github/textlint`](.github/textlint) にある | `textlint` |
| [`test.yml`](.github/workflows/test.yml) | PR・`main` への push | `.sh` と `.bats` を ShellCheck で検査し、bats のテストを実行する | `test` |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | PR の作成・編集・push・再オープン | PR タイトルが Conventional Commits 形式に沿い、説明を日本語で書いているか。規約は [CONTRIBUTING.md](CONTRIBUTING.md#タイトルとコミットメッセージ) | `pr-title` |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) | PR・`main` への push・毎日 | 依存関係の脆弱性とマルウェア。詳しくは [脆弱性とマルウェアの検査](#脆弱性とマルウェアの検査) | `osv-scanner / osv-scan`（PR の検査だけ） |
| [`betterleaks.yml`](.github/workflows/betterleaks.yml) | PR・`main` への push | コミットに含まれるシークレット。詳しくは [シークレットの検査](#シークレットの検査) | `betterleaks` |
| [`commit-title.yml`](.github/workflows/commit-title.yml) | `main` への push | マージしたコミットのタイトルが、`pr-title` で検査した PR タイトルと同じか | なし（マージ後に実行する） |

- マージは squash だけで、PR タイトルがそのままコミットのタイトルになる（[`repository.json`](.github/settings/repository.json)）。マージの画面ではタイトルを書き換えられるため、`commit-title` がマージ後に照合する
- 必須チェックは、`main` の最新を取り込んだ状態で通す必要がある。`main` が先に進んだら、PR のブランチに取り込んでから検査し直す
- `textlint` と `test` は、PR で関係するファイルを変えていなければ、ステップを飛ばして成功になる。`on.pull_request.paths` で絞ると、実行されなかった PR の必須チェックが Pending のまま残るため
- ワークフローのほかに、CodeQL のデフォルトセットアップが GitHub Actions のワークフローを解析する。エラー・警告のアラートか、medium 以上の重大度のセキュリティアラートがあると、ルールセットの `code_scanning` ルールでマージできない

## リポジトリの設定

GitHub の設定は [`.github/settings`](.github/settings) に JSON で定義し、次のコマンドで反映します。何度実行しても同じ状態になります。`gh` と `jq` が必要です（`mise install` で入る）。

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

### 実行に必要な権限

実行するアカウントには、リポジトリの管理者権限が必要です。脆弱性アラートやプライベートな脆弱性報告などを切り替える API が、管理者権限を求めるためです（[リポジトリの REST API](https://docs.github.com/en/rest/repos/repos)）。

`gh` は `gh auth login` でログインしておきます。Actions や CodeQL の設定を変える API には、`repo` スコープが必要です（[Actions の権限の API](https://docs.github.com/en/rest/actions/permissions)・[CodeQL の API](https://docs.github.com/en/rest/code-scanning/code-scanning)）。`gh auth login` で発行されるトークンには、このスコープが含まれます（[gh の実装](https://github.com/cli/cli/blob/v2.102.0/internal/authflow/flow.go)）。

- 環境変数 `GH_TOKEN` か `GITHUB_TOKEN` があると、`gh` はログインしたトークンより優先してそちらを使う（`gh help environment`）。権限の足りないトークンが入っていると、途中で失敗する

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

## 使うツール

CI と手元のスクリプトで使うツール（Betterleaks・ShellCheck・bats・jq・gh）は、[mise](https://mise.jdx.dev/) で入れています。[`mise.toml`](mise.toml) で版を、[`mise.lock`](mise.lock) でダウンロードするファイルの sha256 を固定し、どちらも Renovate が更新します。手元でも `mise install` で同じ版を入れられます。

- mise-action は、`mise.lock` があると `mise install --locked` で入れる。`mise.lock` にない版やプラットフォームは入らないので、`mise.toml` を書き換えたら `mise lock` を実行して `mise.lock` も更新する
- `mise.lock` には、CI の linux-arm64 と、macOS（Apple シリコン）の macos-arm64 を記録している。ほかの環境で使うときは、`mise lock --platform` で足す
- 手元で mise を有効にしていると、このリポジトリでは `gh` も `mise.toml` の版を使う
- 署名は `mise lock` で `mise.lock` を更新するときに検証する。CI のインストールでは検証し直さず、`mise.lock` の sha256 と照合する（[`locked_verify_provenance`](https://mise.jdx.dev/configuration/settings.html#locked_verify_provenance)）
- Betterleaks は `checksums.txt` を cosign の署名で、jq と gh は GitHub の artifact attestations で検証する。検証の方法は、aqua レジストリの定義（[Betterleaks](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/betterleaks/betterleaks/registry.yaml)・[jq](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/jqlang/jq/registry.yaml)・[gh](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/cli/cli/registry.yaml)）に従う
- ShellCheck のリリースには署名もチェックサムのファイルもないので、`mise.lock` の sha256 は、GitHub がリリースのファイルごとに返す digest を使う
- bats はリリースにファイルがなく、タグのソースアーカイブを入れる。`mise lock` は sha256 を記録しないので、版（タグ）でだけ固定している

## Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml) が日本時間の 0:23 から 3 時間ごとに Renovate を実行します。設定は [`.github/renovate.json5`](.github/renovate.json5) にあります。

### 自動マージ

更新の種類によって、自動でマージするかどうかを分けています。

| 更新の種類 | マージのしかた |
| --- | --- |
| minor・patch・digest | 公開後 14 日を過ぎてから、自動でマージする |
| pin・pinDigest（バージョンやダイジェストの固定） | 自動でマージする |
| ロックファイルの更新 | 自動でマージする。PR は毎週月曜の 0〜3 時に作る |
| major など、上記以外の更新 | 自動ではマージしない。内容を確認して手動でマージする |

- 自動マージには GitHub の自動マージを使い、必須チェックがすべて通るとマージされる（[Renovate の自動マージ](https://docs.renovatebot.com/key-concepts/automerge/)・[GitHub の自動マージ](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)）
- 必須チェックは `main` の最新を取り込んだ状態で通す必要があるため、同じ実行で作った PR の 2 件目以降は、次の実行まで自動マージされない
- 更新の状況は、Dependency Dashboard の issue「chore(deps): 依存関係の更新状況」にまとまる

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
