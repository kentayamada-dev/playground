# playground

個人の実験用リポジトリです。GitHub のリポジトリの設定・CI・依存関係の更新を、Git で管理する定義とワークフローにまとめています。

- [コントリビューションガイド](CONTRIBUTING.md): issue・ブランチ・PR・コードの規約
- [行動規範](CODE_OF_CONDUCT.md)
- [セキュリティポリシー](SECURITY.md): 脆弱性を非公開で報告する手順
- [ライセンス](LICENSE): MIT License

## 開発環境

web（Node.js）と api（Go）を、別々の Dev Container で開発します。ホストの OS は macOS だけをサポートします。構成は VS Code の [Connect to multiple containers](https://code.visualstudio.com/remote/advancedcontainers/connect-multiple-containers) にならっています。

| コンテナ | 設定 | 開くディレクトリ | ベースイメージ |
| --- | --- | --- | --- |
| `web` | [`devcontainer.json`](.devcontainer/web/devcontainer.json)・[`Dockerfile`](.devcontainer/web/Dockerfile) | [`web`](web) | `node`（Node.js 26） |
| `api` | [`devcontainer.json`](.devcontainer/api/devcontainer.json)・[`Dockerfile`](.devcontainer/api/Dockerfile) | [`api`](api) | `golang`（Go 1.27） |

- macOS 以外のホストでは、コンテナを作る前に止める。両方の `devcontainer.json` の `initializeCommand` が、ホストで [`check-host-os.sh`](.devcontainer/scripts/check-host-os/check-host-os.sh) を実行する。理由はダイアログには出ず、コマンドパレットの「Dev Containers: Show Container Log」で開くログの末尾近くに出る
- 2 つのコンテナは、[`compose.yaml`](compose.yaml) のサービスとして動く。どちらも、リポジトリのルートを `/workspace` にマウントする。コンテナのなかでも git を使えるようにするため。イメージは公式イメージをもとに、コンテナごとの Dockerfile でビルドする。Dockerfile を変えたら「Dev Containers: Rebuild Container」で作り直す
- 一般ユーザー `dev` で動き、sudo は入れていない。root で作業するときは、手元のリポジトリのルートで `docker compose exec -u root api bash` のように実行する。ユーザー名は `compose.yaml` の `x-build-args` で渡している。変えるときは、両方の `devcontainer.json` の `remoteUser` も合わせる
- ホスト名は、端末のプロンプトで見分けられるよう、サービス名と同じ `web`・`api` にしている
- web は pnpm を使う。版は web の Dockerfile だけで管理し、Renovate が更新する。[`web/pnpm-workspace.yaml`](web/pnpm-workspace.yaml) は、`storeDir` のほかは textlint の [`pnpm-workspace.yaml`](.github/textlint/pnpm-workspace.yaml) とそろえている。api には `http://api:8080`（`compose.yaml` の `API_URL`）で接続する
- bash の履歴と、web の `node_modules`・pnpm のストアは、名前付きボリュームに置く。コンテナを作り直しても履歴を残し、macOS のバインドマウントで遅いインストールを速くするため。手元の `web/node_modules` は空のディレクトリになる
- ウィンドウを閉じても、コンテナは止めない（`shutdownAction: "none"`）。もう一方のコンテナで開いているウィンドウが切れないようにするため

### サーバーを起動する

コンテナを開いても、サーバーは起動しません。それぞれのコンテナのターミナルで、次のコマンドを実行します。

| コンテナ | コマンド | 動作 |
| --- | --- | --- |
| `api` | `go run .` | `GET /hello` に `{"message":"hello from api"}` を返す |
| `web` | `pnpm dev` | `GET /` で api の `/hello` を呼び、応答のメッセージを返す。ファイルを変えると再起動する |

サーバーが待ち受けているポートは、VS Code が手元に自動で転送します（`remote.autoForwardPorts`）。両方を起動したら、手元のブラウザで `http://localhost:3000` を開きます。

## CI の検査

GitHub Actions で、次のとおり検査します。必須チェックが通らない PR はマージできません。必須チェックは [`rulesets/main.json`](.github/settings/rulesets/main.json) に定義しています。

| ワークフロー | 検査する内容 | 必須チェック |
| --- | --- | --- |
| [`textlint.yml`](.github/workflows/textlint.yml) | リポジトリのすべての `.md` の表記。ルールは [`.github/textlint`](.github/textlint) にある | `textlint` |
| [`test.yml`](.github/workflows/test.yml) | `.sh` と `.bats` を ShellCheck で検査し、[shfmt](https://github.com/mvdan/sh) の整形に沿っているかを確認し、bats のテストを実行する。shfmt の整形の設定は [`.editorconfig`](.editorconfig) から読む | `test` |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | PR タイトルが Conventional Commits 形式に沿い、説明を日本語で書いているか。規約は [CONTRIBUTING.md](CONTRIBUTING.md#タイトルとコミットメッセージ) | `pr-title` |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) | 依存関係の脆弱性とマルウェア。詳しくは [脆弱性とマルウェアの検査](#脆弱性とマルウェアの検査) | `osv-scanner / osv-scan`（PR の検査だけ） |
| [`betterleaks.yml`](.github/workflows/betterleaks.yml) | コミットに含まれるシークレット。詳しくは [シークレットの検査](#シークレットの検査) | `betterleaks` |
| [`editorconfig.yml`](.github/workflows/editorconfig.yml) | git で管理するファイルが [`.editorconfig`](.editorconfig) の文字コード・改行・インデント・末尾の空白に沿っているか。[editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) で検査する | `editorconfig` |
| [`actionlint.yml`](.github/workflows/actionlint.yml) | GitHub Actions のワークフローのキー・式・`run:` のスクリプト。[actionlint](https://github.com/rhysd/actionlint) で検査し、`run:` のスクリプトは actionlint から ShellCheck にかける。設定は [`.github/actionlint.yaml`](.github/actionlint.yaml) にある | `actionlint` |
| [`renovate-config-validator.yml`](.github/workflows/renovate-config-validator.yml) | [`.github/renovate.json5`](.github/renovate.json5) の構文と、オプションの名前・値。Renovate の [renovate-config-validator](https://docs.renovatebot.com/config-validation/) で検査する | `renovate-config-validator` |
| [`zizmor.yml`](.github/workflows/zizmor.yml) | GitHub Actions のワークフローのセキュリティ上の問題。テンプレートインジェクション・広すぎる権限・checkout の資格情報の残留・フォークにしかないコミットへの固定などを、[zizmor](https://github.com/zizmorcore/zizmor) で検査する | `zizmor` |
| [`ghalint.yml`](.github/workflows/ghalint.yml) | GitHub Actions のワークフローが、すべてのジョブに `timeout-minutes` を書いているか、シークレットを必要なステップだけに渡しているかなど。[ghalint](https://github.com/suzuki-shunsuke/ghalint) で検査する | `ghalint` |
| [`lychee.yml`](.github/workflows/lychee.yml) | リポジトリのすべてのファイルに書いたリンクが切れていないか。[lychee](https://github.com/lycheeverse/lychee) で検査する。PR と `main` への push ではリポジトリ内のリンクだけ、毎週の実行では外部のリンクも検査する | `lychee`（リポジトリ内のリンクの検査だけ） |
| [`typos.yml`](.github/workflows/typos.yml) | リポジトリのすべてのファイルの英単語の綴り。[typos](https://github.com/crate-ci/typos) で検査する。設定は [`.github/typos.toml`](.github/typos.toml) にある | `typos` |
| [`markdownlint.yml`](.github/workflows/markdownlint.yml) | すべての `.md` の書式。見出しのレベル・リストの記号・表の列数・空行・コードブロックの言語の指定など。[markdownlint](https://github.com/DavidAnson/markdownlint) で検査する。設定は [`.github/markdownlint-cli2.jsonc`](.github/markdownlint-cli2.jsonc) にある | `markdownlint` |
| [`yamllint.yml`](.github/workflows/yamllint.yml) | `.yml`・`.yaml` の構文と書式。キーの重複・インデント・コメントの書き方など。[yamllint](https://github.com/adrienverge/yamllint) で検査する。設定は [`.github/yamllint/.yamllint.yaml`](.github/yamllint/.yamllint.yaml) にある | `yamllint` |
| [`hadolint.yml`](.github/workflows/hadolint.yml) | Dockerfile の書き方。ベースイメージのタグの指定・`apt-get install` の版の固定など。[hadolint](https://github.com/hadolint/hadolint) で検査し、`RUN` のスクリプトは hadolint に組み込まれた ShellCheck にかける。設定は [`.github/hadolint.yaml`](.github/hadolint.yaml) にある | `hadolint` |
| [`settings-drift.yml`](.github/workflows/settings-drift.yml) | GitHub のルールセット・リポジトリ・セキュリティ・Actions・ラベルの設定が、[`.github/settings`](.github/settings) の定義と一致しているか。詳しくは [定義とのずれの検査](#定義とのずれの検査) | なし |

どのワークフローも、PR と `main` への push で動きます。動くタイミングが違うのは、次の 4 つです。

- `pr-title.yml` は、PR の作成・編集・push・再オープンで動く
- `osv-scanner.yml` は毎日、`lychee.yml` は毎週も動く
- `settings-drift.yml` は、毎日と手動の実行でだけ動く

### マージの条件

- マージは squash だけで、PR タイトルがそのままコミットのタイトルになる（[`repository.json`](.github/settings/repository.json)）。マージの画面や `gh pr merge --subject` で書き換えたタイトルは検査しない
- 必須チェックは、`main` の最新を取り込んだ状態で通す必要がある。`main` が先に進んだら、PR のブランチに取り込んでから検査し直す
- 必須チェックのほかに、CodeQL のアラートがあってもマージできない。詳しくは [CodeQL](#codeql)

### 検査する範囲

チェックごとに、次の範囲を検査します。どのチェックも、PR で変えたファイルにかかわらず、毎回すべてを検査します。

| チェック | 検査する範囲 |
| --- | --- |
| `textlint`・`markdownlint` | リポジトリのすべての `.md` |
| `test` | リポジトリ全体の `.sh`・`.bats`。`.git` は除く |
| `editorconfig` | リポジトリ全体。`pnpm-lock.yaml` など、editorconfig-checker がデフォルトで除外するファイルは除く（[Default Excludes](https://github.com/editorconfig-checker/editorconfig-checker/blob/v4.0.2/README.md#default-excludes)） |
| `actionlint`・`zizmor`・`ghalint` | すべてのワークフロー |
| `renovate-config-validator` | [`.github/renovate.json5`](.github/renovate.json5) |
| `lychee` | リポジトリ全体。`.git` と、`.github/mise.lock`・`.github/yamllint/uv.lock` は除く |
| `typos` | リポジトリ全体。`.git` と、`typos.toml`・`pyproject.toml` など typos の設定ファイルと同じ名前のファイルは除く |
| `yamllint` | リポジトリ全体の `.yml`・`.yaml`。`pnpm-lock.yaml` と、`.venv`・`node_modules` の下は除く |
| `hadolint` | リポジトリ全体のうち、名前が `Dockerfile`・`Containerfile` のファイル。`Dockerfile.*`・`*.Dockerfile`・`Containerfile.*`・`*.Containerfile` に一致するファイルも含む。`.git` は除く |

- 必須チェックのワークフローは `on.pull_request.paths` で絞らない。絞ると、実行されなかった PR の必須チェックが Pending のまま残り、マージできない（[Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)）
- yamllint にはディレクトリを渡す。ディレクトリを渡すと、`uv sync` が作る `.venv` など、git で管理していないファイルまで読む（[`cli.py`](https://github.com/adrienverge/yamllint/blob/v1.38.0/yamllint/cli.py#L27-L37)）。そのため、[`.yamllint.yaml`](.github/yamllint/.yamllint.yaml) の `ignore` で `.venv` と `node_modules` を除いている
- lychee には、ディレクトリではなくグロブ `**/*` を渡す。ディレクトリを渡すと、`.md`・`.html` などの拡張子のファイルしか読まない（[`--extensions`](https://github.com/lycheeverse/lychee/blob/lychee-v0.24.2/README.md?plain=1#L456-L467)）。グロブに一致したファイルは、拡張子によらず読む（[`resolver.rs`](https://github.com/lycheeverse/lychee/blob/lychee-v0.24.2/lychee-lib/src/types/input/resolver.rs#L140-L144)）。[`.github/lychee.toml`](.github/lychee.toml) で隠しファイルも読ませ、`.git` を除いている
- typos は、デフォルトでは `.github`・`.devcontainer` など `.` で始まるファイルとディレクトリを読まない（[`files.ignore-hidden`](https://github.com/crate-ci/typos/blob/v1.51.1/docs/reference.md#filesignore-hidden)）。そのため、[`.github/typos.toml`](.github/typos.toml) で隠しファイルも読ませ、`.git` を除いている
- typos は、`typos.toml`・`Cargo.toml`・`pyproject.toml` など設定ファイルと同じ名前のファイルを、渡し方によらず読まない（[`file.rs`](https://github.com/crate-ci/typos/blob/v1.51.1/crates/typos-cli/src/file.rs#L942-L951)）。そのため、[`.github/typos.toml`](.github/typos.toml) と [`.github/yamllint/pyproject.toml`](.github/yamllint/pyproject.toml) は検査しない

### ツールごとの補足

#### 失敗する条件

次のツールは、軽い指摘でも失敗するように実行しています。

| ツール | 失敗する条件 |
| --- | --- |
| renovate-config-validator | `--strict` を付け、エラーと警告に加えて、設定の移行が必要なだけのときも失敗する（[renovate-config-validator の実装](https://github.com/renovatebot/renovate/blob/44.151.1/lib/config-validator.ts#L101-L120)） |
| zizmor | 指摘が 1 件でもあると失敗する。`--strict-collection` を付け、入力のファイルを解析できないときも失敗する（[Input collection](https://docs.zizmor.sh/usage/#input-collection)）。PR の注釈は最初の 10 件までで、残りはジョブのログにだけ出る（[Output formats](https://docs.zizmor.sh/usage/#output-formats)） |
| yamllint | `--strict` を付け、warning の指摘でも失敗する（[Errors and warnings](https://yamllint.readthedocs.io/en/stable/configuration.html#errors-and-warnings)） |
| hadolint | [`.github/hadolint.yaml`](.github/hadolint.yaml) の `failure-threshold: style` で、重大度が style の指摘でも失敗する。デフォルトの `info` のままだと、style の指摘で失敗しない（[CLI](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#cli)）。`label-schema` のラベルがないときと、`strict-labels` でそれ以外のラベルがあるときも失敗する（[Linting Labels](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#linting-labels)） |

#### 指摘を無視する方法

| ツール | 無視する方法 |
| --- | --- |
| zizmor | YAML の該当する行に `# zizmor: ignore[<監査名>]` と書く（[Ignoring results](https://docs.zizmor.sh/usage/#ignoring-results)） |
| typos | 誤検知は、[`.github/typos.toml`](.github/typos.toml) の `extend-ignore-re` に、その箇所だけに一致する正規表現を足して除外する（[`default.extend-ignore-re`](https://github.com/crate-ci/typos/blob/v1.51.1/docs/reference.md#defaultextend-ignore-re)） |
| markdownlint | 該当する行の前に `<!-- markdownlint-disable-next-line <ルール名> -->` と書く（[Configuration](https://github.com/DavidAnson/markdownlint/blob/v0.41.1/README.md#configuration)） |
| yamllint | 該当する行に `# yamllint disable-line rule:<ルール名>` と書く（[Disable with comments](https://yamllint.readthedocs.io/en/stable/disable_with_comments.html#disabling-checks-for-a-specific-line)） |
| hadolint | 該当する命令の前の行に `# hadolint ignore=<ルール名>` と書く（[Inline ignores](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#inline-ignores)） |
| Betterleaks | その行のコメントに `betterleaks:allow` と書く。書けないときは、[シークレットの検査](#シークレットの検査) のとおり `.betterleaksignore` を使う |

#### actionlint

- actionlint v1.7.12 は、GitHub ホストのランナーのラベル `ubuntu-26.04-arm` を知らない（[既知のラベルの一覧](https://github.com/rhysd/actionlint/blob/v1.7.12/rule_runner_label.go)）。そのため、[`actionlint.yaml`](.github/actionlint.yaml) でセルフホストのランナーのラベルとして認めている

#### renovate-config-validator

- [`renovate.yml`](.github/workflows/renovate.yml) で動かす Renovate と同じ版の Docker イメージを、ジョブのコンテナにして使う

#### zizmor

- `GITHUB_TOKEN` を渡し、GitHub API で調べる監査も動かす（[Operating modes](https://docs.zizmor.sh/usage/#operating-modes)）。対象は `impostor-commit`・`known-vulnerable-actions`・`ref-confusion` の 3 つ

#### ghalint

zizmor の監査にない次のポリシーのために使います（[Policies](https://github.com/suzuki-shunsuke/ghalint/blob/v1.5.6/README.md#policies)・[zizmor の監査の一覧](https://docs.zizmor.sh/audits/)）。

- `job_timeout_minutes_is_required` は、すべてのジョブに `timeout-minutes` を求める
- `workflow_secrets`・`job_secrets` は、シークレットをワークフロー・ジョブの `env` に置かせない

#### lychee

- ネットワークを使わず（`--offline`）、リポジトリ内のファイルへのリンクと見出しのアンカーだけを確認する。外部のサイトの障害やレート制限で、PR をマージできなくならないようにするため
- Markdown と HTML 以外のファイルからは URL だけを拾い、コメントに書いた相対パスは検査しない

#### markdownlint

- [markdownlint-cli2-action](https://github.com/DavidAnson/markdownlint-cli2-action) に同梱された markdownlint-cli2 で検査する。npm から依存関係を取得しないので、`package.json` とロックファイルはない。markdownlint-cli2 の版は、アクションの版で決まる
- 行の長さと 1 行目の見出しのルールだけを無効にしている。editorconfig や lychee の検査と重なるルールも有効のままにしている

#### yamllint

- デフォルトの設定から、次の 4 つを変えている。理由は [`.yamllint.yaml`](.github/yamllint/.yamllint.yaml) のコメントに書いている
  - 行の長さ（`line-length`）と、ファイルの先頭の `---`（`document-start`）を検査しない
  - 真偽値の書き方（`truthy`）は、値だけを検査し、キーは検査しない
  - 行末のコメントの前の空白（`comments`）は、1 つでよい
- yamllint の入れ方は [yamllint の依存関係](#yamllint-の依存関係) にある

#### hadolint

- 対象のファイルが 1 つもなければ、hadolint を実行せずに成功する。hadolint は、ファイルを渡さないと失敗するため（[`app/Main.hs`](https://github.com/hadolint/hadolint/blob/v2.15.1/app/Main.hs#L58-L59)）
- `RUN` のスクリプトは、hadolint にライブラリとして組み込まれた ShellCheck で検査する。mise で入れる ShellCheck は使わない（[`hadolint.cabal`](https://github.com/hadolint/hadolint/blob/v2.15.1/hadolint.cabal#L169)）
- 設定は [`.github/hadolint.yaml`](.github/hadolint.yaml) に書き、`--config` で渡す。設定ファイルを解釈できないと、hadolint はエラーを出すだけで、デフォルトの設定で検査を続ける（[`app/Main.hs`](https://github.com/hadolint/hadolint/blob/v2.15.1/app/Main.hs#L89-L93)）。そのため、style の指摘だけが出る Dockerfile を標準入力から渡し、失敗することを先に確認する。ラベルの指摘（DL3049・DL3050）は info で、デフォルトのしきい値でも失敗するので、この確認では外す
- Dockerfile のラベルは、`.github/hadolint.yaml` の `label-schema` に挙げた 4 つだけを書く。値は変数で渡さず、各 Dockerfile に直接書く。変数で渡すと型を `text` にするしかなく、URL と SPDX の形式を検査できないため（[Note on dealing with variables in labels](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#note-on-dealing-with-variables-in-labels)）

### 外部リンクの定期検査

外部のリンクは、[`lychee.yml`](.github/workflows/lychee.yml) の `lychee-external` が毎週月曜と手動の実行（`workflow_dispatch`）で検査します。必須チェックではありません。

- `429`・`502`・`503`・`504` は成功として扱う。レート制限の `429` は、リンク切れとは限らないため。`502`〜`504` は github.com がときどき返す一時的なエラーで、lychee v0.24.2 は `--max-retries` によらずリトライしないため（[#2319](https://github.com/lycheeverse/lychee/issues/2319)）
- `mise.lock` と `uv.lock` の URL は、`mise lock` と `uv lock` が書くものなので、[`.github/lychee.toml`](.github/lychee.toml) で検査から除く
- web と api のサーバーのアドレス（`http://localhost:3000` など）は、CI から接続できないため、[`.github/lychee.toml`](.github/lychee.toml) で検査から除く
- 通らないリンクがあると、[`report-broken-links.sh`](.github/scripts/report-broken-links/report-broken-links.sh) が issue「docs: 外部リンクの定期検査で見つかったリンク切れを直す」を作る。開いていれば、本文を最新の結果に書き換える
- リンクを直したら、issue は手動で閉じる

### CodeQL

ワークフローのほかに、CodeQL のデフォルトセットアップが GitHub Actions のワークフローを解析します。

- エラー・警告のアラートか、medium 以上の重大度のセキュリティアラートがあると、ルールセットの `code_scanning` ルールでマージできない
- 解析は、`main` への push、`main` に向けた PR の作成と push、週 1 回の定期実行で動く。フォークからの PR は解析しない（[デフォルトセットアップ](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types)）

## リポジトリの設定

GitHub の設定は [`.github/settings`](.github/settings) に JSON で定義し、次のコマンドで反映します。何度実行しても同じ状態になります。`gh` と `jq` が必要です。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh
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
- CodeQL のデフォルトセットアップも毎回送る。設定が変わらなければ、新しい解析は始まらない（[#190](https://github.com/kentayamada-dev/playground/pull/190) で確認）

### 実行に必要な権限

`gh` は `gh auth login` でログインしておきます。実行するアカウントとトークンには、次の権限が必要です。

| 必要な権限 | 理由 |
| --- | --- |
| リポジトリの管理者権限 | 脆弱性アラートやプライベートな脆弱性報告などを切り替える API が求めるため（[リポジトリの REST API](https://docs.github.com/en/rest/repos/repos)） |
| トークンの `repo` スコープ | Actions や CodeQL の設定を変える API が求めるため（[Actions の権限の API](https://docs.github.com/en/rest/actions/permissions)・[CodeQL の API](https://docs.github.com/en/rest/code-scanning/code-scanning)）。`gh auth login` で発行されるトークンには含まれる（[gh の実装](https://github.com/cli/cli/blob/v2.102.0/internal/authflow/flow.go)） |

- 環境変数 `GH_TOKEN` か `GITHUB_TOKEN` があると、`gh` はログインしたトークンより優先してそちらを使う（`gh help environment`）。権限の足りないトークンが入っていると、途中で失敗する

### 定義とのずれの検査

`--check` を付けると、GitHub を変えずに、反映すると変わる箇所を定義とのずれとして示します。ずれがあれば、終了コード 1 で終わります。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh --check
```

- ルールセットは、GitHub が付ける `id`・`node_id`・`created_at` などを除き、定義と完全に一致するかを比べる
- ほかの設定は、定義に書いた項目だけを比べる。定義に書いた項目が GitHub の応答になければ、ずれとして示す
- 配列は並び順を無視して比べる。GitHub は `patterns_allowed` などを、定義と違う順で返すことがあるため

[`settings-drift.yml`](.github/workflows/settings-drift.yml) が毎日これを実行し、ずれがあるか検査に失敗すると issue を作ります。開いている issue があれば、新しく作らずに本文を最新の結果に書き換えます。ずれは、定義を直すか、同期のコマンドで GitHub を定義に揃えて直します。

- 定義を変えた PR をマージしたら、同期のコマンドを実行する。実行し忘れると、次の検査で issue になる

#### 検査に使うトークン

Actions の権限などを読むには Administration の権限が必要ですが、`GITHUB_TOKEN` には与えられません（[`permissions` のキー](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)）。そのため、リポジトリの secret `SETTINGS_READ_TOKEN` に登録した Fine-grained personal access token で読みます。issue の作成には、ワークフローの `GITHUB_TOKEN` を使います。

トークンは [トークンの作り方](#トークンの作り方) のとおりに作り、Repository permissions を次の表のとおりに設定します。

| Permission | Access | 用途 |
| --- | --- | --- |
| Administration | Read-only | Actions の権限・脆弱性アラート・セキュリティアップデート・リリースの不変化・CodeQL のデフォルトセットアップの取得 |
| Contents | Read and write | マージの方法・自動マージ・マージ後のブランチの削除など、マージ関連の設定の取得。読むだけでも書き込みの権限が要る（[Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository)） |
| Issues | Read-only | ラベルの取得 |
| Metadata | Read-only | 自動で付く（必須）。ルールセット・リポジトリの設定・脆弱性の非公開報告の取得 |

権限の一覧は [Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) に従っています。作成したトークンは、次のコマンドで secret に登録します。

```bash
gh secret set SETTINGS_READ_TOKEN --repo kentayamada-dev/playground
```

- Contents の書き込みの権限があるため、このトークンではブランチやタグを push できる
- ルールセットの `bypass_actors` は、Administration が Read-only のこのトークンでも返る。ドキュメントには、ルールセットへの書き込み権限がなければ返さないとある（[Get a repository ruleset](https://docs.github.com/en/rest/repos/rules#get-a-repository-ruleset)）

### GitHub Actions の設定

| 項目 | 設定 |
| --- | --- |
| 実行できるアクション | GitHub 公式・検証済み作成者のアクションと、`patterns_allowed` に書いたアクション・再利用ワークフローだけ。ほかの作成者のアクションや、再利用ワークフローを使うときは、`patterns_allowed` に足す |
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

- 間接的な依存関係を検査しているのは OSV-Scanner だけ。GitHub の依存関係グラフは、どちらのロックファイルからも間接的な依存関係を読まないため
  - 依存関係グラフは、`pnpm-lock.yaml` の 1 つ目の文書しか読まない（文書の順番を入れ替えて確認した）
  - pnpm 12 は、1 つ目の文書に pnpm 本体の版を書く。依存関係があるのは 2 つ目の文書（[Reading pnpm-lock.yaml](https://pnpm.io/lockfile)）
  - yamllint の `uv.lock` は、依存関係グラフが読むファイルの一覧にない（[Dependency graph supported package ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems)）
- Dependabot のマルウェアアラートは有効にしていない。Dependabot が読むパッケージは、すべて OSV-Scanner でも検査しているため
- Actions のアクションは SHA で固定しているため、Dependabot のアラートは出ない（[Dependabot alerts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)）。OSV-Scanner もデフォルトでは Actions を検査しない
- 修正版がなく影響もない脆弱性は、ロックファイルと同じディレクトリの `osv-scanner.toml` に、理由と期限（`ignoreUntil`）を付けて除外する（例: [`.github/textlint/osv-scanner.toml`](.github/textlint/osv-scanner.toml)）。設定はそのディレクトリのロックファイルにだけ効く（[Configuration](https://google.github.io/osv-scanner/configuration/)）

## シークレットの検査

トークンやパスワードなどのシークレットがコミットに含まれていないかを、[Betterleaks](https://github.com/betterleaks/betterleaks) で検査しています。

[`betterleaks.yml`](.github/workflows/betterleaks.yml) は、PR ごとと `main` への push で、`HEAD` からたどれる git 履歴全体を走査します。1 件でも見つかると失敗します。必須チェックなので、失敗するとマージできません。

- 見つかった値を実行ログに出さない（`--redact`）
- プロバイダーの API に問い合わせて、見つかったシークレットが有効かどうかは確認しない（`--validation` を付けていない）
- 誤検知の除外のしかたは、[指摘を無視する方法](#指摘を無視する方法) の表にまとめている
- 行にコメントを書けないときは、ルートの `.betterleaksignore` に fingerprint を 1 行ずつ書いて除外する。fingerprint の形式は `<コミット>:<パス>:<ルール ID>:<行番号>` で、`--report-format json` のレポートでは `Fingerprint` に出る

## 使うツール

CI のツールは、[mise](https://mise.jdx.dev/) で入れています。対象は、[ダウンロードするファイルの検証](#ダウンロードするファイルの検証) の表に並べたツールです。[`.github/mise.toml`](.github/mise.toml) で版を、[`.github/mise.lock`](.github/mise.lock) でダウンロードするファイルの sha256 を固定し、どちらも Renovate が更新します。手元では使わないので、ルートではなく `.github` に置き、mise-action の `working_directory` で読ませています。

### `mise.lock` の更新

- `mise.toml` を書き換えたら、`.github` で `mise lock` を実行して `mise.lock` も更新する。mise-action は、`mise.lock` があると `mise install --locked` で入れる。そのため、`mise.lock` にない版やプラットフォームは入らない
- `mise.lock` には、CI の linux-arm64 だけを記録している。`mise lock` は `--platform` を付けないと `mise.lock` にあるプラットフォームだけを対象にするので、手元で実行しても macOS などの記録は増えない（[`mise lock`](https://mise.jdx.dev/cli/lock.html)）

### ダウンロードするファイルの検証

署名は、`mise lock` で `mise.lock` を更新するときに検証します。CI のインストールでは検証し直さず、`mise.lock` の sha256 と照合します（[`locked_verify_provenance`](https://mise.jdx.dev/configuration/settings.html#locked_verify_provenance)）。

バックエンドは `mise.lock` の `backend` の値です。

| ツール | バックエンド | 検証の方法 |
| --- | --- | --- |
| Betterleaks | aqua | `checksums.txt` を cosign の署名で検証する（[aqua レジストリの定義](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/betterleaks/betterleaks/registry.yaml)） |
| actionlint・hadolint・jq・uv・zizmor | aqua | GitHub の artifact attestations で検証する（aqua レジストリの定義: [actionlint](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/rhysd/actionlint/registry.yaml)・[hadolint](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/hadolint/hadolint/registry.yaml)・[jq](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/jqlang/jq/registry.yaml)・[uv](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/astral-sh/uv/registry.yaml)・[zizmor](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/zizmorcore/zizmor/registry.yaml)） |
| editorconfig-checker・shfmt・ghalint・typos | github | GitHub の artifact attestations で検証する（[github バックエンド](https://mise.jdx.dev/dev-tools/backends/github.html)） |
| ShellCheck | aqua | リリースに署名もチェックサムのファイルもない。`mise.lock` の sha256 は、GitHub がリリースのファイルごとに返す digest を使う |
| lychee | aqua | リリースに署名も GitHub の artifact attestations もない。aqua レジストリの定義にも検証の設定がない（[lycheeverse/lychee](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/lycheeverse/lychee/registry.yaml)）。`mise.lock` の sha256 は、GitHub がリリースのファイルごとに返す digest と同じ値になる |
| bats | aqua | リリースにファイルがなく、タグのソースアーカイブを入れる。`mise lock` は sha256 を記録しないので、版（タグ）でだけ固定している |

- editorconfig-checker は、mise のレジストリで github バックエンドが指定されている
- shfmt・ghalint・typos は、mise のレジストリでは aqua バックエンドになる。aqua レジストリの定義を mise が検証に使えないため、github バックエンドで入れている。`mise.toml` には `github:mvdan/sh`・`github:suzuki-shunsuke/ghalint`・`github:crate-ci/typos` と書く
  - shfmt は、aqua レジストリの定義に検証の設定がない（[mvdan/sh](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/mvdan/sh/registry.yaml)）
  - ghalint は、aqua レジストリの定義の検証を mise が使えない（[suzuki-shunsuke/ghalint](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/suzuki-shunsuke/ghalint/registry.yaml)）。cosign は `opts` で渡す形で、mise がネイティブに検証するキーやバンドルの指定がない。SLSA provenance には、署名者の指定がない（[aqua バックエンドの実装](https://github.com/jdx/mise/blob/v2026.9.18/src/backend/aqua.rs#L1368-L1404)）
  - typos は、aqua レジストリの定義に検証の設定がない（[crate-ci/typos](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/crate-ci/typos/registry.yaml)）。リリースのファイルに付く attestation は、タグとファイルを結び付けるリリースの attestation だけで、ビルドしたワークフローを含まない

### yamllint の依存関係

yamllint は Python のパッケージで、PyYAML と pathspec に依存します（[PyPI](https://pypi.org/project/yamllint/)）。依存関係まで版と sha256 を固定するため、mise ではなく uv で入れています。uv 本体は mise で入れます。

- [`.github/yamllint`](.github/yamllint) の `pyproject.toml` で yamllint の版を、`uv.lock` で依存関係を含むすべての版と sha256 を固定する
- `pyproject.toml` を書き換えたら、`.github/yamllint` で `uv lock` を実行して `uv.lock` も更新する。CI は `uv sync --locked` で入れるため、`uv.lock` が古いと失敗する（[`uv sync`](https://docs.astral.sh/uv/reference/cli/#uv-sync)）
- `pyproject.toml` と `uv.lock` は、Renovate の pep621 マネージャーが更新する（[pep621](https://docs.renovatebot.com/modules/manager/pep621/)）

## Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml) が毎時 23 分に Renovate を実行します。設定は [`.github/renovate.json5`](.github/renovate.json5) にあります。

### 自動マージ

更新の種類によって、自動でマージするかどうかを分けています。

| 更新の種類 | マージのしかた |
| --- | --- |
| minor・patch・digest | 公開後 14 日を過ぎてから、自動でマージする |
| pin・pinDigest（バージョンやダイジェストの固定） | 自動でマージする |
| ロックファイルの更新 | 自動でマージする。PR は毎週月曜の 0〜3 時に作る |
| major など、上記以外の更新 | 自動ではマージしない。内容を確認して手動でマージする |

- 自動マージには GitHub の自動マージを使い、必須チェックがすべて通るとマージされる（[Renovate の自動マージ](https://docs.renovatebot.com/key-concepts/automerge/)・[GitHub の自動マージ](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)）
- [マージの条件](#マージの条件) のとおり `main` の最新を取り込む必要があるため、同じ実行で作った PR の 2 件目以降は、次の実行まで自動マージされない
- 脆弱性アラートから作る PR は、公開後 14 日を待たずに作られる。minor・patch の更新なら、そのまま自動でマージされる（[Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)）。このとき Renovate は、`pnpm-workspace.yaml` の `minimumReleaseAgeExclude` に修正版を書き足す
  - 検証用ブランチで OSV の脆弱性情報から作らせた PR（[#141](https://github.com/kentayamada-dev/playground/pull/141)）で確認した
- 更新の状況は、Dependency Dashboard の issue「chore(deps): 依存関係の更新状況」にまとまる

### トークンの準備

Renovate は、リポジトリの secret `RENOVATE_TOKEN` に登録した Fine-grained personal access token で操作します。トークンは [トークンの作り方](#トークンの作り方) のとおりに作り、Repository permissions を次の表のとおりに設定します。

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

## トークンの作り方

[定義とのずれの検査](#検査に使うトークン) と [Renovate](#トークンの準備) が使う Fine-grained personal access token は、[作成画面](https://github.com/settings/personal-access-tokens/new) で次のように作ります。

| 項目 | 設定する値 |
| --- | --- |
| Token name | 任意（例: `settings-read-playground`・`renovate-playground`） |
| Description | 任意 |
| Resource owner | `kentayamada-dev` |
| Expiration | 任意。期限が切れると、定義とのずれの検査は失敗して issue が作られ、Renovate は実行が失敗する |
| Repository access | Only select repositories で `kentayamada-dev/playground` を選ぶ |
| Repository permissions | それぞれの節の表のとおりに設定し、ほかは No access のままにする |
| Account permissions | すべて No access のままにする |
