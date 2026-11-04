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

Mutelet 1.0.0は、Mac App Storeまたは署名・公証済みのダウンロード版を無料で利用できます。

<p class="actions">
  <a class="button" href="https://apps.apple.com/jp/app/id6826858511">Mac App Storeで入手</a>
  <a class="button" href="https://github.com/jsoizo/mutelet/releases/download/v1.0.0/Mutelet-1.0.0.dmg">Mutelet 1.0.0のDMGをダウンロード</a>
  <a href="https://github.com/jsoizo/mutelet/releases/tag/v1.0.0">リリース詳細とチェックサム</a>
</p>

**動作環境**

- Apple Silicon搭載Mac
- macOS 14 Sonoma以降

### インストールと更新

App Store版のインストールと更新は、App Storeから行います。DMG版はダウンロードしたファイルを開き、Muteletをアプリケーションフォルダへドラッグします。更新するときはMuteletを終了し、GitHub Releasesから入手した新しい版で置き換えます。

### 配布元を切り替える

1. Muteletでミュートしたマイクを元の状態に戻し、起動中のMuteletをすべて終了します。
2. 別の配布元から同じか新しいバージョンを入手し、アプリケーションフォルダ内の既存のアプリを置き換えます。インストール先は1か所にし、別の場所にあるコピーを同時に起動しないでください。
3. Muteletを開き、対象のマイク、モード、ショートカット、画面表示の設定を確認します。ショートカットの動作も確認してください。ログイン時に起動しなくなった場合は、設定で一度オフにしてからオンにし、macOSのシステム設定で許可を確認します。

設定とマイクの制御値を復元するためのデータはMac内に保存しています。切り替え時に削除しないでください。古いバージョンへの切り替えはサポートしていません。保存された設定の形式を読み取れない場合、古い版では設定が初期化されることがあります。

お問い合わせは[Issue](https://github.com/jsoizo/mutelet/issues)または[jskmt-dev@proton.me](mailto:jskmt-dev@proton.me)で受け付けています。Mac内の保存データについては[プライバシーポリシー](https://github.com/jsoizo/mutelet/blob/main/docs/PRIVACY.md)を参照してください。

</section>

<section id="features">

## 機能

- Macで現在使用しているマイク、指定したマイク、または接続中のすべてのマイクを操作できます。
- トグルでは、ショートカットを押すたびにミュートを切り替えます。Push to Talkでは、ショートカットを押している間だけミュートを解除します。
- ショートカットはモードごとに設定でき、F1〜F20の単独キーにも対応しています。初期設定はトグルがControl + Shift + M、Push to TalkがF8です。
- 対象のマイク、画面上の状態表示のサイズ・位置・表示時間、ログイン時の起動を設定画面から変更できます。
- マイクの切り替えや再接続、ほかのアプリによるミュート解除、スリープからの復帰後も、ミュート状態を自動で維持する設定を選べます。
- Push to Talkで音声が通る間、画面の縁を光らせて知らせる表示も選べます。

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
