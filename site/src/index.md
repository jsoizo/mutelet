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

Mutelet 0.1.0 is available as a Developer ID-signed and Apple-notarized release.

<p class="actions">
  <a class="button" href="https://github.com/jsoizo/mutelet/releases/download/v0.1.0/Mutelet-0.1.0.dmg">Download Mutelet 0.1.0</a>
  <a href="https://github.com/jsoizo/mutelet/releases/tag/v0.1.0">Release details and checksum</a>
</p>

**Requirements**

- Apple Silicon Mac
- macOS 14 Sonoma or later

</section>

<section id="features">

## Features

- Mute the system default input, one selected input, or all inputs.
- Use Toggle to change the mute state with one press, or Push to Talk to stay muted except while the shortcut is held.
- Configure the target, shortcut, HUD, and launch at login from the settings window.
- Follow default-device changes and reconnect selected devices.

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
