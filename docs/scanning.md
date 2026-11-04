# 脆弱性・ライセンス・シークレットの検査

## 脆弱性とマルウェアの検査

依存関係に既知の脆弱性やマルウェアがないかを、[OSV-Scanner](https://google.github.io/osv-scanner/) と Dependabot で検査しています。結果はどれも Security タブに出ます。Dev Container のイメージは検査しません。Go のコードは、[govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck) でも検査し、結果を issue に出します。`main` の OSV-Scanner の検査が失敗したときも、issue で知らせます。

| 仕組み | 実行のタイミング | 結果 |
| --- | --- | --- |
| [`osv-scanner.yml`](../.github/workflows/osv-scanner.yml) の `osv-scanner` | PR ごと | PR のベースと比べて新しく入ったものがあると失敗する。必須チェックなので、失敗するとマージできない |
| [`osv-scanner.yml`](../.github/workflows/osv-scanner.yml) の `osv-scanner-full` | `main` への push と毎日 | 見つかったものを Code scanning に出し、1 件でもあれば失敗する。失敗すると issue を作る |
| Dependabot アラート | アドバイザリが公開されたときと、依存関係を変えて push したとき | 脆弱性を Dependabot のアラートに出す |
| [`govulncheck.yml`](../.github/workflows/govulncheck.yml) | 毎日と手動の実行 | [`golang`](../golang) のコードが呼び出す関数に脆弱性があると失敗し、issue を作る。必須チェックではない |

- 間接的な依存関係を検査しているのは OSV-Scanner だけ。GitHub の依存関係グラフは、どちらのロックファイルからも間接的な依存関係を読まないため
  - 依存関係グラフは、`pnpm-lock.yaml` の 1 つ目の文書しか読まない（文書の順番を入れ替えて確認した）
  - pnpm は、1 つ目の文書に pnpm 本体の版を書く。依存関係があるのは 2 つ目の文書（[Reading pnpm-lock.yaml](https://pnpm.io/lockfile)）
  - yamllint の `uv.lock` は、依存関係グラフが読むファイルの一覧にない（[Dependency graph supported package ecosystems](https://docs.github.com/en/code-security/reference/supply-chain-security/dependency-graph-supported-package-ecosystems)）
- Dependabot のマルウェアアラートは有効にしていない。Dependabot が読むパッケージは、すべて OSV-Scanner でも検査しているため
- Actions のアクションは SHA で固定しているため、Dependabot のアラートは出ない（[Dependabot alerts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)）。OSV-Scanner もデフォルトでは Actions を検査しない
- Go の標準ライブラリは、OSV-Scanner でも検査する。[`golang/osv-scanner.toml`](../golang/osv-scanner.toml) の `ScanGoModVersion` で、[`golang/go.mod`](../golang/go.mod) の `toolchain` の版を使う。OSV-Scanner は、デフォルトでは go.mod の Go の版を検査に使わない（[Scan Go Mod Version](https://google.github.io/osv-scanner/configuration/#scan-go-mod-version)）
  - Renovate も、`toolchain` の版で脆弱性を照会し、修正版への PR を作る
- Dev Container のイメージの脆弱性は検査しない。イメージの中身は、ベースイメージと pnpm と Go のツールで、どれも Renovate が新しい版に上げる
  - 見つかっても、こちらで取れる手はそれらの版を上げることだけで、Renovate の更新と変わらない
  - 見つかる脆弱性の大半は、ベースイメージの OS パッケージにある、修正版のないもの
- govulncheck は、標準ライブラリも検査する。Go の脆弱性データベースには、標準ライブラリの脆弱性も載っている（例: [GO-2024-2687](https://pkg.go.dev/vuln/GO-2024-2687)）
  - 標準ライブラリの脆弱性は、golang の Dev Container の Go の版で判定する。理由は、[`govulncheck.yml`](../.github/workflows/govulncheck.yml) のコメントに書いている
  - テストのファイルと、Dev Container の Go のツールは検査しない
  - 脆弱性が見つかると、issue で知らせる（[検査の失敗を知らせる issue](ci.md#検査の失敗を知らせる-issue)）
  - PR の検査にしない理由は、`govulncheck.yml` のコメントに書いている
- `main` の `osv-scanner-full` が失敗すると、`osv-scanner-full-report` が issue で知らせる（[検査の失敗を知らせる issue](ci.md#検査の失敗を知らせる-issue)）
  - 本文には、Code scanning で開いている OSV-Scanner のアラートを表にして載せる
  - 次の実行は、issue に触れない
    - `main` 以外のブランチでの手動実行
    - 報告する前に `main` へ新しいコミットが入った実行。報告は新しいコミットの実行に任せる
  - issue で知らせる理由は、[`osv-scanner.yml`](../.github/workflows/osv-scanner.yml) のコメントに書いている
- 見つかった脆弱性は、依存関係の種類ごとに次のように直す
  - 直接の依存関係は、Renovate が修正版への PR を作る（[Renovate](renovate.md#renovate)）
  - pnpm のロックファイルにある間接的な依存関係には、Renovate は PR を作らない。毎週のロックファイルの更新で上がる（例: `fast-uri` は [#305](https://github.com/kentayamada-dev/playground/pull/305) で上がった）
  - 毎週の更新を待たずに直すときは、Dependency Dashboard の issue の「Awaiting Schedule」で、ロックファイルの更新を選ぶ。次の Renovate の実行で PR が作られる（[`dependency-dashboard.ts`](https://github.com/renovatebot/renovate/blob/44.151.1/lib/workers/repository/dependency-dashboard.ts#L515-L524)）
  - Dev Container の Go のツールの依存関係は、依存関係だけを上げず、ツールの新しい版で上げる。理由は、golang の Dockerfile のコメントに書いている
- 次の脆弱性は、ロックファイルと同じディレクトリの `osv-scanner.toml` に、理由と期限（`ignoreUntil`）を付けて除外する。設定はそのディレクトリのロックファイルにだけ効く（[Configuration](https://google.github.io/osv-scanner/configuration/)）
  - 修正版がなく、影響もない脆弱性（例: [`.devcontainer/golang/tools/gosec/osv-scanner.toml`](../.devcontainer/golang/tools/gosec/osv-scanner.toml) の GO-2026-5932）
  - 修正版はあるが、すぐには取り込めない脆弱性。依存元が修正版を使う版を出すのを待つときや、公開後 14 日の待機が明けるのを待つときなど。期限は取り込める見込みの日にし、理由に何を待っているかを書く
- 期限を過ぎると除外は切れ、また検出される（[`config.go`](https://github.com/google/osv-scanner/blob/v2.6.0/internal/config/config.go#L149-L157)）。除外が要らなくなると、OSV-Scanner のログに `has unused ignores` と出る（CI のログで確認した）

## ライセンスの検査

依存関係のライセンスは、[`osv-scanner.yml`](../.github/workflows/osv-scanner.yml) の `osv-scanner-licenses` が、PR ごとと `main` への push で検査します。必須チェックなので、失敗するとマージできません。

- 許可するライセンスは、ワークフローの `allowed_licenses` に SPDX の識別子で 1 行に 1 つ並べている。今の依存関係にある種類をすべて許可していて、新しい種類のライセンスが入ると失敗する
- 新しい種類を許可に足すかは、そのライセンスの条件を確認してから決める
- ライセンスを判定できないパッケージは、[`.github/osv-scanner-licenses.toml`](../.github/osv-scanner-licenses.toml) でライセンスを上書きし、理由を書く
- この検査では脆弱性を見ない。脆弱性は、[脆弱性とマルウェアの検査](#脆弱性とマルウェアの検査) のほかの検査が見る

## シークレットの検査

トークンやパスワードなどのシークレットがコミットに含まれていないかを、[Betterleaks](https://github.com/betterleaks/betterleaks) で検査しています。

[`betterleaks.yml`](../.github/workflows/betterleaks.yml) は、PR ごとと `main` への push で、`HEAD` からたどれる git 履歴全体を走査します。1 件でも見つかると失敗します。必須チェックなので、失敗するとマージできません。

- 見つかった値を実行ログに出さない（`--redact`）
- プロバイダーの API に問い合わせて、見つかったシークレットが有効かどうかは確認しない（`--validation` を付けていない）
- 誤検知の除外のしかたは、[指摘を無視する方法](ci.md#指摘を無視する方法) の表にまとめている
- 行にコメントを書けないときは、ルートの `.betterleaksignore` に fingerprint を 1 行ずつ書いて除外する。fingerprint の形式は `<コミット>:<パス>:<ルール ID>:<行番号>` で、`--report-format json` のレポートでは `Fingerprint` に出る
