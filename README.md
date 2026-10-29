# playground

個人の実験用リポジトリです。GitHub のリポジトリの設定・CI・依存関係の更新を、Git で管理する定義とワークフローにまとめています。

- [コントリビューションガイド](CONTRIBUTING.md): issue・ブランチ・PR・コードの規約
- [行動規範](CODE_OF_CONDUCT.md)
- [セキュリティポリシー](SECURITY.md): 脆弱性を非公開で報告する手順
- [ライセンス](LICENSE): MIT License

## 開発環境

node と golang を、別々の Dev Container で開発します。ホストの OS は macOS だけをサポートします。構成は VS Code の [Connect to multiple containers](https://code.visualstudio.com/remote/advancedcontainers/connect-multiple-containers) にならっています。

| コンテナ | 設定                                                                                                           | 開くディレクトリ   | ベースイメージ |
| -------- | -------------------------------------------------------------------------------------------------------------- | ------------------ | -------------- |
| `node`   | [`devcontainer.json`](.devcontainer/node/devcontainer.json)・[`Dockerfile`](.devcontainer/node/Dockerfile)     | [`node`](node)     | `node`         |
| `golang` | [`devcontainer.json`](.devcontainer/golang/devcontainer.json)・[`Dockerfile`](.devcontainer/golang/Dockerfile) | [`golang`](golang) | `golang`       |

- macOS 以外のホストでは、コンテナを作る前に止める。両方の `devcontainer.json` の `initializeCommand` が、ホストで [`check-host-os.sh`](.devcontainer/scripts/check-host-os/check-host-os.sh) を実行する。理由はダイアログには出ず、コマンドパレットの「Dev Containers: Show Container Log」で開くログの末尾近くに出る
- 2 つのコンテナは、[`compose.yaml`](compose.yaml) のサービスとして動く。どちらも、リポジトリのルートを `/workspace` にマウントする。イメージは公式イメージをもとに、コンテナごとの Dockerfile でビルドする。Dockerfile を変えたら「Dev Containers: Rebuild Container」で作り直す
- 一般ユーザー `dev` で動き、sudo は入れていない。root で作業するときは、手元のリポジトリのルートで `docker compose exec -u root golang bash` のように実行する。ユーザー名は `compose.yaml` の `x-build-args` で渡している
- node は pnpm を使う。版は node の Dockerfile だけで管理し、Renovate が更新する。[`node/pnpm-workspace.yaml`](node/pnpm-workspace.yaml) は、`storeDir` のほかは textlint の [`pnpm-workspace.yaml`](.github/textlint/pnpm-workspace.yaml) とそろえている。golang には、`compose.yaml` の `GOLANG_URL` のアドレスで接続する
- node では npm を使えない。`npm install`・`npm run` などは、`EBADDEVENGINES` のエラーで止まる。[`node/package.json`](node/package.json) の `devEngines.packageManager` で pnpm を指定しているため（[devEngines](https://docs.npmjs.com/cli/v11/configuring-npm/package-json#devengines)）
- `devEngines.packageManager` には版を書かず、pnpm の版は Dockerfile の 1 か所で管理する。pnpm は `onFail` を省くと `download` として扱うため、`error` を明示している（[pmOnFail](https://pnpm.io/settings/cli#pmonfail)）
- node・textlint・oxfmt の pnpm は、本体とパッケージを Takumi Guard のレジストリ（`https://npm.flatt.tech/`）から取得する。`npmjs:` と `@jsr` スコープも同じレジストリに向け、`gh:`（GitHub Packages）は使えないようにしている（[Registries](https://pnpm.io/registries)）
- 公開から 1 日（`minimumReleaseAge: 1440` 分）経っていない版は入れない。待機期間を満たす版がないときと、レジストリが公開日時を返さないときは、インストールが失敗する。以前の版より信頼のレベルが下がった版も入れない（`trustPolicy: no-downgrade`）。どれも [pnpm の設定](https://pnpm.io/settings/dependency-resolution) による
- golang は、gopls・gofumpt・staticcheck をイメージに入れている。版は [`.devcontainer/golang/tools`](.devcontainer/golang/tools) のツールごとの `go.mod` で管理し、Renovate が更新する
- bash の履歴、node の `node_modules`・pnpm のストア、golang のモジュールとビルドのキャッシュは、名前付きボリュームに置く。コンテナを作り直しても、履歴とキャッシュは残る。手元の `node/node_modules` は空のディレクトリになる
- node のコンテナを作ると、`node` で `pnpm install` を実行する。インストールが終わってから、VS Code がコンテナに接続する
- ウィンドウを閉じても、コンテナは止めない（`shutdownAction: "none"`）
- 設定の理由は、[`compose.yaml`](compose.yaml)・`devcontainer.json`・Dockerfile のコメントに書いている

### コマンドでコンテナを開く

手元のリポジトリのルートで [`Makefile`](Makefile) のターゲットを実行すると、VS Code がそのコンテナのウィンドウを開きます。

- VS Code の `code` コマンドがないと、`exec: code: not found` で止まる。VS Code のコマンドパレットで「Shell Command: Install 'code' command in PATH」を実行して入れる（[VS Code のドキュメント](https://code.visualstudio.com/docs/setup/mac)）
- `open-devcontainer.sh` は、`code` の実行に `BUILDX_BAKE_ENTITLEMENTS_FS=0` を付ける。開いたウィンドウの build では、作業ディレクトリの外のファイルの読み書きと、SSH エージェントの転送の確認が止まる（[`entitlements.go`](https://github.com/docker/buildx/blob/v0.38.0/bake/entitlements.go#L280-L386)）
- VS Code の画面から開くときは、この変数を付けて起動した VS Code でないと build が失敗する。理由は `open-devcontainer.sh` のコメントに書いている。外す条件は [#272](https://github.com/kentayamada-dev/playground/issues/272) にある
- コンテナのウィンドウを開く方法は、公式のドキュメントでは確認できていないため、Dev Containers 拡張機能の更新で開けなくなるおそれがある
- `devcontainer.json` のコメントは、行頭からの `//` だけに対応する。行末のコメントや末尾のカンマがあると、読めずに止まる

### サーバーを起動する

コンテナを開いても、サーバーは起動しません。それぞれのコンテナのターミナルで、golang は [`golang/Makefile`](golang/Makefile) のターゲットを、node は [`node/package.json`](node/package.json) のスクリプトを `pnpm` で実行して起動します。

サーバーが待ち受けているポートは、VS Code が手元に自動で転送します（`remote.autoForwardPorts`）。両方を起動したら、手元のブラウザで `http://localhost:3000` を開きます。

## CI の検査

GitHub Actions で、次のとおり検査します。必須チェックが通らない PR はマージできません。必須チェックは [`rulesets/main.json`](.github/settings/rulesets/main.json) に定義しています。

| ワークフロー                                                                       | 検査する内容                                                                                                                                                                                                                                                                                                                                                                                                                   | 必須チェック                               |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------ |
| [`textlint.yml`](.github/workflows/textlint.yml)                                   | リポジトリのすべての `.md` の表記。ルールは [`.github/textlint`](.github/textlint) にある                                                                                                                                                                                                                                                                                                                                      | `textlint`                                 |
| [`test.yml`](.github/workflows/test.yml)                                           | `.sh` と `.bats` を ShellCheck で検査し、[shfmt](https://github.com/mvdan/sh) の整形に沿っているかを確認し、bats のテストを実行する。shfmt の整形の設定は [`.editorconfig`](.editorconfig) から読む                                                                                                                                                                                                                            | `test`                                     |
| [`pr-title.yml`](.github/workflows/pr-title.yml)                                   | PR タイトルが Conventional Commits 形式に沿い、説明を日本語で書いているか。規約は [CONTRIBUTING.md](CONTRIBUTING.md#タイトルとコミットメッセージ)                                                                                                                                                                                                                                                                              | `pr-title`                                 |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml)                             | 依存関係の脆弱性とマルウェア。詳しくは [脆弱性とマルウェアの検査](#脆弱性とマルウェアの検査)                                                                                                                                                                                                                                                                                                                                   | `osv-scanner / osv-scan`（PR の検査だけ）  |
| [`betterleaks.yml`](.github/workflows/betterleaks.yml)                             | コミットに含まれるシークレット。詳しくは [シークレットの検査](#シークレットの検査)                                                                                                                                                                                                                                                                                                                                             | `betterleaks`                              |
| [`editorconfig.yml`](.github/workflows/editorconfig.yml)                           | git で管理するファイルが [`.editorconfig`](.editorconfig) の文字コード・改行・インデント・末尾の空白に沿っているか。[editorconfig-checker](https://github.com/editorconfig-checker/editorconfig-checker) で検査する                                                                                                                                                                                                            | `editorconfig`                             |
| [`actionlint.yml`](.github/workflows/actionlint.yml)                               | GitHub Actions のワークフローのキー・式・`run:` のスクリプト。[actionlint](https://github.com/rhysd/actionlint) で検査し、`run:` のスクリプトは actionlint から ShellCheck にかける。設定は [`.github/actionlint.yaml`](.github/actionlint.yaml) にある                                                                                                                                                                        | `actionlint`                               |
| [`renovate-config-validator.yml`](.github/workflows/renovate-config-validator.yml) | [`.github/renovate.json5`](.github/renovate.json5) の構文と、オプションの名前・値。Renovate の [renovate-config-validator](https://docs.renovatebot.com/config-validation/) で検査する                                                                                                                                                                                                                                         | `renovate-config-validator`                |
| [`zizmor.yml`](.github/workflows/zizmor.yml)                                       | GitHub Actions のワークフローのセキュリティ上の問題。テンプレートインジェクション・広すぎる権限・checkout の資格情報の残留・フォークにしかないコミットへの固定などを、[zizmor](https://github.com/zizmorcore/zizmor) で検査する                                                                                                                                                                                                | `zizmor`                                   |
| [`ghalint.yml`](.github/workflows/ghalint.yml)                                     | GitHub Actions のワークフローが、すべてのジョブに `timeout-minutes` を書いているか、シークレットを必要なステップだけに渡しているかなど。[ghalint](https://github.com/suzuki-shunsuke/ghalint) で検査する                                                                                                                                                                                                                       | `ghalint`                                  |
| [`lychee.yml`](.github/workflows/lychee.yml)                                       | リポジトリのすべてのファイルに書いたリンクが切れていないか。[lychee](https://github.com/lycheeverse/lychee) で検査する。PR と `main` への push ではリポジトリ内のリンクだけ、毎週の実行では外部のリンクも検査する                                                                                                                                                                                                              | `lychee`（リポジトリ内のリンクの検査だけ） |
| [`typos.yml`](.github/workflows/typos.yml)                                         | リポジトリのすべてのファイルの英単語の綴り。[typos](https://github.com/crate-ci/typos) で検査する。設定は [`.github/typos.toml`](.github/typos.toml) にある                                                                                                                                                                                                                                                                    | `typos`                                    |
| [`markdownlint.yml`](.github/workflows/markdownlint.yml)                           | すべての `.md` の書式。見出しのレベル・リストの記号・表の列数・空行・コードブロックの言語の指定など。[markdownlint](https://github.com/DavidAnson/markdownlint) で検査する。設定は [`.github/markdownlint-cli2.jsonc`](.github/markdownlint-cli2.jsonc) にある                                                                                                                                                                 | `markdownlint`                             |
| [`yamllint.yml`](.github/workflows/yamllint.yml)                                   | `.yml`・`.yaml` の構文と書式。キーの重複・インデント・コメントの書き方など。[yamllint](https://github.com/adrienverge/yamllint) で検査する。設定は [`.github/yamllint/.yamllint.yaml`](.github/yamllint/.yamllint.yaml) にある                                                                                                                                                                                                 | `yamllint`                                 |
| [`hadolint.yml`](.github/workflows/hadolint.yml)                                   | Dockerfile の書き方。ベースイメージのタグの指定・`apt-get install` の版の固定など。[hadolint](https://github.com/hadolint/hadolint) で検査し、`RUN` のスクリプトは hadolint に組み込まれた ShellCheck にかける。設定は [`.github/hadolint.yaml`](.github/hadolint.yaml) にある                                                                                                                                                 | `hadolint`                                 |
| [`devcontainer.yml`](.github/workflows/devcontainer.yml)                           | [開発環境](#開発環境) の 2 つのイメージを、[`compose.yaml`](compose.yaml) のとおりにビルドできるか。golang では gopls・gofumpt・staticcheck が、node では pnpm が起動するかも確認する。詳しくは [devcontainer](#devcontainer)                                                                                                                                                                                                  | `devcontainer`                             |
| [`golang-check.yml`](.github/workflows/golang-check.yml)                           | [`golang`](golang) の Go のコード。golang の Dev Container と同じイメージのなかで、ビルド・`go vet`・gofumpt の整形・[staticcheck](https://staticcheck.dev/)・`go test` を順に検査する。staticcheck の設定は [`golang/staticcheck.conf`](golang/staticcheck.conf) にある。詳しくは [golang-check](#golang-check)                                                                                                               | `golang-check`                             |
| [`node-check.yml`](.github/workflows/node-check.yml)                               | [`node`](node) のコード。node の Dev Container と同じイメージのなかで、TypeScript の型・[oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) の整形・[oxlint](https://oxc.rs/docs/guide/usage/linter.html) の規則を順に検査する。設定は [`node/tsconfig.json`](node/tsconfig.json)・[`node/.oxfmtrc.jsonc`](node/.oxfmtrc.jsonc)・[`node/.oxlintrc.jsonc`](node/.oxlintrc.jsonc) にある。詳しくは [node-check](#node-check) | `node-check`                               |
| [`oxfmt.yml`](.github/workflows/oxfmt.yml)                                         | [`node`](node) の外の JSON・YAML・TOML・Markdown などが、[oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) の整形に沿っているか。設定は [`.oxfmtrc.jsonc`](.oxfmtrc.jsonc) にある。詳しくは [oxfmt](#oxfmt)                                                                                                                                                                                                              | `oxfmt`                                    |
| [`settings-drift.yml`](.github/workflows/settings-drift.yml)                       | GitHub のルールセット・リポジトリ・セキュリティ・Actions・ラベルの設定が、[`.github/settings`](.github/settings) の定義と一致しているか。詳しくは [定義とのずれの検査](#定義とのずれの検査)                                                                                                                                                                                                                                    | なし                                       |

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

| チェック                    | 検査する範囲                                                                                                                                                                                                                                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `textlint`・`markdownlint`  | リポジトリのすべての `.md`                                                                                                                                                                                                                                                                                        |
| `test`                      | リポジトリ全体の `.sh`・`.bats`。`.git` は除く                                                                                                                                                                                                                                                                    |
| `editorconfig`              | リポジトリ全体。`pnpm-lock.yaml` など、editorconfig-checker がデフォルトで除外するファイルは除く（[Default Excludes](https://github.com/editorconfig-checker/editorconfig-checker/blob/v4.0.2/README.md#default-excludes)）                                                                                       |
| `actionlint`                | すべてのワークフロー                                                                                                                                                                                                                                                                                              |
| `zizmor`                    | すべてのワークフローと、リポジトリ内のアクション（`action.yml`）                                                                                                                                                                                                                                                  |
| `ghalint`                   | すべてのワークフローと、リポジトリのルートから 3 階層までのディレクトリにあるアクション（`action.yml`）                                                                                                                                                                                                           |
| `renovate-config-validator` | [`.github/renovate.json5`](.github/renovate.json5)                                                                                                                                                                                                                                                                |
| `lychee`                    | リポジトリ全体。`.git` と、`.github/mise.lock`・`.github/yamllint/uv.lock` は除く                                                                                                                                                                                                                                 |
| `typos`                     | リポジトリ全体。`.git` と、`typos.toml`・`pyproject.toml` など typos の設定ファイルと同じ名前のファイルは除く                                                                                                                                                                                                     |
| `yamllint`                  | リポジトリ全体の `.yml`・`.yaml`。`pnpm-lock.yaml` と、`.venv`・`node_modules` の下は除く                                                                                                                                                                                                                         |
| `hadolint`                  | リポジトリ全体のうち、名前が `Dockerfile`・`Containerfile` のファイル。`Dockerfile.*`・`*.Dockerfile`・`Containerfile.*`・`*.Containerfile` に一致するファイルも含む。`.git` は除く                                                                                                                               |
| `devcontainer`              | [`compose.yaml`](compose.yaml) の `node`・`golang` のサービスのイメージ。ランナーと同じ arm64 のイメージだけをビルドする                                                                                                                                                                                          |
| `golang-check`              | [`golang`](golang) のモジュールのすべてのパッケージ（`./...`）。gofumpt は、その下のすべての `.go`（`vendor`・`testdata` は除く）                                                                                                                                                                                 |
| `node-check`                | [`node`](node) の下のファイル。`.gitignore` に一致するファイルは除く。tsc は、[`node/tsconfig.json`](node/tsconfig.json) の `include` に一致するファイルで、`node_modules` の下を除く。oxfmt は、対応する形式のうち `.md`・`.yml`・`.yaml` とロックファイルを除く。oxlint は、JavaScript と TypeScript のファイル |
| `oxfmt`                     | リポジトリ全体のうち、oxfmt が対応する形式のファイル。[`node`](node) の下・`.gitignore` に一致するファイル・ロックファイルは除く                                                                                                                                                                                  |

- 必須チェックのワークフローは `on.pull_request.paths` で絞らない。絞ると、実行されなかった PR の必須チェックが Pending のまま残り、マージできない（[Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)）
- 範囲の決め方と除く理由は、各ワークフローと、[`.yamllint.yaml`](.github/yamllint/.yamllint.yaml)・[`.github/lychee.toml`](.github/lychee.toml)・[`.github/typos.toml`](.github/typos.toml) のコメントに書いている
- typos は、`typos.toml`・`Cargo.toml`・`pyproject.toml` など設定ファイルと同じ名前のファイルを、渡し方によらず読まない（[`file.rs`](https://github.com/crate-ci/typos/blob/v1.51.1/crates/typos-cli/src/file.rs#L942-L951)）。そのため、[`.github/typos.toml`](.github/typos.toml) と [`.github/yamllint/pyproject.toml`](.github/yamllint/pyproject.toml) は検査しない

### ツールごとの補足

#### 失敗する条件

次のツールは、軽い指摘でも失敗するように実行しています。

| ツール                    | 失敗する条件                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| renovate-config-validator | `--strict` を付け、エラーと警告に加えて、設定の移行が必要なだけのときも失敗する（[renovate-config-validator の実装](https://github.com/renovatebot/renovate/blob/44.151.1/lib/config-validator.ts#L101-L120)）                                                                                                                                                                                                                                              |
| zizmor                    | 指摘が 1 件でもあると失敗する。`--strict-collection` を付け、入力のファイルを解析できないときも失敗する（[Input collection](https://docs.zizmor.sh/usage/#input-collection)）。`--persona=pedantic` を付け、すぐには攻撃に使えないコードの臭いも指摘させる（[Using personas](https://docs.zizmor.sh/usage/#using-personas)）。PR の注釈は最初の 10 件までで、残りはジョブのログにだけ出る（[Output formats](https://docs.zizmor.sh/usage/#output-formats)） |
| ShellCheck                | `--enable=all` を付け、デフォルトでは無効の任意のチェックもすべて有効にする（[shellcheck.1.md](https://github.com/koalaman/shellcheck/blob/v0.11.0/shellcheck.1.md)）                                                                                                                                                                                                                                                                                       |
| shfmt                     | [`.editorconfig`](.editorconfig) の `simplify = true` で、もっと簡単に書けるコードも差分として出す                                                                                                                                                                                                                                                                                                                                                          |
| yamllint                  | `--strict` を付け、warning の指摘でも失敗する（[Errors and warnings](https://yamllint.readthedocs.io/en/stable/configuration.html#errors-and-warnings)）                                                                                                                                                                                                                                                                                                    |
| hadolint                  | [`.github/hadolint.yaml`](.github/hadolint.yaml) の `failure-threshold: style` で、重大度が style の指摘でも失敗する。`label-schema` のラベルがないときと、`strict-labels` でそれ以外のラベルがあるときも失敗する（[Linting Labels](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#linting-labels)）                                                                                                                                           |
| staticcheck               | [`golang/staticcheck.conf`](golang/staticcheck.conf) の `checks = ["all"]` で、デフォルトでは無効のスタイルの検査もすべて有効にする（[Configuration](https://staticcheck.dev/docs/configuration/)）                                                                                                                                                                                                                                                         |
| oxlint                    | [`node/.oxlintrc.jsonc`](node/.oxlintrc.jsonc) で、開発中の `nursery` を除くすべてのカテゴリの規則をエラーにする。Tailwind CSS のクラスの規則も、行の折り返しを除いてすべてエラーにする。warning と、使われていない無効化のコメントでも失敗する（[`options`](https://oxc.rs/docs/guide/usage/linter/config-file-reference.html#options)）                                                                                                                   |

#### 指摘を無視する方法

| ツール       | 無視する方法                                                                                                                                                                                                                                              |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| zizmor       | YAML の該当する行に `# zizmor: ignore[<監査名>]` と書く（[Ignoring results](https://docs.zizmor.sh/usage/#ignoring-results)）                                                                                                                             |
| typos        | 誤検知は、[`.github/typos.toml`](.github/typos.toml) の `extend-ignore-re` に、その箇所だけに一致する正規表現を足して除外する（[`default.extend-ignore-re`](https://github.com/crate-ci/typos/blob/v1.51.1/docs/reference.md#defaultextend-ignore-re)）   |
| markdownlint | 該当する行の前に `<!-- markdownlint-disable-next-line <ルール名> -->` と書く（[Configuration](https://github.com/DavidAnson/markdownlint/blob/v0.41.1/README.md#configuration)）                                                                          |
| yamllint     | 該当する行に `# yamllint disable-line rule:<ルール名>` と書く（[Disable with comments](https://yamllint.readthedocs.io/en/stable/disable_with_comments.html#disabling-checks-for-a-specific-line)）                                                       |
| hadolint     | 該当する命令の前の行に `# hadolint ignore=<ルール名>` と書く（[Inline ignores](https://github.com/hadolint/hadolint/blob/v2.15.1/README.md#inline-ignores)）                                                                                              |
| staticcheck  | 該当する行の前に `//lint:ignore <チェック名> <理由>` と書く。理由は省略できない（[Ignoring problems with linter directives](https://staticcheck.dev/docs/configuration/#ignoring-problems)）                                                              |
| oxlint       | 該当する行の前に `// oxlint-disable-next-line <規則名>` と書く（[Inline suppressions](https://oxc.rs/docs/guide/usage/linter/ignore-comments.html)）                                                                                                      |
| oxfmt        | 整形させない文の前に `// oxfmt-ignore` と書く。JSX のなかでは `{/* oxfmt-ignore */}` と書く。JavaScript と TypeScript のほかのファイルでは、`prettier-ignore` を使う（[Ignore comments](https://oxc.rs/docs/guide/usage/formatter/ignore-comments.html)） |
| Betterleaks  | その行のコメントに `betterleaks:allow` と書く。書けないときは、[シークレットの検査](#シークレットの検査) のとおり `.betterleaksignore` を使う                                                                                                             |

#### actionlint

- ランナーのラベル `ubuntu-26.04-arm` を、[`actionlint.yaml`](.github/actionlint.yaml) でセルフホストのランナーのラベルとして認めている。理由は、そのファイルのコメントに書いている

#### renovate-config-validator

- [`renovate.yml`](.github/workflows/renovate.yml) で動かす Renovate と同じ版の Docker イメージを、ジョブのコンテナにして使う

#### zizmor

- `GITHUB_TOKEN` を渡し、GitHub API で調べる監査も動かす（[Operating modes](https://docs.zizmor.sh/usage/#operating-modes)）。対象は `impostor-commit`・`known-vulnerable-actions`・`ref-confusion` の 3 つ
- `--persona=pedantic` の指摘に合わせて、ワークフローを次のように書く（[Audit Rules](https://docs.zizmor.sh/audits/)）
  - すべてのジョブに `name` を書く（`anonymous-definition`）。`name` は必須チェックの名前になるので、ジョブ ID と同じにする。変えるときは [`rulesets/main.json`](.github/settings/rulesets/main.json) の `context` も合わせる
  - `concurrency` を書く（`concurrency-limits`）。同じ PR に push し直したら、古い実行を取り消す。PR 以外は実行ごとにグループを分け、`main` への push や定期実行は取り消さない。同時に動くと困るワークフローは、ワークフロー単位のグループにして実行を重ねない
  - `contents: read` 以外の `permissions` には、行末のコメントで理由を書く（`undocumented-permissions`）

#### ghalint

zizmor の監査にない次のポリシーのために使います（[Policies](https://github.com/suzuki-shunsuke/ghalint/blob/v1.5.6/README.md#policies)・[zizmor の監査の一覧](https://docs.zizmor.sh/audits/)）。

- `job_timeout_minutes_is_required` は、すべてのジョブに `timeout-minutes` を求める
- `workflow_secrets`・`job_secrets` は、シークレットをワークフロー・ジョブの `env` に置かせない

#### lychee

- ネットワークを使わず（`--offline`）、リポジトリ内のファイルへのリンクと見出しのアンカーだけを確認する
- Markdown と HTML 以外のファイルからは URL だけを拾い、コメントに書いた相対パスは検査しない

#### markdownlint

- [markdownlint-cli2-action](https://github.com/DavidAnson/markdownlint-cli2-action) に同梱された markdownlint-cli2 で検査する。npm から依存関係を取得しないので、`package.json` とロックファイルはない。markdownlint-cli2 の版は、アクションの版で決まる
- 行の長さと 1 行目の見出しのルールだけを無効にしている。editorconfig や lychee の検査と重なるルールも有効のままにしている

#### textlint

- pnpm の版は、[`.github/textlint/package.json`](.github/textlint/package.json) の `devEngines.packageManager` だけで管理し、Renovate が更新する（[#26](https://github.com/kentayamada-dev/playground/pull/26)）。CI の pnpm/action-setup も、Renovate がロックファイルを更新するときも、この版を使う（[Renovate の実装](https://github.com/renovatebot/renovate/blob/44.151.1/lib/modules/manager/npm/post-update/pnpm.ts#L55-L65)）

#### oxfmt

- [`node`](node) の外の、oxfmt が対応する形式（JSON・JSONC・JSON5・YAML・TOML・Markdown など）の整形を検査する。`node` の下は [node-check](#node-check) が検査する
- ほかのリンターと規則がぶつかるときは、oxfmt の整形に合わせて、リンターの設定を変える
- 手元では、`.github/oxfmt` に `pnpm install` で依存関係を入れ、リポジトリのルートから `.github/oxfmt/node_modules/.bin/oxfmt -c .oxfmtrc.jsonc` を実行すると整形し直す。`--check` を付けると、CI と同じ検査になる
- `-c` で設定を渡す理由は、[`oxfmt.yml`](.github/workflows/oxfmt.yml) のコメントに書いている
- pnpm の版は、[`.github/oxfmt/package.json`](.github/oxfmt/package.json) の `devEngines.packageManager` で管理し、Renovate が更新する。[`pnpm-workspace.yaml`](.github/oxfmt/pnpm-workspace.yaml) は、textlint のものとそろえている
- Renovate は、`oxfmt` の minor・patch を自動マージする。整形の結果が変わる更新を入れないため、必須チェックにしている
- 依存関係は、Takumi Guard のレジストリから取得する。接続できないと、どの PR もマージできない

#### bats

- `LC_ALL=C` を付けて実行する。手元で実行するときも付ける。理由は [`test.yml`](.github/workflows/test.yml) のコメントに書いている

#### yamllint

- デフォルトの設定から、次の 4 つを変えている。理由は [`.yamllint.yaml`](.github/yamllint/.yamllint.yaml) のコメントに書いている
  - 行の長さ（`line-length`）と、ファイルの先頭の `---`（`document-start`）を検査しない
  - 真偽値の書き方（`truthy`）は、値だけを検査し、キーは検査しない
  - 行末のコメントの前の空白（`comments`）は、1 つでよい
- yamllint の入れ方は [yamllint の依存関係](#yamllint-の依存関係) にある

#### hadolint

- 対象のファイルが 1 つもなければ、hadolint を実行せずに成功する
- `RUN` のスクリプトは、hadolint にライブラリとして組み込まれた ShellCheck で検査する。mise で入れる ShellCheck は使わない（[`hadolint.cabal`](https://github.com/hadolint/hadolint/blob/v2.15.1/hadolint.cabal#L169)）
- 設定は [`.github/hadolint.yaml`](.github/hadolint.yaml) に書き、`--config` で渡す。検査の前に、style の指摘だけが出る Dockerfile を標準入力から渡し、設定が効いて失敗することを確認する
- Dockerfile のラベルは、`.github/hadolint.yaml` の `label-schema` に挙げた 4 つだけを書く。値は変数で渡さず、各 Dockerfile に直接書く
- 理由は、[`hadolint.yml`](.github/workflows/hadolint.yml) と `.github/hadolint.yaml` のコメントに書いている

#### devcontainer

- Renovate は、ベースイメージ・pnpm・gopls・gofumpt・staticcheck の minor・patch・digest の更新を自動マージする。組み合わせによってはビルドが壊れるため、必須チェックにしている
- ビルドのキャッシュは使わず、毎回すべての層をビルドする
- ビルドでは、Docker Hub・Takumi Guard のレジストリ・Go のモジュールプロキシから取得する。どれかに接続できないと、どの PR もマージできない

#### golang-check

- 手元では、golang のコンテナで CI と同じ検査ができる。実行のしかたは [`golang/Makefile`](golang/Makefile) にある
- 検査は順に実行し、失敗したところで止まる。後の検査は実行しない
- staticcheck は、エディタの gopls と同じく、すべての検査を有効にしている
- `go test` は、テストのファイルがないパッケージを `[no test files]` と出して成功として扱う
- ビルドは、VCS の情報を埋め込まず、実行ファイルを一時ディレクトリに書いて捨てる。手元の `make build` とは出力が違う
- Renovate は、golang のベースイメージと gofumpt・staticcheck の minor・patch・digest の更新を自動マージする。コードが検査に通らなくなる更新を入れないため、必須チェックにしている
- イメージのビルドとツールチェーン・モジュールの取得では、Docker Hub と Go のモジュールプロキシから取得する。どちらかに接続できないと、どの PR もマージできない
- Dev Container と同じイメージで検査する理由と、ビルドと gofumpt に付けるオプションの理由は、[`golang-check.yml`](.github/workflows/golang-check.yml) のコメントに書いている

#### node-check

- 手元では、node のコンテナで `pnpm typecheck`・`pnpm fmt:check`・`pnpm lint` を実行すると、CI と同じ検査ができる。`pnpm fmt` を実行すると整形し直す
- 検査は順に実行し、失敗したところで止まる。後の検査は実行しない
- `pnpm typecheck` は、Next.js が生成するルートの型（`.next/types`）を作ってから検査する。`tsc` だけでは、その型がないときに `LayoutProps` などが見つからずに失敗する
- `pnpm lint` は、`pnpm typecheck` と同じく、Next.js が生成するルートの型を作ってから検査する。その型がないと、型情報を使う規則が `LayoutProps` などを解決できず、誤った指摘を出す
- oxfmt のインデントや改行の設定は、リポジトリのルートの [`.editorconfig`](.editorconfig) から読む
- oxlint は、型情報を使う規則も動かす。型情報は `oxlint-tsgolint` が [`node/tsconfig.json`](node/tsconfig.json) から作る
- oxlint は、Tailwind CSS のクラスも [eslint-plugin-better-tailwindcss](https://github.com/schoero/eslint-plugin-better-tailwindcss) の規則で検査する
  - ESLint のプラグインを、oxlint の JS プラグインとして動かす。JS プラグインは、まだ alpha の機能（[JS Plugins](https://oxc.rs/docs/guide/usage/linter/js-plugins.html)）
  - クラスの正規の形は Tailwind CSS 本体が決める。そのため `tailwindcss` を更新すると、指摘の内容も変わりうる
- 外した規則と、デフォルトのオプションを変えた規則の理由は、[`node/.oxlintrc.jsonc`](node/.oxlintrc.jsonc) のコメントに書いている
- node の Dev Container には Oxc の VS Code 拡張機能を入れ、保存すると oxfmt で整形する設定にしている
- Renovate は、`next`・`typescript`・`@types/*` などの minor・patch の更新も自動マージする。型が合わなくなる更新を入れないため、必須チェックにしている
- Renovate は、`oxlint`・`oxfmt`・`oxlint-tsgolint`・`eslint-plugin-better-tailwindcss` の minor・patch も自動マージする。指摘や整形の結果が変わる更新を入れないため、必須チェックにしている
- イメージのビルドと依存関係の取得では、Docker Hub・Takumi Guard のレジストリから取得する。どちらかに接続できないと、どの PR もマージできない
- Dev Container と同じイメージで検査する理由は、[`node-check.yml`](.github/workflows/node-check.yml) のコメントに書いている

### 外部リンクの定期検査

外部のリンクは、[`lychee.yml`](.github/workflows/lychee.yml) の `lychee-external` が毎週月曜と手動の実行（`workflow_dispatch`）で検査します。必須チェックではありません。

- `429`・`502`・`503`・`504` は成功として扱う
- `mise.lock` と `uv.lock` の URL は、[`.github/lychee.toml`](.github/lychee.toml) で検査から除く
- node と golang のサーバーのアドレス（`http://localhost:3000` など）も、`.github/lychee.toml` で検査から除く
- 理由は、[`lychee.yml`](.github/workflows/lychee.yml) と `.github/lychee.toml` のコメントに書いている
- HTTPS で開けるリンクを `http://` で書いていると、失敗する（`require_https`、[lychee.example.toml](https://github.com/lycheeverse/lychee/blob/lychee-v0.24.2/lychee.example.toml#L98-L99)）。PR の検査は `--offline` でネットワークを使わないため、この検査は効かない
- 通らないリンクがあると、[`report-scheduled-check.sh`](.github/scripts/report-scheduled-check/report-scheduled-check.sh) が issue「docs: 外部リンクの定期検査で見つかったリンク切れを直す」を作る。開いていれば、本文を最新の結果に書き換える
- すべてのリンクが通ると、開いている issue に実行の URL をコメントして閉じる
- リンクを直したら、次の検査を待つか、手動で実行して issue を閉じる

### CodeQL

ワークフローのほかに、CodeQL のデフォルトセットアップが GitHub Actions のワークフローを解析します。

- エラー・警告のアラートか、medium 以上の重大度のセキュリティアラートがあると、ルールセットの `code_scanning` ルールでマージできない
- 解析は、`main` への push、`main` に向けた PR の作成と push、週 1 回の定期実行で動く。フォークからの PR は解析しない（[デフォルトセットアップ](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types)）

## リポジトリの設定

GitHub の設定は [`.github/settings`](.github/settings) に JSON で定義し、次のコマンドで反映します。何度実行しても同じ状態になります。`gh` と `jq` が必要です。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh
```

| 定義                                                  | 対象                                                              | 反映のしかた                                                                   |
| ----------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [`rulesets`](.github/settings/rulesets)               | ルールセット                                                      | `name` が同じルールセットを更新し、なければ作成する。定義にないものは削除する  |
| [`repository.json`](.github/settings/repository.json) | マージの方法・Wiki の有無・シークレットスキャン・プッシュ保護など | 定義に書いた項目だけを更新する                                                 |
| [`security.json`](.github/settings/security.json)     | Dependabot・CodeQL など                                           | 定義に書いた項目だけを、`true` なら有効に、`false` なら無効にする              |
| [`actions.json`](.github/settings/actions.json)       | GitHub Actions                                                    | 定義に書いた項目だけを更新する                                                 |
| [`labels.json`](.github/settings/labels.json)         | issue と PR のラベル                                              | 名前が同じラベルの色と説明を更新し、なければ作成する。定義にないものは削除する |

- 定義にないルールセットとラベルは、GitHub の画面で作ったものも削除される。消したラベルは issue や PR からも外れる。Organization のルールセットは対象外
- シークレットスキャンとプッシュ保護は、リポジトリの設定と同じ API で変えるため、`repository.json` の `security_and_analysis` に書く
- CodeQL のデフォルトセットアップも毎回送る。設定が変わらなければ、新しい解析は始まらない（[#190](https://github.com/kentayamada-dev/playground/pull/190) で確認）
- 環境変数 `GH_REPO` は使わない。どのディレクトリから実行しても、スクリプトはリポジトリのルートに移り、git の remote から反映先を決める

### 実行に必要な権限

`gh` は `gh auth login` でログインしておきます。実行するアカウントとトークンには、次の権限が必要です。

| 必要な権限                 | 理由                                                                                                                                                                                                                                                                                                                                                |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| リポジトリの管理者権限     | 脆弱性アラートやプライベートな脆弱性報告などを切り替える API が求めるため（[リポジトリの REST API](https://docs.github.com/en/rest/repos/repos)）                                                                                                                                                                                                   |
| トークンの `repo` スコープ | Actions や CodeQL の設定を変える API が求めるため（[Actions の権限の API](https://docs.github.com/en/rest/actions/permissions)・[CodeQL の API](https://docs.github.com/en/rest/code-scanning/code-scanning)）。`gh auth login` で発行されるトークンには含まれる（[gh の実装](https://github.com/cli/cli/blob/v2.102.0/internal/authflow/flow.go)） |

- 環境変数 `GH_TOKEN` か `GITHUB_TOKEN` があると、`gh` はログインしたトークンより優先してそちらを使う（`gh help environment`）。権限の足りないトークンが入っていると、途中で失敗する

### 定義とのずれの検査

`--check` を付けると、GitHub を変えずに、反映すると変わる箇所を定義とのずれとして示します。ずれがあれば、終了コード 1 で終わります。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh --check
```

- ルールセットは、GitHub が付ける `id`・`node_id`・`created_at` などを除き、定義と完全に一致するかを比べる
- ほかの設定は、定義に書いた項目だけを比べる。定義に書いた項目が GitHub の応答になければ、ずれとして示す
- 配列は並び順を無視して比べる

[`settings-drift.yml`](.github/workflows/settings-drift.yml) が毎日これを実行し、ずれがあるか検査に失敗すると issue を作ります。開いている issue があれば、新しく作らずに本文を最新の結果に書き換えます。ずれは、定義を直すか、同期のコマンドで GitHub を定義に揃えて直します。直したあとの検査が通ると、開いている issue に実行の URL をコメントして閉じます。

- 定義を変えた PR をマージしたら、同期のコマンドを実行する。実行し忘れると、次の検査で issue になる

#### 検査に使うトークン

GitHub の設定は、リポジトリの secret `SETTINGS_READ_TOKEN` に登録した Fine-grained personal access token で読みます。`GITHUB_TOKEN` を使わない理由は、[`settings-drift.yml`](.github/workflows/settings-drift.yml) のコメントに書いています。issue の操作には、ワークフローの `GITHUB_TOKEN` を使います。

トークンは [トークンの作り方](#トークンの作り方) のとおりに作り、Repository permissions を次の表のとおりに設定します。

| Permission     | Access         | 用途                                                                                                                                                                                                 |
| -------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Administration | Read-only      | Actions の権限・脆弱性アラート・セキュリティアップデート・リリースの不変化・CodeQL のデフォルトセットアップの取得                                                                                    |
| Contents       | Read and write | マージの方法・自動マージ・マージ後のブランチの削除など、マージ関連の設定の取得。読むだけでも書き込みの権限が要る（[Get a repository](https://docs.github.com/en/rest/repos/repos#get-a-repository)） |
| Issues         | Read-only      | ラベルの取得                                                                                                                                                                                         |
| Metadata       | Read-only      | 自動で付く（必須）。ルールセット・リポジトリの設定・脆弱性の非公開報告の取得                                                                                                                         |

権限の一覧は [Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) に従っています。作成したトークンは、次のコマンドで secret に登録します。

```bash
gh secret set SETTINGS_READ_TOKEN --repo kentayamada-dev/playground
```

- Contents の書き込みの権限があるため、このトークンではブランチやタグを push できる
- ルールセットの `bypass_actors` は、Administration が Read-only のこのトークンでも返る。ドキュメントには、ルールセットへの書き込み権限がなければ返さないとある（[Get a repository ruleset](https://docs.github.com/en/rest/repos/rules#get-a-repository-ruleset)）

### GitHub Actions の設定

| 項目                   | 設定                                                                                                                                                                                            |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 実行できるアクション   | GitHub 公式・検証済み作成者のアクションと、`patterns_allowed` に書いたアクション・再利用ワークフローだけ。ほかの作成者のアクションや、再利用ワークフローを使うときは、`patterns_allowed` に足す |
| アクションのバージョン | 完全なコミット SHA で固定する                                                                                                                                                                   |
| フォークからの PR      | 外部の貢献者の PR のワークフローは、毎回承認してから動く                                                                                                                                        |
| `GITHUB_TOKEN` の権限  | `permissions` を書かないワークフローでは読み取りだけ。ワークフローから PR を承認できない                                                                                                        |

## 脆弱性とマルウェアの検査

依存関係に既知の脆弱性やマルウェアがないかを、[OSV-Scanner](https://google.github.io/osv-scanner/) と Dependabot で検査しています。結果はどれも Security タブに出ます。

| 仕組み                                                                       | 実行のタイミング                                               | 結果                                                                                              |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) の `osv-scanner`      | PR ごと                                                        | PR のベースと比べて新しく入ったものがあると失敗する。必須チェックなので、失敗するとマージできない |
| [`osv-scanner.yml`](.github/workflows/osv-scanner.yml) の `osv-scanner-full` | `main` への push と毎日                                        | 見つかったものを Code scanning に出し、1 件でもあれば失敗する                                     |
| Dependabot アラート                                                          | アドバイザリが公開されたときと、依存関係を変えて push したとき | 脆弱性を Dependabot のアラートに出す                                                              |

- 間接的な依存関係を検査しているのは OSV-Scanner だけ。GitHub の依存関係グラフは、どちらのロックファイルからも間接的な依存関係を読まないため
  - 依存関係グラフは、`pnpm-lock.yaml` の 1 つ目の文書しか読まない（文書の順番を入れ替えて確認した）
  - pnpm は、1 つ目の文書に pnpm 本体の版を書く。依存関係があるのは 2 つ目の文書（[Reading pnpm-lock.yaml](https://pnpm.io/lockfile)）
  - yamllint の `uv.lock` は、依存関係グラフが読むファイルの一覧にない（[Dependency graph supported package ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems)）
- Dependabot のマルウェアアラートは有効にしていない。Dependabot が読むパッケージは、すべて OSV-Scanner でも検査しているため
- Actions のアクションは SHA で固定しているため、Dependabot のアラートは出ない（[Dependabot alerts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)）。OSV-Scanner もデフォルトでは Actions を検査しない
- Go の標準ライブラリは、OSV-Scanner では検査しない。OSV-Scanner は go.mod の Go の版を読み取るが、デフォルトでは検査に使わない（[Scan Go Mod Version](https://google.github.io/osv-scanner/configuration/#scan-go-mod-version)）。代わりに Renovate が、[`golang/go.mod`](golang/go.mod) の `toolchain` の版で脆弱性を照会し、修正版への PR を作る
- 見つかった脆弱性は、依存関係の種類ごとに次のように直す
  - 直接の依存関係は、Renovate が修正版への PR を作る（[Renovate](#renovate)）
  - pnpm のロックファイルにある間接的な依存関係には、Renovate は PR を作らない。毎週のロックファイルの更新で上がる（例: `fast-uri` は [#305](https://github.com/kentayamada-dev/playground/pull/305) で上がった）
  - 毎週の更新を待たずに直すときは、Dependency Dashboard の issue の「Awaiting Schedule」で、ロックファイルの更新を選ぶ。次の Renovate の実行で PR が作られる（[`dependency-dashboard.ts`](https://github.com/renovatebot/renovate/blob/44.151.1/lib/workers/repository/dependency-dashboard.ts#L515-L524)）
  - Dev Container の Go のツールの依存関係は、依存関係だけを上げず、ツールの新しい版で上げる。理由は、golang の Dockerfile のコメントに書いている
- 次の脆弱性は、ロックファイルと同じディレクトリの `osv-scanner.toml` に、理由と期限（`ignoreUntil`）を付けて除外する。設定はそのディレクトリのロックファイルにだけ効く（[Configuration](https://google.github.io/osv-scanner/configuration/)）
  - 修正版がなく、影響もない脆弱性（例: [`.github/textlint/osv-scanner.toml`](.github/textlint/osv-scanner.toml)）
  - 修正版はあるが、すぐには取り込めない脆弱性。依存元が修正版を使う版を出すのを待つときや、公開後 14 日の待機が明けるのを待つときなど。期限は取り込める見込みの日にし、理由に何を待っているかを書く
- 期限を過ぎると除外は切れ、また検出される（[`config.go`](https://github.com/google/osv-scanner/blob/v2.6.0/internal/config/config.go#L149-L157)）。除外が要らなくなると、OSV-Scanner のログに `has unused ignores` と出る（CI のログで確認した）

## シークレットの検査

トークンやパスワードなどのシークレットがコミットに含まれていないかを、[Betterleaks](https://github.com/betterleaks/betterleaks) で検査しています。

[`betterleaks.yml`](.github/workflows/betterleaks.yml) は、PR ごとと `main` への push で、`HEAD` からたどれる git 履歴全体を走査します。1 件でも見つかると失敗します。必須チェックなので、失敗するとマージできません。

- 見つかった値を実行ログに出さない（`--redact`）
- プロバイダーの API に問い合わせて、見つかったシークレットが有効かどうかは確認しない（`--validation` を付けていない）
- 誤検知の除外のしかたは、[指摘を無視する方法](#指摘を無視する方法) の表にまとめている
- 行にコメントを書けないときは、ルートの `.betterleaksignore` に fingerprint を 1 行ずつ書いて除外する。fingerprint の形式は `<コミット>:<パス>:<ルール ID>:<行番号>` で、`--report-format json` のレポートでは `Fingerprint` に出る

## 使うツール

CI のツールは、[mise](https://mise.jdx.dev/) で入れています。対象は、[ダウンロードするファイルの検証](#ダウンロードするファイルの検証) の表に並べたツールです。[`.github/mise.toml`](.github/mise.toml) で版を、[`.github/mise.lock`](.github/mise.lock) でダウンロードするファイルの sha256 を固定し、どちらも Renovate が更新します。手元では使わないので、ルートではなく `.github` に置き、[`setup-mise`](.github/actions/setup-mise/action.yml) が mise-action の `working_directory` で読ませています。

### `mise.lock` の更新

- `mise.lock` には、CI の linux-arm64 だけを記録している。`mise lock` は `--platform` を付けないと `mise.lock` にあるプラットフォームだけを対象にするので、手元で実行しても macOS などの記録は増えない（[`mise lock`](https://mise.jdx.dev/cli/lock.html)）

### ダウンロードするファイルの検証

署名は、`mise lock` で `mise.lock` を更新するときに検証します。CI のインストールでは検証し直さず、`mise.lock` の sha256 と照合します（[`locked_verify_provenance`](https://mise.jdx.dev/configuration/settings.html#locked_verify_provenance)）。

バックエンドは `mise.lock` の `backend` の値です。

| ツール                                      | バックエンド | 検証の方法                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Betterleaks                                 | aqua         | `checksums.txt` を cosign の署名で検証する（[aqua レジストリの定義](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/betterleaks/betterleaks/registry.yaml)）                                                                                                                                                                                                                                                                                                                                                                                                   |
| actionlint・hadolint・jq・uv・zizmor        | aqua         | GitHub の artifact attestations で検証する（aqua レジストリの定義: [actionlint](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/rhysd/actionlint/registry.yaml)・[hadolint](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/hadolint/hadolint/registry.yaml)・[jq](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/jqlang/jq/registry.yaml)・[uv](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/astral-sh/uv/registry.yaml)・[zizmor](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/zizmorcore/zizmor/registry.yaml)） |
| editorconfig-checker・shfmt・ghalint・typos | github       | GitHub の artifact attestations で検証する（[github バックエンド](https://mise.jdx.dev/dev-tools/backends/github.html)）                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ShellCheck                                  | aqua         | リリースに署名もチェックサムのファイルもない。`mise.lock` の sha256 は、GitHub がリリースのファイルごとに返す digest を使う                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| lychee                                      | aqua         | リリースに署名も GitHub の artifact attestations もない。aqua レジストリの定義にも検証の設定がない（[lycheeverse/lychee](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/lycheeverse/lychee/registry.yaml)）。`mise.lock` の sha256 は、GitHub がリリースのファイルごとに返す digest と同じ値になる                                                                                                                                                                                                                                                            |
| bats                                        | aqua         | リリースにファイルがなく、タグのソースアーカイブを入れる。`mise lock` は sha256 を記録しないので、版（タグ）でだけ固定している                                                                                                                                                                                                                                                                                                                                                                                                                                          |

- github バックエンドで入れるツールを選んだ理由は、[`.github/mise.toml`](.github/mise.toml) のコメントに書いている
- typos のリリースのファイルに付く attestation は、タグとファイルを結び付けるリリースの attestation だけで、ビルドしたワークフローを含まない

### yamllint の依存関係

yamllint は Python のパッケージで、PyYAML と pathspec に依存します（[PyPI](https://pypi.org/project/yamllint/)）。依存関係まで版と sha256 を固定するため、mise ではなく uv で入れています。uv 本体は mise で入れます。

- [`.github/yamllint`](.github/yamllint) の `pyproject.toml` で yamllint の版を、`uv.lock` で依存関係を含むすべての版と sha256 を固定する
- `pyproject.toml` と `uv.lock` は、Renovate の pep621 マネージャーが更新する（[pep621](https://docs.renovatebot.com/modules/manager/pep621/)）

## Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](.github/workflows/renovate.yml) が毎時 23 分に Renovate を実行します。設定は [`.github/renovate.json5`](.github/renovate.json5) にあります。

- PR には `dependencies` ラベルを付ける。タイトルは日本語にする（例: `chore(deps): jdx/mise を v2026.10.3 に更新`・`chore(deps): ロックファイルを更新`）
- PR を作る時間帯は日本時間で決める（`timezone`）。Renovate 本体（`renovate/renovate`・`renovatebot/github-action`）の更新 PR は、毎日 0〜3 時にだけ作る
- 脆弱性は、Dependabot アラートに加えて OSV のデータベースでも照会し、修正版があれば PR を作る（[`osvVulnerabilityAlerts`](https://docs.renovatebot.com/configuration-options/#osvvulnerabilityalerts)）。照会するのは直接の依存関係だけ
- 設定の理由は、[`.github/renovate.json5`](.github/renovate.json5) のコメントに書いている

### 自動マージ

更新の種類によって、自動でマージするかどうかを分けています。

| 更新の種類                                       | マージのしかた                                                                           |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| minor・patch・digest                             | 公開後 14 日を過ぎてから、自動でマージする                                               |
| major                                            | 公開後 14 日を過ぎてから PR を作る。自動ではマージしない。内容を確認して手動でマージする |
| pin・pinDigest（バージョンやダイジェストの固定） | 自動でマージする                                                                         |
| ロックファイルの更新                             | 自動でマージする。PR は毎週月曜の 0〜3 時に作る                                          |
| 上記以外の更新（置き換えなど）                   | 自動ではマージしない。内容を確認して手動でマージする                                     |

- 自動マージには GitHub の自動マージを使い、必須チェックがすべて通るとマージされる（[Renovate の自動マージ](https://docs.renovatebot.com/key-concepts/automerge/)・[GitHub の自動マージ](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)）
- [マージの条件](#マージの条件) のとおり `main` の最新を取り込む必要があるため、同じ実行で作った PR の 2 件目以降は、次の実行まで自動マージされない
- 脆弱性アラートから作る PR は、公開後 14 日を待たずに作られる。minor・patch の更新なら、そのまま自動でマージされる（[Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)）。このとき Renovate は、`pnpm-workspace.yaml` の `minimumReleaseAgeExclude` に修正版を書き足す
  - 検証用ブランチで OSV の脆弱性情報から作らせた PR（[#141](https://github.com/kentayamada-dev/playground/pull/141)）で確認した
- 更新の状況は、Dependency Dashboard の issue「chore(deps): 依存関係の更新状況」にまとまる

### トークンの準備

Renovate は、リポジトリの secret `RENOVATE_TOKEN` に登録した Fine-grained personal access token で操作します。トークンは [トークンの作り方](#トークンの作り方) のとおりに作り、Repository permissions を次の表のとおりに設定します。

| Permission        | Access         | 用途                                                                          |
| ----------------- | -------------- | ----------------------------------------------------------------------------- |
| Contents          | Read and write | リポジトリの取得と、更新用ブランチの push                                     |
| Pull requests     | Read and write | 更新 PR の作成・更新と、自動マージの有効化                                    |
| Issues            | Read and write | Dependency Dashboard の issue の作成・更新                                    |
| Commit statuses   | Read and write | `renovate/stability-days` など、Renovate 自身のステータスの書き込み           |
| Workflows         | Read and write | `.github/workflows` 配下のファイルの更新                                      |
| Dependabot alerts | Read-only      | 脆弱性アラートの読み取り。アラートがあると、Renovate が脆弱性を直す PR を作る |
| Metadata          | Read-only      | 自動で付く（必須）                                                            |

権限の一覧は [Renovate のドキュメント](https://docs.renovatebot.com/modules/platform/github/) に従っています。作成したトークンは、次のコマンドで secret に登録します。

```bash
gh secret set RENOVATE_TOKEN --repo kentayamada-dev/playground
```

## トークンの作り方

[定義とのずれの検査](#検査に使うトークン) と [Renovate](#トークンの準備) が使う Fine-grained personal access token は、[作成画面](https://github.com/settings/personal-access-tokens/new) で次のように作ります。

| 項目                   | 設定する値                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| Token name             | 任意（例: `settings-read-playground`・`renovate-playground`）                                |
| Description            | 任意                                                                                         |
| Resource owner         | `kentayamada-dev`                                                                            |
| Expiration             | 任意。期限が切れると、定義とのずれの検査は失敗して issue が作られ、Renovate は実行が失敗する |
| Repository access      | Only select repositories で `kentayamada-dev/playground` を選ぶ                              |
| Repository permissions | それぞれの節の表のとおりに設定し、ほかは No access のままにする                              |
| Account permissions    | すべて No access のままにする                                                                |
