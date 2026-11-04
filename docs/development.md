# 開発環境の構成

開発環境の始め方は、[README](../README.md#開発環境) にあります。

- macOS 以外のホストでは、コンテナを作る前に止める。両方の `devcontainer.json` の `initializeCommand` が、ホストで [`check-host-os.sh`](../.devcontainer/scripts/check-host-os/check-host-os.sh) を実行する。理由はダイアログには出ず、コマンドパレットの「Dev Containers: Show Container Log」で開くログの末尾近くに出る
- 2 つのコンテナは、[`compose.yaml`](../compose.yaml) のサービスとして動く。どちらも、リポジトリのルートを `/workspace` にマウントする。イメージは公式イメージをもとに、コンテナごとの Dockerfile でビルドする。Dockerfile を変えたら「Dev Containers: Rebuild Container」で作り直す
- 一般ユーザー `dev` で動き、sudo は入れていない。root で作業するときは、手元のリポジトリのルートで `docker compose exec -u root golang bash` のように実行する。ユーザー名は `compose.yaml` の `x-build-args` で渡している
- node は pnpm を使う。版は node の Dockerfile だけで管理し、Renovate が更新する。[`node/pnpm-workspace.yaml`](../node/pnpm-workspace.yaml) は、`storeDir` のほかは textlint の [`pnpm-workspace.yaml`](../.github/textlint/pnpm-workspace.yaml) とそろえている。golang には、`compose.yaml` の `GOLANG_URL` のアドレスで接続する
- node では npm を使えない。`npm install`・`npm run` などは、`EBADDEVENGINES` のエラーで止まる。[`node/package.json`](../node/package.json) の `devEngines.packageManager` で pnpm を指定しているため（[devEngines](https://docs.npmjs.com/cli/v11/configuring-npm/package-json#devengines)）
- `devEngines.packageManager` には版を書かず、pnpm の版は Dockerfile の 1 か所で管理する。pnpm は `onFail` を省くと `download` として扱うため、`error` を明示している（[pmOnFail](https://pnpm.io/settings/cli#pmonfail)）
- node・textlint・oxfmt・jscpd の pnpm は、本体とパッケージを Takumi Guard のレジストリ（`https://npm.flatt.tech/`）から取得する。`@jsr` スコープも同じレジストリに向け、`npmjs:` と `gh:`（GitHub Packages）は使えないようにしている（[Registries](https://pnpm.io/registries)）
- 公開から 1 日（`minimumReleaseAge: 1440` 分）経っていない版は入れない。待機期間を満たす版がないときと、レジストリが公開日時を返さないときは、インストールが失敗する。以前の版より信頼のレベルが下がった版も入れない（`trustPolicy: no-downgrade`）。どれも [pnpm の設定](https://pnpm.io/settings/dependency-resolution) による
- golang は、gopls・gofumpt・staticcheck・gosec・govulncheck をイメージに入れている。版は [`.devcontainer/golang/tools`](../.devcontainer/golang/tools) のツールごとの `go.mod` で管理し、Renovate が更新する
- bash の履歴、node の `node_modules`・pnpm のストア、golang のモジュールとビルドのキャッシュは、名前付きボリュームに置く。コンテナを作り直しても、履歴とキャッシュは残る。手元の `node/node_modules` は空のディレクトリになる
- node のコンテナを作ると、`node` で `pnpm install` を実行する。インストールが終わってから、VS Code がコンテナに接続する
- ウィンドウを閉じても、コンテナは止めない（`shutdownAction: "none"`）
- 設定の理由は、[`compose.yaml`](../compose.yaml)・`devcontainer.json`・Dockerfile のコメントに書いている
