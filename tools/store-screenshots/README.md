# Store screenshot studio

実際のアプリ画面と説明文を組み合わせ、Mac App Store 用の画像を作成します。文言は言語別 JSON、撮影素材は `.work/store-screenshots/assets/`、書き出し結果は `.work/store-screenshots/exports/` に分けています。

## 文言を編集して書き出す

```bash
cd site
pnpm install --frozen-lockfile
pnpm screenshots
```

`http://127.0.0.1:4177` を開きます。`copy/ja.json` または `copy/en.json` を編集し、**Reload copy & assets** で読み込み直します。言語を選んで **Export all** を押すと、各4枚の JPEG をローカルの出力フォルダーに保存します。画像は2560×1600で、透明部分はありません。アプリの UI や文章を App Store Connect に自動アップロードする機能はありません。

見出しの `headline` は2行の配列です。ラベルは `label`、説明は `body`、補足は `detail`、画像の代替テキストは `alt` で変更します。3枚目の HUD は `accentImage` と `accentAlt` で指定します。改行や文字数を変えたときは、日英両方のプレビューと書き出し画像で、文字切れや画面への重なりがないか確認してください。見出しが意図した2行を超える場合や説明が補足に重なる場合は、書き出し前にエラーを表示します。

文章は[公式サイト](https://jsoizo.github.io/mutelet/)の機能説明と実装をもとにしています。録音をしないこと、保存済みの状態を復元すること、対応機器に限り操作できることを保ち、日英それぞれで自然な表現にしています。

## 実画面を撮り直す

起動中の Mutelet を終了してから実行します。撮影は Debug の UI テストを使い、固定名のテスト用マイクと一時的な設定で、メニューと設定ウインドウだけを撮影します。実際のマイクや保存済みの設定は操作しません。

```bash
./scripts/capture-store-screenshots.sh
```

macOS 側で UI テストの操作が許可されていない場合、撮影前に失敗することがあります。スクリプトはシステムの権限設定を変更しません。

撮影した素材は次の場所に保存されます。

```text
.work/store-screenshots/assets/
├── en/
│   ├── toggle.jpg
│   ├── push-to-talk.jpg
│   ├── display.jpg
│   ├── general.jpg
│   └── hud.jpg
└── ja/
    └── 同じ5ファイル
```

撮影後は、入力名・画面状態・言語が意図どおりで、個人情報が写っていないことを確認します。素材だけの変更や文言だけの変更では、アプリのリリースビルドを作り直す必要はありません。UI が変わった場合は、そのコミットから撮影し直します。

## レイアウト

1枚目はメニューからのミュート、2枚目は Push to Talk、3枚目は状態表示、4枚目は一般設定を紹介します。4枚とも同じ背景色と文字色を使います。すべての画像に実際のアプリ画面を使い、機器やOS全体の画面を再現したモックアップは使いません。

生成ツールは既存サイトの開発依存 `html-to-image` を使います。`site/src` の外にあるため、公開サイトのビルドには含まれません。

## 文言の方針

公式サイトと同じく、操作と結果を具体的に書きます。「いつもの使い方で」「ひと目でわかる」のような抽象的な売り文句や問いかけで、機能説明を置き換えません。日本語から英語へ語順を移すのではなく、各言語で同じ動作が伝わる文章にします。

AI slop は一般に質の低いAI生成コンテンツを指し、文章について合意された判定基準があるわけではありません。今回の見直しでは、AIが書いたかどうかの判定よりも、読み手が動作を理解できるかを基準にしています。

- [Merriam-Webster: Slop](https://www.merriam-webster.com/wordplay/word-of-the-year)
- [Measuring AI “Slop” in Text](https://arxiv.org/abs/2509.19163)
- [Anthropic: More on writing in design](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md#more-on-writing-in-design)
