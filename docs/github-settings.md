# リポジトリの設定

GitHub の設定は [`.github/settings`](../.github/settings) に JSON で定義し、次のコマンドで反映します。何度実行しても同じ状態になります。`gh` と `jq` が必要です。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh
```

| 定義 | 対象 | 反映のしかた |
| --- | --- | --- |
| [`rulesets`](../.github/settings/rulesets) | ルールセット | `name` が同じルールセットを更新し、なければ作成する。定義にないものは削除する |
| [`repository.json`](../.github/settings/repository.json) | マージの方法・Wiki の有無・シークレットスキャン・プッシュ保護など | 定義に書いた項目だけを更新する |
| [`security.json`](../.github/settings/security.json) | Dependabot・CodeQL など | 定義に書いた項目だけを、`true` なら有効に、`false` なら無効にする |
| [`actions.json`](../.github/settings/actions.json) | GitHub Actions | 定義に書いた項目だけを更新する |
| [`labels.json`](../.github/settings/labels.json) | issue と PR のラベル | 名前が同じラベルの色と説明を更新し、なければ作成する。定義にないものは削除する |

- 定義にないルールセットとラベルは、GitHub の画面で作ったものも削除される。消したラベルは issue や PR からも外れる。Organization のルールセットは対象外
- 定期検査が issue に付けるラベルが GitHub になければ、issue を作ったあとでラベルを付けられずに失敗する
- シークレットスキャンとプッシュ保護は、リポジトリの設定と同じ API で変えるため、`repository.json` の `security_and_analysis` に書く
- CodeQL のデフォルトセットアップも毎回送る。設定が変わらなければ、新しい解析は始まらない（[#190](https://github.com/kentayamada-dev/playground/pull/190) で確認）
- 環境変数 `GH_REPO` は使わない。どのディレクトリから実行しても、スクリプトはリポジトリのルートに移り、git の remote から反映先を決める
- [`renovate-app.json`](../.github/settings/renovate-app.json) は、反映と検査の対象外。Renovate の GitHub App を作るときだけ使う。詳しくは [GitHub App の準備](renovate.md#github-app-の準備)

## 実行に必要な権限

`gh` は `gh auth login` でログインしておきます。実行するアカウントとトークンには、次の権限が必要です。

| 必要な権限 | 理由 |
| --- | --- |
| リポジトリの管理者権限 | 脆弱性アラートやプライベートな脆弱性報告などを切り替える API が求めるため（[リポジトリの REST API](https://docs.github.com/en/rest/repos/repos)） |
| トークンの `repo` スコープ | Actions や CodeQL の設定を変える API が求めるため（[Actions の権限の API](https://docs.github.com/en/rest/actions/permissions)・[CodeQL の API](https://docs.github.com/en/rest/code-scanning/code-scanning)）。`gh auth login` で発行されるトークンには含まれる（[gh の実装](https://github.com/cli/cli/blob/v2.102.0/internal/authflow/flow.go)） |

- 環境変数 `GH_TOKEN` か `GITHUB_TOKEN` があると、`gh` はログインしたトークンより優先してそちらを使う（`gh help environment`）。権限の足りないトークンが入っていると、途中で失敗する

## 定義とのずれの検査

`--check` を付けると、GitHub を変えずに、反映すると変わる箇所を定義とのずれとして示します。ずれがあれば、終了コード 1 で終わります。

```bash
.github/scripts/sync-github-settings/sync-github-settings.sh --check
```

- ルールセットは、GitHub が付ける `id`・`node_id`・`created_at` などを除き、定義と完全に一致するかを比べる
- ほかの設定は、定義に書いた項目だけを比べる。定義に書いた項目が GitHub の応答になければ、ずれとして示す
- 配列は並び順を無視して比べる

[`settings-drift.yml`](../.github/workflows/settings-drift.yml) が毎日これを実行し、ずれがあるか検査に失敗すると issue で知らせます（[検査の失敗を知らせる issue](ci.md#検査の失敗を知らせる-issue)）。ずれは、定義を直すか、同期のコマンドで GitHub を定義に揃えて直します。

- 定義を変えた PR をマージしたら、同期のコマンドを実行する。実行し忘れると、次の検査で issue になる

### 検査に使うトークン

GitHub の設定は、リポジトリの secret `SETTINGS_READ_TOKEN` に登録した Fine-grained personal access token で読みます。`GITHUB_TOKEN` を使わない理由は、[`settings-drift.yml`](../.github/workflows/settings-drift.yml) のコメントに書いています。issue の操作には、ワークフローの `GITHUB_TOKEN` を使います。

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

## GitHub Actions の設定

| 項目 | 設定 |
| --- | --- |
| 実行できるアクション | GitHub 公式・検証済み作成者のアクションと、`patterns_allowed` に書いたアクション・再利用ワークフローだけ。ほかの作成者のアクションや、再利用ワークフローを使うときは、`patterns_allowed` に足す |
| アクションのバージョン | 完全なコミット SHA で固定する |
| フォークからの PR | 外部の貢献者の PR のワークフローは、毎回承認してから動く |
| `GITHUB_TOKEN` の権限 | `permissions` を書かないワークフローでは読み取りだけ。ワークフローから PR を承認できない |

## トークンの作り方

[定義とのずれの検査](#検査に使うトークン) が使う Fine-grained personal access token は、[作成画面](https://github.com/settings/personal-access-tokens/new) で次のように作ります。

| 項目 | 設定する値 |
| --- | --- |
| Token name | 任意（例: `settings-read-playground`） |
| Description | 任意 |
| Resource owner | `kentayamada-dev` |
| Expiration | 任意。期限が切れると、定義とのずれの検査は失敗して issue が作られる |
| Repository access | Only select repositories で `kentayamada-dev/playground` を選ぶ |
| Repository permissions | [検査に使うトークン](#検査に使うトークン) の表のとおりに設定し、ほかは No access のままにする |
| Account permissions | すべて No access のままにする |
