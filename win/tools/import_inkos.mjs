// import_inkos.mjs - 把 inkos 格式的书籍导入到 zhinai-novel-editor 的 novels.db
//
// 用法:
//   node import_inkos.mjs <inkos_book_dir> [--apply] [--backup] [--db <path>]
//
// 默认 dry-run: 只打印将要做的改动, 不写库.
// 加 --apply 才会写. 加 --backup 先备份 novels.db 到 novels.db.bak.<ts>.
//
// inkos 目录结构 (假设):
//   book.json          书的元数据
//   chapters/*.md      每章一个 md, 首行 "# 第N章 标题", 后面正文
//   chapters/index.json  每章元数据 (可选, 没用上)
//
// zhinai schema:
//   books(id, title, author, summary, platform, target_chapters, chapter_word_count, genres, created_at, updated_at)
//   chapters(id, book_id, order_index, title, content, updated_at)

import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync, existsSync, copyFileSync, statSync } from 'node:fs';
import { join, basename, resolve } from 'node:path';
import { argv, exit } from 'node:process';

const args = argv.slice(2);
const apply = args.includes('--apply');
const backup = args.includes('--backup');
const dbIdx = args.indexOf('--db');
const dbPath = dbIdx >= 0 ? args[dbIdx + 1] : null;
const srcDir = args.find(a => !a.startsWith('--') && (dbIdx < 0 || args[dbIdx + 1] !== a));

if (!srcDir) {
  console.error('用法: node import_inkos.mjs <inkos_book_dir> [--apply] [--backup] [--db <novels.db>]');
  exit(1);
}

const resolvedSrc = resolve(srcDir);
if (!existsSync(resolvedSrc)) {
  console.error('目录不存在: ' + resolvedSrc);
  exit(1);
}
const resolvedDb = dbPath ? resolve(dbPath) : join(process.env.APPDATA || process.env.HOME, 'ZhinaiNovelEditor', 'novels.db');

function log(msg) { console.log(msg); }
function warn(msg) { console.warn('⚠ ' + msg); }

const bookJsonPath = join(resolvedSrc, 'book.json');
if (!existsSync(bookJsonPath)) {
  console.error('找不到 book.json: ' + bookJsonPath);
  exit(1);
}

const book = JSON.parse(readFileSync(bookJsonPath, 'utf8'));
log('书名: ' + book.title);
log('平台: ' + book.platform);
log('目标章节: ' + book.targetChapters);
log('每章字数: ' + book.chapterWordCount);

// 读 chapters
const chaptersDir = join(resolvedSrc, 'chapters');
if (!existsSync(chaptersDir)) {
  console.error('找不到 chapters 目录: ' + chaptersDir);
  exit(1);
}
const files = readdirSync(chaptersDir)
  .filter(f => f.endsWith('.md') && !f.startsWith('.'))
  .sort();
log('找到 ' + files.length + ' 个章节 md');

const chapters = [];
// 中文数字 -> 阿拉伯
const CN_NUMS = { '零':0, '一':1, '二':2, '三':3, '四':4, '五':5, '六':6, '七':7, '八':8, '九':9, '十':10 };
function cnNumToInt(s) {
  if (!s) return 0;
  if (/^\d+$/.test(s)) return parseInt(s, 10);
  // 简单处理: 十X (十几) / X十 (几十) / X十Y (几十几)
  if (s === '十') return 10;
  if (s.length === 2 && s[0] === '十') return 10 + (CN_NUMS[s[1]] || 0);
  if (s.length === 2 && s[1] === '十') return (CN_NUMS[s[0]] || 0) * 10;
  if (s.length === 3 && s[1] === '十') return (CN_NUMS[s[0]] || 0) * 10 + (CN_NUMS[s[2]] || 0);
  // 单字
  if (s.length === 1) return CN_NUMS[s] || 0;
  return 0;
}

for (const f of files) {
  const raw = readFileSync(join(chaptersDir, f), 'utf8');
  // 优先从文件名提取章节号
  let no = 0;
  const fn = f.replace(/\.md$/i, '');
  const fnMatch = fn.match(/^(\d{1,4})[_\s]/);
  if (fnMatch) no = parseInt(fnMatch[1], 10);

  // 从首行提取标题 (支持阿拉伯/中文数字)
  const firstLine = raw.split(/\r?\n/, 1)[0];
  let m = firstLine.match(/^#\s*第\s*([\d零一二三四五六七八九十百千万]+)\s*章\s*(.*?)\s*$/);
  if (!m) m = firstLine.match(/^#\s*(?:第\s*)?([\d零一二三四五六七八九十百千万]+)\s*[.、:]\s*(.*?)\s*$/);
  if (!m) m = firstLine.match(/^#\s+(.*?)\s*$/);
  let title = '';
  if (m) {
    if (m[2] !== undefined) title = m[2].trim();
    else if (m[1] !== undefined) title = m[1].trim();
  }
  if (m && /^\d+$/.test(m[1])) {
    no = parseInt(m[1], 10);  // 首行覆盖文件名
  } else if (m && m[1]) {
    const cnNo = cnNumToInt(m[1]);
    if (cnNo > 0) no = cnNo;
  }
  // 标题缺失: 从文件名取 (去掉序号 + 下划线)
  if (!title) {
    const t = fn.replace(/^\d+[_\s]*/, '').replace(/_/g, ' ').trim();
    title = t || ('第' + no + '章');
  }
  // content: 去掉首行 + 可能的前导空行
  let body = raw.replace(/^[^\n]*\n/, '').replace(/^\s*\n/, '');
  chapters.push({ no, title, content: body, sourceFile: f });
}
chapters.sort((a, b) => (a.no || 0) - (b.no || 0));
// 给没章节号的按当前最大+1 补
let maxNo = 0;
for (const c of chapters) if (c.no > maxNo) maxNo = c.no;
for (const c of chapters) if (!c.no) c.no = ++maxNo;
log('解析章节:');
for (const c of chapters) log('  - 第' + c.no + '章 ' + c.title + ' (' + c.content.length + ' 字)');

if (!existsSync(resolvedDb)) {
  console.error('目标 DB 不存在, 请先启动一次 zhinai-novel-editor 让它建库: ' + resolvedDb);
  exit(1);
}
log('目标 DB: ' + resolvedDb);
log('模式: ' + (apply ? '⚡ APPLY (会写库)' : '👀 DRY-RUN (不写)'));

if (!apply) {
  log('');
  log('确认要导入就加 --apply 跑. 例:');
  log('  node import_inkos.mjs ' + JSON.stringify(srcDir) + ' --apply --backup');
  exit(0);
}

// 备份
if (backup) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const bak = resolvedDb + '.bak.' + ts;
  copyFileSync(resolvedDb, bak);
  log('已备份: ' + bak);
}

// 打开 DB
const db = new DatabaseSync(resolvedDb);
try {
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('BEGIN');

  const now = Math.floor(Date.now() / 1000);
  // 查同名书
  const existing = db.prepare('SELECT id FROM books WHERE title = ?').get(book.title);
  let bookId;
  if (existing) {
    bookId = existing.id;
    log('已存在同名书, id=' + bookId + ', 替换');
    db.prepare(`UPDATE books SET author=?, summary=?, platform=?, target_chapters=?, chapter_word_count=?, genres=?, updated_at=? WHERE id=?`)
      .run('', '', book.platform || '', book.targetChapters || 0, book.chapterWordCount || 0, book.genre || '', now, bookId);
    // 删旧章节
    db.prepare('DELETE FROM chapters WHERE book_id = ?').run(bookId);
  } else {
    const r = db.prepare(`INSERT INTO books(title, author, summary, platform, target_chapters, chapter_word_count, genres, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?)`)
      .run(book.title, '', '', book.platform || '', book.targetChapters || 0, book.chapterWordCount || 0, book.genre || '', now, now);
    bookId = Number(r.lastInsertRowid);
    log('新建书, id=' + bookId);
  }

  // 写章节
  const ins = db.prepare('INSERT INTO chapters(book_id, order_index, title, content, updated_at) VALUES(?,?,?,?,?)');
  for (const c of chapters) {
    const no = c.no || (chapters.indexOf(c) + 1);
    const r = ins.run(bookId, no - 1, c.title, c.content, now);
    log('  写章节 第' + no + '章 ' + c.title + ' -> id=' + r.lastInsertRowid);
  }

  db.exec('COMMIT');
  log('');
  log('✅ 完成. 作品: ' + book.title + ' (id=' + bookId + '), 共 ' + chapters.length + ' 章');
  log('打开 zhinai-novel-editor 顶栏作品下拉选这本.');
} catch (e) {
  db.exec('ROLLBACK');
  console.error('❌ 失败: ' + e.message);
  exit(1);
} finally {
  db.close();
}
