const fs = require('fs'), path = require('path');
const sharp = require('C:/Users/Tanshi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = path.resolve(__dirname, '../../art/sprites/rework/new-skins');
async function main() {
  const entries = fs.readFileSync(path.join(root, 'generation-log.ndjson'), 'utf8').trim().split(/\r?\n/).map(JSON.parse).slice(-25);
  const output = path.join(root, 'qa');
  fs.mkdirSync(output, { recursive: true });
  for (let page = 0; page < Math.ceil(entries.length / 4); page++) {
    const inputs = [];
    for (let j = 0; j < 4 && page * 4 + j < entries.length; j++) {
      const entry = entries[page * 4 + j], name = entry.id + '-' + entry.panel;
      const left = j % 2 * 640, top = Math.floor(j / 2) * 680;
      const input = await sharp(path.join(root, name + '.png')).resize(620, 620, { fit: 'inside', kernel: 'nearest' }).flatten({ background: '#182135' }).png().toBuffer();
      inputs.push({ input, left: left + 10, top: top + 45 });
      inputs.push({ input: Buffer.from('<svg width="640" height="40"><text x="10" y="28" fill="white" font-size="24">' + name + '</text></svg>'), left, top });
    }
    const destination = path.join(output, 'latest-panels-' + (page + 1) + '.png');
    await sharp({ create: { width: 1280, height: 1360, channels: 4, background: '#182135' } }).composite(inputs).png().toFile(destination);
    console.log(destination);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
