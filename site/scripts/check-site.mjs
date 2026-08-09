import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";

const outputDirectory = path.resolve("_site");
const pages = [
  {
    file: "index.html",
    lang: "en",
    headings: ["Mutelet", "Download", "Features"],
    menuImage: "menu-en.png",
    hudVideo: "hud-en.mp4",
    hudImage: "hud-en.png"
  },
  {
    file: "ja/index.html",
    lang: "ja",
    headings: ["Mutelet", "ダウンロード", "機能"],
    menuImage: "menu-ja.png",
    hudVideo: "hud-ja.mp4",
    hudImage: "hud-ja.png"
  }
];

for (const page of pages) {
  const html = await readFile(path.join(outputDirectory, page.file), "utf8");

  assert.match(html, new RegExp(`<html lang="${page.lang}">`));
  assert.match(html, /href="\/mutelet\/"/);
  assert.match(html, /href="\/mutelet\/ja\/"/);
  assert.match(html, /href="\/mutelet\/assets\/vendor\/simple\.min\.css"/);
  assert.match(html, /href="\/mutelet\/assets\/site\.css"/);
  assert.match(html, new RegExp(`src="/mutelet/assets/${page.menuImage}"`));
  assert.match(html, new RegExp(`src="/mutelet/assets/${page.hudVideo}"`));
  assert.match(html, new RegExp(`src="/mutelet/assets/${page.hudImage}"`));
  assert.match(html, /<video autoplay="" muted="" loop="" playsinline="" width="960" height="540"/);

  let previousHeadingPosition = -1;
  for (const heading of page.headings) {
    const headingPosition = html.indexOf(`>${heading}</h`);
    assert.ok(headingPosition > previousHeadingPosition, `${page.file} is missing or misorders ${heading}`);
    previousHeadingPosition = headingPosition;
  }
}

await access(path.join(outputDirectory, "assets/vendor/simple.min.css"));
await access(path.join(outputDirectory, "assets/site.css"));
await access(path.join(outputDirectory, "assets/app-icon.png"));
await access(path.join(outputDirectory, "assets/menu-en.png"));
await access(path.join(outputDirectory, "assets/menu-ja.png"));
await access(path.join(outputDirectory, "assets/hud-en.mp4"));
await access(path.join(outputDirectory, "assets/hud-ja.mp4"));
await access(path.join(outputDirectory, "assets/hud-en.png"));
await access(path.join(outputDirectory, "assets/hud-ja.png"));

console.log("Site checks passed.");
