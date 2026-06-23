// render_all.mjs — Render semua diagram .mmd ke PNG
// Jalankan: node render_all.mjs

import { execSync } from 'child_process';
import { readdirSync, existsSync, mkdirSync } from 'fs';
import { join, basename, extname } from 'path';

const DIAGRAM_DIR = '.';
const OUT_DIR = './png_output';
const CONFIG = './mermaid.config.json';
const MMDC = 'C:\\Users\\HP\\AppData\\Roaming\\npm\\mmdc.cmd';
const WIDTH = 1600;
const SCALE = 2;  // retina quality

if (!existsSync(OUT_DIR)) mkdirSync(OUT_DIR, { recursive: true });

const files = readdirSync(DIAGRAM_DIR)
  .filter(f => extname(f) === '.mmd')
  .sort();

console.log(`\n🎨 Rendering ${files.length} diagram(s) to PNG...\n`);
console.log('─'.repeat(58));

let success = 0;
let failed  = 0;

for (const file of files) {
  const inPath  = join(DIAGRAM_DIR, file);
  const outName = basename(file, '.mmd') + '.png';
  const outPath = join(OUT_DIR, outName);

  process.stdout.write(`  ▶ ${file.padEnd(32)}`);
  try {
    execSync(
      `"${MMDC}" -i "${inPath}" -o "${outPath}" -c "${CONFIG}" -w ${WIDTH} -s ${SCALE} --backgroundColor white`,
      { stdio: 'pipe', timeout: 90000 }
    );
    console.log(`✅  →  ${outName}`);
    success++;
  } catch (err) {
    const msg = (err.stderr?.toString() || err.stdout?.toString() || err.message).trim();
    console.log(`❌  GAGAL`);
    console.log(`     ${msg.split('\n')[0]}`);
    failed++;
  }
}

console.log('─'.repeat(58));
console.log(`\n✅ Berhasil : ${success} diagram`);
if (failed > 0) console.log(`❌ Gagal    : ${failed} diagram`);
console.log(`\n📁 Output tersimpan di: ${OUT_DIR}\n`);
