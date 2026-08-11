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

Muteletは、Apple Silicon搭載Mac向けのオープンソースのマイクミュートアプリです。メニューバーまたはグローバルショートカットから、マイクのミュートや解除ができるようになります。

</div>

<img class="menu-preview" src="/assets/menu-ja.png" width="640" height="570" alt="マイクをミュートしているMuteletのメニュー">

</section>

<section id="download">

## ダウンロード

Developer IDで署名し、Appleの公証を受けたMutelet 0.1.0を公開しています。

<p class="actions">
  <a class="button" href="https://github.com/jsoizo/mutelet/releases/download/v0.1.0/Mutelet-0.1.0.dmg">Mutelet 0.1.0をダウンロード</a>
  <a href="https://github.com/jsoizo/mutelet/releases/tag/v0.1.0">リリース詳細とチェックサム</a>
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

この境界はmacOSのApp Sandboxでも強制され、Muteletにはマイク音声を取得したりネットワークへ接続したりする権限がありません。

</section>
