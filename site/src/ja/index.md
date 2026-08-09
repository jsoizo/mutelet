---
layout: layouts/base.njk
title: Mutelet
lang: ja
description: Muteletは、Apple Silicon搭載Mac向けのオープンソースのマイクミュートアプリです。
languageNavigationLabel: 言語
privacyLabel: プライバシー
permalink: "/ja/"
---
<section class="hero">

<div class="hero-copy">

# Mutelet

Muteletは、Apple Silicon搭載Mac向けのオープンソースのマイクミュートアプリです。メニューバーまたはグローバルショートカットから、マイクをミュートしたり解除したりできます。

</div>

<img class="menu-preview" src="/assets/menu-ja.png" width="640" height="570" alt="マイクをミュートしているMuteletのメニュー">

</section>

<section id="download">

## ダウンロード

Muteletは現在開発中です。署名・公証済みの初回リリースはまだ公開していません。公開後は[GitHub Releases](https://github.com/jsoizo/mutelet/releases)からダウンロードできます。それまでは、リポジトリの手順に従ってソースコードからビルドできます。

<p class="actions">
  <a class="button" href="https://github.com/jsoizo/mutelet">GitHubでソースコードを見る</a>
  <a href="https://github.com/jsoizo/mutelet/releases">リリースを確認</a>
</p>

**動作環境**

- Apple Silicon搭載Mac
- macOS 14 Sonoma以降

</section>

<section id="features">

## 機能

- Macで現在使用しているマイク、指定したマイク、または接続中のすべてのマイクを操作できます。
- トグルでは、ショートカットを押すたびにミュートを切り替えます。プッシュトゥトークでは、ショートカットを押している間だけミュートを解除します。
- 対象のマイク、ショートカット、画面上の状態表示、ログイン時の起動を設定画面から変更できます。
- 使用するマイクが変わったときや、機器をつなぎ直したときも、自動的に状態を更新します。

<figure class="hud-preview">
  <video autoplay muted loop playsinline width="960" height="540" poster="/assets/hud-ja.png" aria-label="マイクの状態を画面上に表示するMutelet">
    <source src="/assets/hud-ja.mp4" type="video/mp4">
  </video>
  <img class="hud-preview-static" src="/assets/hud-ja.png" width="960" height="540" loading="lazy" alt="マイクの状態を示すMuteletの画面表示">
  <figcaption>マイクの状態を切り替えると、画面上に短時間表示します。</figcaption>
</figure>

Muteletは音声を録音しません。サーバーへの通信や利用状況の収集も行わず、マイク、アクセシビリティ、入力監視の権限も求めません。

</section>
