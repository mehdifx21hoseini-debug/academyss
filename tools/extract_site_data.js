/**
 * RAW extraction step: evaluate js/data.js in a stub browser environment and
 * dump window.SSAData verbatim to raw_sources/academy/.
 * The source file is never modified; the extract is never hand-edited.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
// The site moved to legacy-site/ when MENTORAI CORE landed. Both layouts are
// accepted, and whichever file is actually read is the one recorded as the
// source below — a provenance string that no longer points at a real file is
// worse than a broken build, because it fails silently.
const CANDIDATES = [
  path.join('legacy-site', 'js', 'data.js'),
  path.join('js', 'data.js'),
];
const rel = CANDIDATES.find((candidate) => fs.existsSync(path.join(root, candidate)));
if (!rel) {
  console.error('data.js پیدا نشد. مسیرهای بررسی‌شده: ' + CANDIDATES.join(', '));
  process.exit(1);
}
const src = path.join(root, rel);
const code = fs.readFileSync(src, 'utf8');

const sandbox = { window: {}, localStorage: { getItem: () => null } };
vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: rel });

const out = {
  extract_type: 'academy_site_data',
  source_file: rel,
  extracted_at: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
  extractor: 'tools/extract_site_data.js',
  note: 'Verbatim runtime value of window.SSAData. Raw source of truth for the Academy catalog.',
  data: sandbox.window.SSAData,
};

const dest = path.join(root, 'raw_sources', 'academy', 'site_data_v001.json');
fs.mkdirSync(path.dirname(dest), { recursive: true });
let changed = true;
if (fs.existsSync(dest)) {
  try {
    const prev = JSON.parse(fs.readFileSync(dest, 'utf8'));
    if (JSON.stringify(prev.data) === JSON.stringify(out.data)) {
      out.extracted_at = prev.extracted_at; // raw extract is unchanged: keep its timestamp
      changed = false;
    }
  } catch (e) { /* unreadable previous extract: rewrite it */ }
}
if (changed) fs.writeFileSync(dest, JSON.stringify(out, null, 2) + '\n', 'utf8');
console.log(changed ? 'wrote' : 'unchanged', path.relative(root, dest),
  '| podcasts:', out.data.podcasts.length,
  'books:', out.data.books.length,
  'testimonials:', out.data.testimonials.length);
