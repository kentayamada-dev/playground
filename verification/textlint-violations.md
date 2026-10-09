# textlint の検証用文書

感嘆符を使った文です！

日本語とEnglishの間にスペースがありません。

全角 文字の間にスペースがあります。

かっこの内側に（ スペース ）があります。

スラッシュの前後に struct / enum のスペースがあります。

インラインコードの前後に`code`スペースがありません。

リンクの前後に[リンク](https://example.com)スペースがありません。

サーバとサーバーの表記揺れがあります。

ＡＢＣは全角のアルファベットです。

<!-- textlint-disable ja-space-around-code -->

無効化した範囲の`code`は検出されません。

<!-- textlint-enable ja-space-around-code -->
