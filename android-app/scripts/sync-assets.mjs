import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, '..');
const srcLawIndex = path.resolve(
  appRoot,
  '../harmony-app/entry/src/main/resources/rawfile/law_index.json'
);
const dstDir = path.resolve(appRoot, 'public/data');
const dstLawIndex = path.resolve(dstDir, 'law_index.json');

if (!fs.existsSync(srcLawIndex)) {
  console.error('[sync-assets] Missing source law_index.json:', srcLawIndex);
  process.exit(1);
}

fs.mkdirSync(dstDir, { recursive: true });

const srcStat = fs.statSync(srcLawIndex);
const needsCopy =
  !fs.existsSync(dstLawIndex) ||
  fs.statSync(dstLawIndex).size !== srcStat.size ||
  fs.statSync(dstLawIndex).mtimeMs < srcStat.mtimeMs;

if (needsCopy) {
  fs.copyFileSync(srcLawIndex, dstLawIndex);
  console.log(
    `[sync-assets] Copied law_index.json (${(srcStat.size / 1024 / 1024).toFixed(1)} MB) -> public/data/law_index.json`
  );
} else {
  console.log('[sync-assets] public/data/law_index.json is up to date.');
}
