const localePicker = document.querySelector('#locale');
const status = document.querySelector('#status');
const reloadButton = document.querySelector('#reload');
const exportButton = document.querySelector('#export');
const previews = document.querySelector('#previews');
const stage = document.querySelector('#export-stage');
let copy;
let images = {};
let busy = false;
let generation = 0;
const observer = new ResizeObserver(entries => {
  for (const { target, contentRect } of entries) {
    target.firstElementChild.style.transform = `scale(${contentRect.width / 2560})`;
  }
});
async function dataImage(path) {
  const response = await fetch(path, { cache: 'no-store' });
  if (!response.ok) throw new Error(`Missing image: ${path}. Run scripts/capture-store-screenshots.sh first.`);
  const blob = await response.blob();
  return await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}
function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}
function image(src, alt, className) {
  const element = node('img', className);
  element.src = src;
  element.alt = alt;
  element.draggable = false;
  return element;
}
function slideElement(slide, index) {
  const element = node('article', `slide ${slide.id}`);
  element.lang = copy.locale;
  const brand = node('div', 'brand');
  brand.append(image(images.icon, '', ''), node('span', 'brand-name', copy.brand));
  const caption = node('div', 'copy');
  const headline = node('h1');
  for (const line of slide.headline) headline.append(node('span', '', line));
  caption.append(node('div', 'label', slide.label), headline, node('p', 'body', slide.body));
  const visual = node('div', 'visual');
  visual.append(image(images[slide.image], slide.alt, 'capture'));
  element.append(brand, node('div', 'tagline', copy.tagline), caption, visual, node('p', 'detail', slide.detail), node('span', 'number', `${String(index + 1).padStart(2, '0')} / ${String(copy.slides.length).padStart(2, '0')}`));
  return element;
}
function controlsDisabled(value) {
  busy = value;
  exportButton.disabled = value;
  reloadButton.disabled = value;
  localePicker.disabled = value;
}
async function load() {
  const current = ++generation;
  controlsDisabled(true);
  status.textContent = 'Loading copy and captured screens…';
  try {
    const locale = localePicker.value;
    const response = await fetch(`/copy/${locale}.json`, { cache: 'no-store' });
    if (!response.ok) throw new Error('Could not load copy');
    const next = await response.json();
    if (next.locale !== locale || next.slides.length !== 4) throw new Error('Copy must contain the selected locale and four slides');
    const expected = ['toggle', 'push-to-talk', 'display', 'general'];
    next.slides.forEach((slide, index) => {
      if (slide.id !== expected[index] || !Array.isArray(slide.headline) || slide.headline.length !== 2 || ['label', 'body', 'detail', 'alt'].some(key => typeof slide[key] !== 'string' || !slide[key].trim()) || !/^[a-z-]+\.jpg$/.test(slide.image)) throw new Error(`Invalid copy at slide ${index + 1}`);
    });
    const pairs = await Promise.all(next.slides.map(async slide => [slide.image, await dataImage(`/assets/${locale}/${slide.image}`)]));
    const icon = await dataImage('/icon.png');
    if (current !== generation) return;
    copy = next;
    images = Object.fromEntries([...pairs, ['icon', icon]]);
    observer.disconnect();
    previews.replaceChildren();
    copy.slides.forEach((slide, index) => {
      const card = node('section', 'preview');
      const viewport = node('div', 'viewport');
      viewport.append(slideElement(slide, index));
      card.append(node('h2', '', `${String(index + 1).padStart(2, '0')} · ${slide.label}`), viewport);
      previews.append(card);
      observer.observe(viewport);
    });
    status.textContent = 'Ready. Edit the JSON files and reload to update the wording.';
    controlsDisabled(false);
  } catch (error) {
    copy = null;
    status.textContent = error.message;
    controlsDisabled(false);
    exportButton.disabled = true;
  }
}
async function exportAll() {
  if (busy || !copy) return;
  controlsDisabled(true);
  try {
    for (const [index, slide] of copy.slides.entries()) {
      status.textContent = `Exporting ${index + 1} / ${copy.slides.length}…`;
      const element = slideElement(slide, index);
      stage.replaceChildren(element);
      stage.style.left = '0px';
      stage.style.zIndex = '-1';
      await Promise.all([...element.querySelectorAll('img')].map(img => img.decode()));
      await document.fonts.ready;
      const options = { width: 2560, height: 1600, pixelRatio: 1, quality: 1, backgroundColor: '#f7f9fe', fontEmbedCSS: '', skipAutoScale: true };
      await htmlToImage.toJpeg(element, options);
      const output = await htmlToImage.toJpeg(element, options);
      const response = await fetch('/export', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ locale: copy.locale, id: slide.id, image: output }) });
      if (!response.ok) throw new Error(await response.text());
      stage.style.left = '-9999px';
      stage.replaceChildren();
    }
    status.textContent = `Saved ${copy.slides.length} images to .work/store-screenshots/exports/${copy.locale}/`;
  } catch (error) {
    status.textContent = `Export failed: ${error.message}`;
  } finally {
    stage.style.left = '-9999px';
    stage.replaceChildren();
    controlsDisabled(false);
  }
}
reloadButton.addEventListener('click', load);
localePicker.addEventListener('change', load);
exportButton.addEventListener('click', exportAll);
await load();
