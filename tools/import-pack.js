// Build a ScrollGate quiz pack from a community question bank.
// Usage: node tools/import-pack.js <friberg|lemonsad> <outDir> [localRepoPath]
// Sources (no license files; for personal use, ask authors before redistributing):
//   friberg  https://github.com/friberg1991/korkort   726 q, 3 options, images
//   lemonsad https://github.com/Lemonsad222/korkort   ~200 q, 4 options, sv+en
// The source files are JS/TS; they are PARSED as literals here, never executed.
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const SOURCES = {
  friberg: { url: 'https://github.com/friberg1991/korkort', id: 'korkort-emil', title: 'Körkort (Emils frågor)' },
  lemonsad: { url: 'https://github.com/Lemonsad222/korkort', id: 'korkort-lemonsad', title: 'Körkortsprov' },
};

const [,, source, outDir, localPath] = process.argv;
if (!SOURCES[source] || !outDir) {
  console.error('usage: node tools/import-pack.js <friberg|lemonsad> <outDir> [localRepoPath]');
  process.exit(2);
}
const src = SOURCES[source];

let repo = localPath;
if (!repo) {
  repo = fs.mkdtempSync(path.join(os.tmpdir(), 'tq-import-'));
  console.log('cloning', src.url, '->', repo);
  execFileSync('git', ['clone', '--depth', '1', '-q', src.url, repo], { stdio: 'inherit' });
}

const packDir = path.join(outDir, src.id);
fs.mkdirSync(packDir, { recursive: true });

const items = source === 'friberg' ? importFriberg(repo, packDir) : importLemonsad(repo);

const manifest = {
  id: src.id, title: src.title, kind: 'quiz', items: 'items.json',
  strategy: 'weighted-wrong', unlock: 'correct', source: src.url,
};
fs.writeFileSync(path.join(packDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
fs.writeFileSync(path.join(packDir, 'items.json'), JSON.stringify(items, null, 1) + '\n');
console.log(`wrote ${items.length} items to ${packDir} (${items.filter(i => i.image).length} with images)`);

// ---------------------------------------------------------------------------
// Minimal JS literal parser: objects, arrays, strings ('/"/`), numbers, true/false/null.
// Unquoted keys allowed. Comments skipped. Anything else throws.
function parseLiteral(text, pos = 0) {
  let i = pos;
  const err = (m) => { throw new Error(`${m} at ${i}: ${text.slice(i, i + 40)}`); };
  const ws = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('//', i)) { while (i < text.length && text[i] !== '\n') i++; continue; }
      if (text.startsWith('/*', i)) { i = text.indexOf('*/', i) + 2; continue; }
      break;
    }
  };
  const str = () => {
    const quote = text[i++]; let out = '';
    while (i < text.length && text[i] !== quote) {
      if (text[i] === '\\') {
        i++; const c = text[i++];
        out += { n: '\n', t: '\t', r: '\r', '0': '\0' }[c] ?? (c === 'u' ? String.fromCharCode(parseInt(text.substr(i, 4), 16)) : c);
        if (c === 'u') i += 4;
      } else out += text[i++];
    }
    if (text[i] !== quote) err('unterminated string');
    i++; return out;
  };
  const value = () => {
    ws();
    const c = text[i];
    if (c === '{') {
      i++; const o = {};
      for (;;) {
        ws(); if (text[i] === '}') { i++; return o; }
        let key;
        if (text[i] === '"' || text[i] === "'") key = str();
        else { const m = /^[A-Za-z_$][\w$]*/.exec(text.slice(i)); if (!m) err('bad key'); key = m[0]; i += key.length; }
        ws(); if (text[i] !== ':') err('expected :'); i++;
        o[key] = value();
        ws(); if (text[i] === ',') i++;
      }
    }
    if (c === '[') {
      i++; const a = [];
      for (;;) {
        ws(); if (text[i] === ']') { i++; return a; }
        a.push(value());
        ws(); if (text[i] === ',') i++;
      }
    }
    if (c === '"' || c === "'" || c === '`') return str();
    const m = /^(-?\d+(\.\d+)?|true|false|null)/.exec(text.slice(i));
    if (!m) err('unexpected token');
    i += m[0].length;
    return m[0] === 'true' ? true : m[0] === 'false' ? false : m[0] === 'null' ? null : Number(m[0]);
  };
  const v = value();
  return { value: v, end: i };
}

// --- friberg1991/korkort: data.js has `window.KORKORT = { chapters: [...], questions: [[chapter, q, [answers], explain, imageCode], ...] }`
// First answer is the correct one (the app shuffles). Images: signs/<code>.png or situations/<code>.jpg.
function importFriberg(repo, packDir) {
  const js = fs.readFileSync(path.join(repo, 'data.js'), 'utf8');
  const start = js.indexOf('{', js.indexOf('window.KORKORT'));
  const { value: data } = parseLiteral(js, start);
  const chapterTitle = Object.fromEntries(data.chapters.map(c => [c[0], c[1]]));
  const out = [];
  data.questions.forEach((row, idx) => {
    const [ch, q, answers, explain, img] = row;
    if (!q || !Array.isArray(answers) || answers.length < 2) return;
    const item = { id: `${ch}-${idx}`, category: chapterTitle[ch] || ch, q, answers: answers.slice(), correct: 0 };
    if (explain) item.explain = explain;
    if (img) {
      for (const [dir, ext] of [['signs', 'png'], ['situations', 'jpg'], ['situations', 'png']]) {
        const srcFile = path.join(repo, dir, `${img}.${ext}`);
        if (fs.existsSync(srcFile)) {
          const rel = path.join(dir, `${img}.${ext}`);
          fs.mkdirSync(path.join(packDir, dir), { recursive: true });
          fs.copyFileSync(srcFile, path.join(packDir, rel));
          item.image = rel;
          break;
        }
      }
    }
    out.push(item);
  });
  return out;
}

// --- Lemonsad222/korkort: src/data/<cat>.ts has `export const X: Question[] = [ {...}, ... ]`
function importLemonsad(repo) {
  const dir = path.join(repo, 'src', 'data');
  const out = [];
  for (const file of ['regler', 'sakerhet', 'fordon', 'miljo', 'person']) {
    const ts = fs.readFileSync(path.join(dir, `${file}.ts`), 'utf8');
    const m = /export const \w+: Question\[\] =/.exec(ts);
    if (!m) continue;
    const start = ts.indexOf('[', m.index + m[0].length);
    const { value: arr } = parseLiteral(ts, start);
    for (const qq of arr) {
      if (!qq.sv || !Array.isArray(qq.sv.a)) continue;
      const item = { id: qq.id, category: qq.cat, q: qq.sv.q, answers: qq.sv.a, correct: qq.correct };
      if (qq.sv.e) item.explain = qq.sv.e;
      out.push(item);
    }
  }
  return out;
}
