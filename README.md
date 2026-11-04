# playground

個人の実験用リポジトリです。GitHub のリポジトリの設定・CI・依存関係の更新を、Git で管理する定義とワークフローにまとめています。

- [コントリビューションガイド](CONTRIBUTING.md): issue・ブランチ・PR・コードの規約
- [行動規範](CODE_OF_CONDUCT.md)
- [セキュリティポリシー](SECURITY.md): 脆弱性を非公開で報告する手順
- [ライセンス](LICENSE): MIT License

## ドキュメント

- [開発環境の構成](docs/development.md): コンテナの構成と、pnpm・Go のツールの管理
- [CI の検査](docs/ci.md): ワークフローごとの検査・マージの条件・検査する範囲・指摘を無視する方法・CI で使うツール
- [脆弱性・ライセンス・シークレットの検査](docs/scanning.md): 依存関係とコミットの検査と、見つかったものの直し方
- [リポジトリの設定](docs/github-settings.md): GitHub の設定を定義から反映する手順と、定義とのずれの検査
- [Renovate](docs/renovate.md): 依存関係の更新・自動マージと、GitHub App の準備

## 開発環境

node と golang を、別々の Dev Container で開発します。ホストの OS は macOS だけをサポートします。構成は VS Code の [Connect to multiple containers](https://code.visualstudio.com/remote/advancedcontainers/connect-multiple-containers) にならっています。

| コンテナ | 設定 | 開くディレクトリ | ベースイメージ |
| --- | --- | --- | --- |
| `node` | [`devcontainer.json`](.devcontainer/node/devcontainer.json)・[`Dockerfile`](.devcontainer/node/Dockerfile) | [`node`](node) | `node` |
| `golang` | [`devcontainer.json`](.devcontainer/golang/devcontainer.json)・[`Dockerfile`](.devcontainer/golang/Dockerfile) | [`golang`](golang) | `golang` |

構成の詳細は、[開発環境の構成](docs/development.md) にあります。

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

### DB を起動する

[`compose.yaml`](compose.yaml) の `db` で、Supabase の Postgres を動かせます。データは `studio` の Supabase Studio で見ます。Dev Container を開いても起動しないため、手元のリポジトリのルートで次を実行します。

```bash
docker compose up -d studio
```

- `studio` が使う `meta`（postgres-meta）と `db` も起動する。起動したら、手元のブラウザで `http://localhost:54323` を開く
- Studio は、手元のブラウザからしか開けない。`db` のポートは手元に公開しない
- Auth・Storage など、入れていないサービスに依存する Studio の画面はエラーになる
- 止めるときは、`docker compose stop studio meta db` のようにサービス名を付けて実行する。サービス名を付けない `docker compose stop`・`docker compose down` は、この 3 つを止めない（[Using profiles](https://docs.docker.com/compose/how-tos/profiles/)）
- データは名前付きボリュームに置く。コンテナを作り直しても、データは残る
