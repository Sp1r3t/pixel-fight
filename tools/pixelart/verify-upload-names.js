"use strict";
// Read-only check of supplied image IDs against public Roblox asset metadata.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '../..');
const inputFile = path.resolve(root, process.argv[2] || 'art/sprites/v3/asset-ids.json');
const ids = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
const previousFile = path.join(path.dirname(inputFile), 'upload-verification.json');
const legacyFile = path.join(root, 'art/sprites/v2/upload-verification.json');
const previous = fs.existsSync(previousFile) ? JSON.parse(fs.readFileSync(previousFile, 'utf8')) : fs.existsSync(legacyFile) ? JSON.parse(fs.readFileSync(legacyFile, 'utf8')) : [];
const results = previous.filter(r => r.matches && ids[r.file] === r.id);
const entries = Object.entries(ids).filter(([file, id]) => id && !results.some(r => r.file === file));
let next = 0;
async function worker() {
  while (next < entries.length) {
    const [file, id] = entries[next++];
    await new Promise(resolve => setTimeout(resolve, 1500));
    try {
      const response = await fetch(`https://economy.roblox.com/v2/assets/${id}/details`, { signal: AbortSignal.timeout(12000) });
      const data = await response.json();
      const expected = file.replace(/\.png$/, '');
      const result = { file, id, status: response.status, name: data.Name || null, assetType: data.AssetTypeId || null };
      result.matches = response.ok && result.name === expected && result.assetType === 1;
      results.push(result);
      if (!result.matches) console.log(JSON.stringify(result));
    } catch (error) {
      results.push({ file, id, error: String(error), matches: false });
      console.log(file + ': ' + error);
    }
  }
}
Promise.all(Array.from({ length: 1 }, worker)).then(() => {
  results.sort((a, b) => a.file.localeCompare(b.file));
  fs.writeFileSync(previousFile, JSON.stringify(results, null, 2) + '\n');
  console.log(`${results.filter(r => r.matches).length}/${Object.values(ids).filter(Boolean).length} IDs have matching public asset names`);
});
