import { readFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';

const [attachmentDirectory, outputDirectory] = process.argv.slice(2).map(p => resolve(p));
const manifest = JSON.parse(await readFile(join(attachmentDirectory, 'manifest.json'), 'utf8'));
const attachments = [];
function visit(value) {
  if (!value || typeof value !== 'object') return;
  if (value.exportedFileName && value.suggestedHumanReadableName) attachments.push(value);
  for (const child of Object.values(value)) visit(child);
}
visit(manifest);
const expected = ['toggle', 'push-to-talk', 'display', 'general'];
const matches = [];
for (const locale of ['en', 'ja']) {
  for (const id of expected) {
    const prefix = `store-${locale}-${id}_`;
    const matching = attachments.filter(a => a.suggestedHumanReadableName.startsWith(prefix));
    if (matching.length !== 1) throw new Error(`Expected one attachment for ${prefix}, found ${matching.length}`);
    matches.push({ locale, id, file: matching[0].exportedFileName });
  }
}
for (const { locale, id, file } of matches) {
  const directory = join(outputDirectory, locale);
  await mkdir(directory, { recursive: true });
  execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '100', join(attachmentDirectory, file), '--out', join(directory, `${id}.jpg`)], { stdio: 'pipe' });
  console.log(`${locale}/${id}.jpg`);
}
