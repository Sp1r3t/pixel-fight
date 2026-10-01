const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '../../art/sprites/rework/new-skins');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
const packed = path.join(root, 'packed');
const referenced = new Set(Object.values(manifest.characters).flatMap(c => c.files).map(f => path.basename(f)));
const rejected = path.join(root, 'rejected-packed');
fs.mkdirSync(rejected, { recursive: true });
for (const name of process.argv.includes('--archive-orphans') ? fs.readdirSync(packed) : []) {
  if (!/^[a-z]+_[1-8]\.png$/.test(name) || referenced.has(name)) continue;
  const source = path.resolve(packed, name), destination = path.resolve(rejected, name);
  if (!source.startsWith(packed + path.sep) || !destination.startsWith(rejected + path.sep)) throw new Error('Invalid output path');
  if (fs.existsSync(destination)) throw new Error('Archive already exists: ' + name);
  fs.renameSync(source, destination);
}
const status = {
  date: '2026-10-01', status: process.argv[2] || 'in-progress',
  actors: Object.keys(manifest.characters).length,
  generatedPanels: Object.values(manifest.characters).reduce((n, c) => n + c.frameCount / 16, 0),
  completeDraftSets: Object.values(manifest.characters).filter(c => c.frameCount === 128).map(c => c.id),
  missingPanels: manifest.pending,
  cropReview: manifest.repairs,
  uploadedToRoblox: false,
};
if (status.status === 'blocked-usage-limit') {
  status.blocking = {
    code: 'usage_limit_reached',
    provider: 'built-in-image-generation',
    resetsAtEpochSeconds: 1790878509,
    resetsAtUtc: '2026-10-01T18:15:09Z',
    resetsAtMoscow: '2026-10-01T21:15:09+03:00',
    interruptedPanels: ['byte-recovery', 'morrow-motion'],
  };
}
fs.writeFileSync(path.join(root, 'generation-status.json'), JSON.stringify(status, null, 2));
console.log(JSON.stringify({ panels: status.generatedPanels, missing: status.missingPanels.length, completeDraftSets: status.completeDraftSets }));
