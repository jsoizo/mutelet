import http from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, join, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const root = resolve(directory, '../..');
const workspace = join(root, '.work/store-screenshots');
const port = Number(process.env.PORT || 4177);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.jpg': 'image/jpeg', '.png': 'image/png' };
const routes = new Map([
  ['/', join(directory, 'index.html')],
  ['/app.js', join(directory, 'app.js')],
  ['/style.css', join(directory, 'style.css')],
  ['/vendor/html-to-image.js', join(root, 'site/node_modules/html-to-image/dist/html-to-image.js')],
  ['/icon.png', join(root, 'Sources/Mutelet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')],
]);
function within(base, suffix) {
  const target = resolve(base, suffix);
  if (!target.startsWith(resolve(base) + sep)) throw new Error('Invalid path');
  return target;
}
const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://127.0.0.1:${port}`);
    if (request.method === 'POST' && url.pathname === '/export') {
      if (request.headers.origin !== `http://127.0.0.1:${port}`) {
        response.writeHead(403).end(); return;
      }
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 20_000_000) throw new Error('Export too large');
        chunks.push(chunk);
      }
      const { locale, id, image } = JSON.parse(Buffer.concat(chunks).toString());
      if (!['en', 'ja'].includes(locale) || !/^[a-z-]+$/.test(id)) throw new Error('Invalid export');
      const copy = JSON.parse(await readFile(join(directory, 'copy', `${locale}.json`), 'utf8'));
      const index = copy.slides.findIndex(slide => slide.id === id);
      if (index < 0 || !image.startsWith('data:image/jpeg;base64,')) throw new Error('Invalid image');
      const filename = `${String(index + 1).padStart(2, '0')}-${id}-${locale}-2560x1600.jpg`;
      const folder = join(workspace, 'exports', locale);
      await mkdir(folder, { recursive: true });
      await writeFile(join(folder, filename), Buffer.from(image.split(',')[1], 'base64'));
      response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ path: `.work/store-screenshots/exports/${locale}/${filename}` }));
      return;
    }
    if (request.method !== 'GET') { response.writeHead(405).end(); return; }
    let path = routes.get(url.pathname);
    if (url.pathname.startsWith('/copy/')) path = within(join(directory, 'copy'), url.pathname.slice(6));
    if (url.pathname.startsWith('/assets/')) path = within(join(workspace, 'assets'), url.pathname.slice(8));
    if (!path) { response.writeHead(404).end('Not found'); return; }
    const data = await readFile(path);
    response.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream', 'Cache-Control': 'no-store' }).end(data);
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' ? 404 : 400, { 'Content-Type': 'text/plain' }).end(error.message);
  }
});
server.listen(port, '127.0.0.1', () => console.log(`Screenshot studio: http://127.0.0.1:${port}`));
