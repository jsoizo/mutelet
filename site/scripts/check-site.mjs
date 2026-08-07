import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";

const outputDirectory = path.resolve("_site");
const pages = [
  {
    file: "index.html",
    lang: "en",
    headings: ["Mutelet", "Features", "Download"]
  },
  {
    file: "ja/index.html",
    lang: "ja",
    headings: ["Mutelet", "機能", "ダウンロード"]
  }
];

for (const page of pages) {
  const html = await readFile(path.join(outputDirectory, page.file), "utf8");

  assert.match(html, new RegExp(`<html lang="${page.lang}">`));
  assert.match(html, /href="\/mutelet\/"/);
  assert.match(html, /href="\/mutelet\/ja\/"/);
  assert.match(html, /href="\/mutelet\/assets\/vendor\/simple\.min\.css"/);
  assert.match(html, /href="\/mutelet\/assets\/site\.css"/);

  for (const heading of page.headings) {
    assert.ok(html.includes(`>${heading}</h`), `${page.file} is missing ${heading}`);
  }
}

await access(path.join(outputDirectory, "assets/vendor/simple.min.css"));
await access(path.join(outputDirectory, "assets/site.css"));

console.log("Site checks passed.");
