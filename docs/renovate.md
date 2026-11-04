# Renovate

依存関係の更新は Renovate で自動化しています。[`.github/workflows/renovate.yml`](../.github/workflows/renovate.yml) が毎時 23 分に Renovate を実行します。設定は [`.github/renovate.json5`](../.github/renovate.json5) にあります。

- PR には `dependencies` ラベルを付ける。タイトルは日本語にする（例: `chore(deps): jdx/mise を v2026.10.3 に更新`・`chore(deps): ロックファイルを更新`）
- PR を作る時間帯は日本時間で決める（`timezone`）。Renovate 本体（`renovate/renovate`・`renovatebot/github-action`）の更新 PR は、毎日 0〜3 時にだけ作る
- 脆弱性は、Dependabot アラートに加えて OSV のデータベースでも照会し、修正版があれば PR を作る（[`osvVulnerabilityAlerts`](https://docs.renovatebot.com/configuration-options/#osvvulnerabilityalerts)）。照会するのは直接の依存関係だけ
- 設定の理由は、[`.github/renovate.json5`](../.github/renovate.json5) のコメントに書いている

## 自動マージ

更新の種類によって、自動でマージするかどうかを分けています。

| 更新の種類 | マージのしかた |
| --- | --- |
| minor・patch・digest | 公開後 14 日を過ぎてから、自動でマージする |
| major | 公開後 14 日を過ぎてから PR を作る。自動ではマージしない。内容を確認して手動でマージする |
| pin・pinDigest（バージョンやダイジェストの固定） | 自動でマージする |
| ロックファイルの更新 | 自動でマージする。PR は毎週月曜の 0〜3 時に作る |
| 上記以外の更新（置き換えなど） | 自動ではマージしない。内容を確認して手動でマージする |

- 自動マージには GitHub の自動マージを使い、必須チェックがすべて通るとマージされる（[Renovate の自動マージ](https://docs.renovatebot.com/key-concepts/automerge/)・[GitHub の自動マージ](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)）
- [マージの条件](ci.md#マージの条件) のとおり `main` の最新を取り込む必要があるため、同じ実行で作った PR の 2 件目以降は、次の実行まで自動マージされない
- 脆弱性アラートから作る PR は、公開後 14 日を待たずに作られる。minor・patch の更新なら、そのまま自動でマージされる（[Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)）。このとき Renovate は、`pnpm-workspace.yaml` の `minimumReleaseAgeExclude` に修正版を書き足す
  - 検証用ブランチで OSV の脆弱性情報から作らせた PR（[#141](https://github.com/kentayamada-dev/playground/pull/141)）で確認した
- 更新の状況は、Dependency Dashboard の issue「chore(deps): 依存関係の更新状況」にまとまる。issue には `dependencies` ラベルを付ける

### 必須チェックで検査する更新

自動でマージする更新のうち、次のものは必須チェックで検査し、壊れる更新を入れないようにしています。

| 更新するもの | 必須チェック | 入れない更新 |
| --- | --- | --- |
| `.github/oxfmt` の `oxfmt` | `oxfmt` | 整形の結果が変わる更新 |
| `.github/jscpd` の `jscpd` | `jscpd` | 重複の検出のしかたが変わって検査に通らなくなる更新 |
| golang のベースイメージ・Dev Container の Go のツール | `golang-check` | イメージがビルドできなくなる更新・コードが検査に通らなくなる更新 |
| node のベースイメージ・pnpm | `node-check` | イメージがビルドできなくなる更新 |
| node の `next`・`typescript`・`@types/*` など | `node-check` | 型が合わなくなる更新・ビルドできなくなる更新 |
| node の `oxlint`・`oxfmt`・`oxlint-tsgolint`・`eslint-plugin-better-tailwindcss`・`knip` | `node-check` | 指摘や整形の結果が変わる更新 |

## GitHub App の準備

Renovate は、GitHub App のトークンで操作します。App のトークンで動かすと、Renovate のコミットに GitHub が署名します。理由は [`renovate.yml`](../.github/workflows/renovate.yml) のコメントに書いています。

App の設定は、[`renovate-app.json`](../.github/settings/renovate-app.json) に [マニフェスト](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) として定義します。App は、次のコマンドでこの定義から作ります。macOS で実行し、`gh` と `jq` が必要です。

```bash
.github/scripts/create-renovate-app/create-renovate-app.sh
```

1. ブラウザで App の作成画面が開く。App の名前は `renovate-app.json` の `name` になる。ほかの App と重なるときは、画面で書き換える
2. 「Create GitHub App」を押すと、リポジトリのページに移る。アドレスバーの URL をコピーして、ターミナルに貼り付ける
3. スクリプトが、App の秘密鍵を secret `RENOVATE_APP_PRIVATE_KEY` に、Client ID を変数 `RENOVATE_APP_CLIENT_ID` に登録する。秘密鍵はファイルに保存しない
4. ブラウザで App のインストール画面が開く。Only select repositories でこのリポジトリを選んで、インストールする

- 貼り付ける URL の `code` は、1 時間で期限が切れる。切れたら、もう一度実行する
- 登録に失敗したら、スクリプトが示す手順で登録し直す
- 環境変数 `GH_REPO` は使わない。スクリプトはリポジトリのルートに移り、git の remote から登録先を決める
- `renovate-app.json` は App を作るときだけ使う。作ったあとに変えたときは、App の設定画面でも同じように変える
- `redirect_url` はリポジトリのページにしている。`code` を受け取るサーバーを立てずに、移った先の URL を貼り付けて渡すため
- Webhook は使わないため、`hook_attributes.active` を `false` にしている

App には、Repository permissions を次の表のとおりに与えます（`renovate-app.json` の `default_permissions`）。ワークフローで作るトークンにも、同じ権限だけを与えます。権限を変えるときは、`renovate-app.json`・[`renovate.yml`](../.github/workflows/renovate.yml) の `permission-*`・この表を合わせて変えます。

| Permission | Access | 用途 |
| --- | --- | --- |
| Contents | Read and write | リポジトリの取得と、更新用ブランチの push |
| Pull requests | Read and write | 更新 PR の作成・更新と、自動マージの有効化 |
| Issues | Read and write | Dependency Dashboard の issue の作成・更新 |
| Commit statuses | Read and write | `renovate/stability-days` など、Renovate 自身のステータスの書き込み |
| Workflows | Read and write | `.github/workflows` 配下のファイルの更新 |
| Dependabot alerts | Read-only | 脆弱性アラートの読み取り。アラートがあると、Renovate が脆弱性を直す PR を作る |
| Metadata | Read-only | 自動で付く（必須） |

権限は [Renovate のドキュメント](https://docs.renovatebot.com/modules/platform/github/) から選んでいます。ドキュメントが App に挙げる権限のうち、Administration・Checks・Merge queues・Members は与えていません。
