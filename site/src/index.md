---
layout: layouts/base.njk
title: Mutelet
lang: en
description: Mutelet is an open-source microphone mute utility for Apple Silicon Macs.
languageNavigationLabel: Languages
privacyLabel: Privacy
permalink: "/"
---
<section class="hero">

<div class="hero-copy">

# Mutelet

Mutelet is an open-source microphone mute utility for Apple Silicon Macs. It can control the microphone from the menu bar or a global keyboard shortcut.

</div>

<img class="menu-preview" src="/assets/menu-en.png" width="640" height="570" alt="Mutelet menu showing a muted microphone">

</section>

<section id="download">

## Download

Mutelet 1.0.0 is available free on the Mac App Store and as a signed, notarized download.

<p class="actions">
  <a class="button" href="https://apps.apple.com/app/id6826858511">Get on the Mac App Store</a>
  <a class="button" href="https://github.com/jsoizo/mutelet/releases/download/v1.0.0/Mutelet-1.0.0.dmg">Download Mutelet 1.0.0 DMG</a>
  <a href="https://github.com/jsoizo/mutelet/releases/tag/v1.0.0">Release details and checksum</a>
</p>

**Requirements**

- Apple Silicon Mac
- macOS 14 Sonoma or later

### Installation and updates

Install the App Store version and receive its updates through the App Store. For the DMG version, open the download and drag Mutelet to Applications. To update it, quit Mutelet and replace it with the newer download from GitHub Releases.

### Switching distribution channels

1. Restore any microphone muted by Mutelet, then quit all copies of the app.
2. Replace the existing installation in Applications with the same or a newer version from the other channel. Keep one installation and do not run copies from different paths at the same time.
3. Open Mutelet and check the selected input, mode, shortcuts, and display settings. Test the shortcut; if launch at login no longer works, turn it off and on in Settings and check its approval in macOS System Settings.

Settings and saved microphone-control values are stored locally. Do not delete that data when switching. Switching to an older version is unsupported: an older app may reset settings if it cannot read the stored settings format.

For support, [open an issue](https://github.com/jsoizo/mutelet/issues) or email [jskmt-dev@proton.me](mailto:jskmt-dev@proton.me). See the [privacy policy](https://github.com/jsoizo/mutelet/blob/main/docs/PRIVACY.md) for local-data details.

</section>

<section id="features">

## Features

- Mute the system default input, one selected input, or all inputs.
- Use Toggle to change the mute state with one press, or Push to Talk to stay muted except while the shortcut is held.
- Set a separate shortcut for each mode, including standalone F1–F20 keys. The defaults are Control + Shift + M for Toggle and F8 for Push to Talk.
- Configure the target, HUD size, position and duration, and launch at login from the settings window.
- Optionally maintain the session mute state across input changes, device reconnection, external unmute attempts, and sleep/wake.
- Optionally illuminate the screen edges while Push to Talk can carry sound.

<figure class="hud-preview">
  <video autoplay muted loop playsinline width="960" height="540" poster="/assets/hud-en.png" aria-label="Mutelet showing the microphone state in its on-screen HUD">
    <source src="/assets/hud-en.mp4" type="video/mp4">
  </video>
  <img class="hud-preview-static" src="/assets/hud-en.png" width="960" height="540" loading="lazy" alt="Mutelet HUD showing the microphone state">
  <figcaption>The HUD briefly shows the microphone state after it changes.</figcaption>
</figure>

Mutelet does not record audio, connect to a server, or collect telemetry. It does not request Microphone, Accessibility, or Input Monitoring permission.

The macOS App Sandbox enforces this boundary: Mutelet has no entitlement to capture microphone audio or use the network.

</section>
