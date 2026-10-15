# playground

個人の実験用リポジトリです。GitHub のリポジトリの設定・CI・依存関係の更新を、Git で管理する定義とワークフローにまとめています。

- [コントリビューションガイド](CONTRIBUTING.md): issue・ブランチ・PR・コードの規約
- [行動規範](CODE_OF_CONDUCT.md)
- [セキュリティポリシー](SECURITY.md): 脆弱性を非公開で報告する手順
- [ライセンス](LICENSE): MIT License

## CI の検査

GitHub Actions で、次のとおり検査します。必須チェックが通らない PR はマージできません。必須チェックは [`rulesets/main.json`](.github/settings/rulesets/main.json) に定義しています。

| ワークフロー | 実行のタイミング | 検査する内容 | 必須チェック |
| --- | --- | --- | --- |
| [`textlint.yml`](.github/workflows/textlint.yml) | PR・`main` への push | リポジトリのすべての `.md` の表記。ルールは [`.github/textlint`](.github/textlint) にある | `textlint` |
| [`test.yml`](.github/workflows/test.yml) | PR・`main` への push | `.sh` と `.bats` を ShellCheck で検査し、[shfmt](https://github.com/mvdan/sh) の整形に沿っているかを確認し、bats のテストを実行する。shfmt の整形の設定は [`.editorconfig`](.editorconfig) から読む | `test` |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | PR の作成・編集・push・再オープン | PR タイトルが Conventional Commits 形式に沿い、説明を日本語で書いているか。規約は [CONTRIBUTING.md](CONTRIBUTING.md#タイトルとコミットメッセージ) | `pr-title` |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) | PR・`main` への push・毎日 | 依存関係の脆弱性とマルウェア。詳しくは [脆弱性とマルウェアの検査](#脆弱性とマルウェアの検査) | `osv-scanner / osv-scan`（PR の検査だけ） |
| [`betterleaks.yml`](.github/workflows/betterleaks.yml) | PR・`main` への push | コミットに含まれるシークレット。詳しくは [シークレットの検査](#シークレットの検査) | `betterleaks` |
| [`editorconfig.yml`](.github/workflows/editorconfig.yml) | PR・`main` への push | git で管理するファイルが [`.editorconfig`](.editorconfig) の文字コード・改行・インデント・末尾の空白に沿っているか。[editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) で検査する | `editorconfig` |
| [`actionlint.yml`](.github/workflows/actionlint.yml) | PR・`main` への push | GitHub Actions のワークフローのキー・式・`run:` のスクリプト。[actionlint](https://github.com/rhysd/actionlint) で検査し、`run:` のスクリプトは actionlint から ShellCheck にかける。設定は [`.github/actionlint.yaml`](.github/actionlint.yaml) にある | `actionlint` |
| [`renovate-config-validator.yml`](.github/workflows/renovate-config-validator.yml) | PR・`main` への push | [`.github/renovate.json5`](.github/renovate.json5) の構文と、オプションの名前・値。Renovate の [renovate-config-validator](https://docs.renovatebot.com/config-validation/) で検査する | `renovate-config-validator` |

- マージは squash だけで、PR タイトルがそのままコミットのタイトルになる（[`repository.json`](.github/settings/repository.json)）。マージの画面や `gh pr merge --subject` で書き換えたタイトルは検査しない
- 必須チェックは、`main` の最新を取り込んだ状態で通す必要がある。`main` が先に進んだら、PR のブランチに取り込んでから検査し直す
- `textlint`・`test`・`renovate-config-validator` は、PR で関係するファイルを変えていなければ、ステップを飛ばして成功になる。`on.pull_request.paths` で絞ると、実行されなかった PR の必須チェックが Pending のまま残るため
- `editorconfig` は、PR で変えたファイルにかかわらず、リポジトリ全体を検査する。`pnpm-lock.yaml` など、editorconfig-checker がデフォルトで除外するファイルは検査しない（[Default Excludes](https://github.com/editorconfig-checker/editorconfig-checker/blob/v4.0.2/README.md#default-excludes)）
- `actionlint` は、PR で変えたファイルにかかわらず、すべてのワークフローを検査する。GitHub ホストのランナーのラベル `ubuntu-26.04-arm` を actionlint v1.7.12 が知らないため、`actionlint.yaml` でセルフホストのランナーのラベルとして認めている（[既知のラベルの一覧](https://github.com/rhysd/actionlint/blob/v1.7.12/rule_runner_label.go)）
- `renovate-config-validator` は、[`renovate.yml`](.github/workflows/renovate.yml) で動かす Renovate と同じ版の Docker イメージで検査する。エラーだけでなく警告でも失敗する。`--strict` を付けていないので、設定の移行が必要なだけでは失敗しない（[renovate-config-validator の実装](https://github.com/renovatebot/renovate/blob/44.151.1/lib/config-validator.ts#L101-L120)）
- ワークフローのほかに、CodeQL のデフォルトセットアップが GitHub Actions のワークフローを解析する。エラー・警告のアラートか、medium 以上の重大度のセキュリティアラートがあると、ルールセットの `code_scanning` ルールでマージできない
- CodeQL の解析は、`main` への push、`main` に向けた PR の作成と push、週 1 回の定期実行で動く。フォークからの PR は解析しない（[デフォルトセットアップ](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types)）

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

CI で使うツール（actionlint・Betterleaks・editorconfig-checker・ShellCheck・shfmt・bats・jq）は、[mise](https://mise.jdx.dev/) で入れています。[`.github/mise.toml`](.github/mise.toml) で版を、[`.github/mise.lock`](.github/mise.lock) でダウンロードするファイルの sha256 を固定し、どちらも Renovate が更新します。手元では使わないので、ルートではなく `.github` に置き、mise-action の `working_directory` で読ませています。

- mise-action は、`mise.lock` があると `mise install --locked` で入れる。`mise.lock` にない版やプラットフォームは入らないので、`mise.toml` を書き換えたら、`.github` で `mise lock` を実行して `mise.lock` も更新する
- `mise.lock` には、CI の linux-arm64 だけを記録している。`mise lock` は `--platform` を付けないと `mise.lock` にあるプラットフォームだけを対象にするので、手元で実行しても macOS などの記録は増えない（[`mise lock`](https://mise.jdx.dev/cli/lock.html)）
- 署名は `mise lock` で `mise.lock` を更新するときに検証する。CI のインストールでは検証し直さず、`mise.lock` の sha256 と照合する（[`locked_verify_provenance`](https://mise.jdx.dev/configuration/settings.html#locked_verify_provenance)）
- Betterleaks は `checksums.txt` を cosign の署名で、jq は GitHub の artifact attestations で検証する。検証の方法は、aqua レジストリの定義（[Betterleaks](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/betterleaks/betterleaks/registry.yaml)・[jq](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/jqlang/jq/registry.yaml)）に従う
- editorconfig-checker は、mise のレジストリで aqua ではなく github バックエンドを使う。GitHub の artifact attestations で検証する（[github バックエンド](https://mise.jdx.dev/dev-tools/backends/github.html)）
- shfmt は、mise のレジストリでは aqua バックエンドになるが、aqua レジストリの定義に検証の設定がない（[mvdan/sh](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/mvdan/sh/registry.yaml)）。そのため、`mise.toml` に `github:mvdan/sh` と書いて github バックエンドで入れ、GitHub の artifact attestations で検証する
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
- 脆弱性アラートから作る PR は、公開後 14 日を待たずに作られ、minor・patch の更新ならそのまま自動でマージされる（[Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)）。検証用ブランチで OSV の脆弱性情報から作らせた PR（[#141](https://github.com/kentayamada-dev/playground/pull/141)）で確認した。このとき Renovate は、`pnpm-workspace.yaml` の `minimumReleaseAgeExclude` に修正版を書き足す
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
