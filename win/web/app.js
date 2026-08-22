// app.js - 织奈编辑器 前端主逻辑
// 通信: WebView2 postMessage 走 C++ 桥 (callNative),
//       浏览器直连 fallback 走 REST (callRest).

const isWebView = !!(window.chrome && window.chrome.webview);

async function callNative(method, params = {}) {
  const id = String(Date.now()) + Math.random().toString(36).slice(2, 8);
  if (isWebView) {
    return new Promise((resolve, reject) => {
      const onMsg = (e) => {
        try {
          const data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
          if (data && data.id === id) {
            window.chrome.webview.removeEventListener('message', onMsg);
            if (data.ok) resolve(data.data);
            else reject(new Error(data.error || 'native call failed'));
          }
        } catch (_) {}
      };
      window.chrome.webview.addEventListener('message', onMsg);
      window.chrome.webview.postMessage(JSON.stringify({ id, method, params }));
      setTimeout(() => {
        window.chrome.webview.removeEventListener('message', onMsg);
        reject(new Error('native call timeout'));
      }, 60000);
    });
  }
  return callRest(method, params);
}

async function callRest(method, params) {
  const map = {
    'books.list':           ['GET',  '/api/books'],
    'books.create':         ['POST', '/api/books', params],
    'books.update':         ['PUT',  '/api/books/' + params.id, params],
    'books.delete':         ['DELETE', '/api/books/' + params.id],
    'chapters.list':        ['GET',  '/api/books/' + params.bookId + '/chapters'],
    'chapters.create':      ['POST', '/api/books/' + params.bookId + '/chapters', { title: params.title, orderIndex: params.orderIndex }],
    'chapters.saveContent': ['PUT',  '/api/chapters/' + params.id + '/content', { content: params.content }],
    'chapters.rename':      ['PUT',  '/api/chapters/' + params.id + '/title', { title: params.title }],
    'chapters.delete':      ['DELETE', '/api/chapters/' + params.id],
    'lore.list':            ['GET',  '/api/lore'],
    'lore.create':          ['POST', '/api/lore', params],
    'lore.update':          ['PUT',  '/api/lore/' + params.id, params],
    'lore.delete':          ['DELETE', '/api/lore/' + params.id],
    'agents.list':          ['GET',  '/api/agents'],
    'agents.save':          ['POST', '/api/agents', params],
    'agents.delete':        ['DELETE', '/api/agents/' + params.id],
    'conversations.list':   ['GET',  '/api/conversations'],
    'conversations.create': ['POST', '/api/conversations', params],
    'conversations.delete': ['DELETE', '/api/conversations/' + params.id],
    'conversations.messages': ['GET', '/api/conversations/' + params.id + '/messages'],
    'conversations.appendMessage': ['POST', '/api/conversations/' + params.convId + '/messages', { role: params.role, content: params.content }],
    'llm.chat':             ['POST', '/api/llm/chat', params],
    'llm.test':             ['POST', '/api/llm/test', params],
    'skills.list':          ['GET',  '/api/skills'],
    'skills.read':          ['GET',  '/api/skills/' + encodeURIComponent(params.name)],
    'vectors.import':       ['POST', '/api/vectors/import', params],
    'vectors.search':       ['POST', '/api/vectors/search', params],
    'vectors.stats':        ['GET',  '/api/vectors/stats'],
    'config.get':           ['GET',  '/api/config'],
    'config.set':           ['PUT',  '/api/config', params],
    'skills.catalog':       ['GET',  '/api/skills/catalog'],
    'search.query':         ['GET',  '/api/search?q=' + encodeURIComponent(params.q)],
    'system.openDataDir':   ['POST', '/api/system/openDataDir'],
  };
  const spec = map[method];
  if (!spec) throw new Error('unknown method: ' + method);
  const [verb, path, body] = spec;
  const opts = { method: verb, headers: {} };
  if (body) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error('http ' + r.status);
  return await r.json();
}

const api = new Proxy({}, { get: (_, method) => (params) => callNative(method, params) });

// ---- 状态 ----
const State = {
  tab: 'chapters',           // 当前活动栏 tab
  currentBookId: null,
  chapterId: null,
  saveTimer: null,
  convId: null,
  loreId: null,
  bgOpacity: 0.64,
  bookTitle: '选择作品',
  skillCatalog: [],          // 后端 /api/skills/catalog 缓存
};

// ---- Agent 头像映射 (跟 macOS 4 个 Agent 对应) ----
const AGENT_AVATARS = {
  'creative-assistant': 'img/agents/creative-assistant.png',
  'strict-editor':      'img/agents/strict-editor.png',
  'web-fiction-writer': 'img/agents/web-fiction-writer.png',
  'world-builder':      'img/agents/world-builder.png',
};
const DEFAULT_AVATAR = 'img/agents/world-builder.png';
function avatarFor(agent) {
  if (!agent) return DEFAULT_AVATAR;
  // 优先按 skill 字段匹配, 没有就用名字 hash 选一个
  if (agent.skill && AGENT_AVATARS[agent.skill]) return AGENT_AVATARS[agent.skill];
  const keys = Object.keys(AGENT_AVATARS);
  let h = 0; for (const c of (agent.name || '')) h = (h * 31 + c.charCodeAt(0)) & 0xffff;
  return AGENT_AVATARS[keys[h % keys.length]] || DEFAULT_AVATAR;
}

// ---- 工具 ----
function $(sel, root=document) { return root.querySelector(sel); }
function $$(sel, root=document) { return Array.from(root.querySelectorAll(sel)); }
function escapeHtml(s) {
  return (s || '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
let toastTimer = null;
function showToast(msg, isError) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.className = isError ? 'error' : '';
  t.style.display = 'block';
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.display = 'none'; }, 1800);
}

// ---- 顶栏菜单 (作品下拉 / AI 工具) ----
function setupToolbar() {
  // 下拉菜单切换
  $$('.tb-menu').forEach(menu => {
    const trigger = menu.querySelector('[data-trigger]');
    trigger.addEventListener('click', (e) => {
      e.stopPropagation();
      $$('.tb-menu').forEach(m => { if (m !== menu) m.classList.remove('open'); });
      menu.classList.toggle('open');
    });
  });
  document.addEventListener('click', () => $$('.tb-menu').forEach(m => m.classList.remove('open')));

  // 作品下拉
  $('#menu-book').addEventListener('click', async (e) => {
    const item = e.target.closest('.menu-item');
    if (!item) return;
    const act = item.dataset.act;
    if (act === 'select-none') { State.currentBookId = null; updateBookTitle(); switchTab('chapters'); }
    else if (act === 'new') { await createBookFlow(); }
    else if (act === 'import') { showToast('导入待实现', true); }
    else if (act === 'export') { showToast('导出待实现', true); }
    else if (act === 'delete' && State.currentBookId) {
      if (confirm('删除当前作品?')) { await api.books.delete({ id: State.currentBookId }); State.currentBookId = null; updateBookTitle(); }
    }
  });

  // AI 工具菜单 - 启动时由 renderAIMenu() 从 catalog 填充
  $('#menu-ai').addEventListener('click', async (e) => {
    const item = e.target.closest('.menu-item');
    if (!item) return;
    const skillId = item.dataset.skill;
    if (skillId) await aiRunSkill(skillId);
  });

  // 顶栏按钮
  $('#newChapterBtn').addEventListener('click', createChapterFlow);
  $('#newConvBtn').addEventListener('click', createConvFlow);
  $('#agentBtn').addEventListener('click', () => switchTab('agents'));
  $('#settingsBtn').addEventListener('click', () => switchTab('settings'));
  $('#bgOpacityBtn').addEventListener('click', () => switchTab('settings'));
}

function updateBookTitle() {
  const el = $('[data-bind="currentBookTitle"]');
  if (el) el.textContent = State.bookTitle;
}

// ---- 顶栏快捷 ----
async function createChapterFlow() {
  if (!State.currentBookId) { showToast('先选作品', true); return; }
  const title = prompt('章节标题', '新章节');
  if (!title) return;
  const r = await api.chapters.create({ bookId: State.currentBookId, title });
  State.chapterId = r.id;
  await loadSidebar(); loadMain();
  showToast('已创建');
}
async function createConvFlow() {
  const r = await api.conversations.create({ title: '新对话 ' + new Date().toLocaleString(), agentId: 0, bookId: State.currentBookId || 0 });
  State.convId = r.id;
  if (State.tab !== 'chat') switchTab('chat');
  else { loadSidebar(); loadMain(); }
}
async function createBookFlow() {
  // 弹完整表单 (跟 macOS NewBookSheet 对齐)
  showBookModal(null);
}
async function editBookFlow(book) {
  showBookModal(book);
}

function showBookModal(book) {
  const isEdit = !!book;
  const m = book || { title: '', author: '', summary: '', platform: 'other', targetChapters: 0, chapterWordCount: 3000, genres: '' };
  let modal = document.getElementById('bookModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'bookModal';
    modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.4);backdrop-filter:blur(4px);display:flex;align-items:center;justify-content:center;z-index:9999';
    document.body.appendChild(modal);
  }
  modal.innerHTML = `
    <div style="background:#fff;border-radius:12px;max-width:520px;width:90%;display:flex;flex-direction:column;box-shadow:0 20px 60px rgba(0,0,0,0.25);overflow:hidden">
      <div style="padding:14px 18px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:8px">
        <strong style="font-size:14px">${isEdit ? '编辑作品' : '新建作品'}</strong>
        <span style="flex:1"></span>
        <button class="btn-icon" id="bookModalClose">✕</button>
      </div>
      <div style="padding:18px 22px;display:flex;flex-direction:column;gap:12px">
        <label class="field"><span>书名 <span style="color:#b91c1c">*</span></span>
          <input id="bmTitle" placeholder="例如: 雾城来信" value="${escapeHtml(m.title)}" />
        </label>
        <label class="field"><span>简介 (可选)</span>
          <textarea id="bmSummary" rows="3" style="font:13px/1.6 ui-serif,'Songti SC',serif;min-height:60px;resize:vertical">${escapeHtml(m.summary || '')}</textarea>
        </label>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <label class="field"><span>作者</span><input id="bmAuthor" value="${escapeHtml(m.author || '')}" placeholder="可选" /></label>
          <label class="field"><span>题材</span><input id="bmGenre" value="${escapeHtml(m.genres || '')}" placeholder="例如: 玄幻" /></label>
        </div>
        <label class="field"><span>目标平台</span>
          <select id="bmPlatform">
            <option value="tomato">番茄</option>
            <option value="qidian">起点</option>
            <option value="feilu">飞卢</option>
            <option value="other">其他 / 未定</option>
          </select>
        </label>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <label class="field"><span>目标章节</span>
            <input type="number" id="bmTargetCh" min="0" value="${m.targetChapters || 0}" />
          </label>
          <label class="field"><span>每章字数</span>
            <input type="number" id="bmChapterWords" min="0" step="500" value="${m.chapterWordCount || 3000}" />
          </label>
        </div>
      </div>
      <div style="padding:12px 18px;border-top:1px solid var(--border);display:flex;gap:8px;justify-content:flex-end">
        <button class="btn-secondary" id="bookModalCancel">取消</button>
        <button class="btn-primary" id="bookModalSave">${isEdit ? '保存' : '创建'}</button>
      </div>
    </div>
  `;
  modal.style.display = 'flex';
  $('#bmPlatform').value = m.platform || 'other';
  const close = () => { modal.style.display = 'none'; };
  modal.querySelector('#bookModalClose').onclick = close;
  modal.querySelector('#bookModalCancel').onclick = close;
  modal.querySelector('#bookModalSave').onclick = async () => {
    const title = $('#bmTitle').value.trim();
    if (!title) { showToast('书名必填', true); return; }
    const payload = {
      title, author: $('#bmAuthor').value.trim(), summary: $('#bmSummary').value.trim(),
      platform: $('#bmPlatform').value, genres: $('#bmGenre').value.trim(),
      targetChapters: parseInt($('#bmTargetCh').value, 10) || 0,
      chapterWordCount: parseInt($('#bmChapterWords').value, 10) || 0,
    };
    if (isEdit) await api.books.update({ id: m.id, ...payload });
    else {
      const r = await api.books.create(payload);
      State.currentBookId = r.id; State.bookTitle = title; updateBookTitle();
    }
    close();
    showToast(isEdit ? '已保存' : '已创建');
    if (State.tab === 'books') renderBooks();
    else switchTab('books');
  };
  setTimeout(() => $('#bmTitle').focus(), 30);
}

// ---- 视图切换 ----
const TAB_TITLES = {
  books: '作品', chapters: '章节', lore: '设定库', search: '搜索', chat: '对话',
  agents: 'Agent', vectors: '向量库', skills: '技能', settings: '设置',
};
function switchTab(tab) {
  State.tab = tab;
  $$('.ab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
  $('#sideTitle').textContent = TAB_TITLES[tab] || '';
  loadSidebar();
  loadMain();
}

function loadSidebar() {
  const sb = $('#sidebar');
  sb.innerHTML = '';
  if (State.tab === 'books') return renderBooksSidebar(sb);
  if (State.tab === 'chapters') return renderChaptersSidebar(sb);
  if (State.tab === 'lore') return renderLoreSidebar(sb);
  if (State.tab === 'search') return;  // 搜索无侧栏
  if (State.tab === 'chat') return renderChatSidebar(sb);
  if (State.tab === 'agents') return renderAgentsSidebar(sb);
  if (State.tab === 'vectors') return renderVectorsSidebar(sb);
  if (State.tab === 'skills') return renderSkillsSidebar(sb);
  if (State.tab === 'settings') return;  // 设置无侧栏
}

function loadMain() {
  const main = $('#main');
  main.innerHTML = '';
  const tpl = document.getElementById('tpl-' + State.tab);
  if (tpl) main.appendChild(tpl.content.cloneNode(true));
  if (State.tab === 'books') return renderBooks();
  if (State.tab === 'chapters') return renderChapters();
  if (State.tab === 'lore') return renderLore();
  if (State.tab === 'search') return renderSearch();
  if (State.tab === 'chat') return renderChat();
  if (State.tab === 'agents') return renderAgents();
  if (State.tab === 'vectors') return renderVectors();
  if (State.tab === 'skills') return renderSkills();
  if (State.tab === 'settings') return renderSettings();
}

document.getElementById('activityBar').addEventListener('click', (e) => {
  const b = e.target.closest('.ab-btn');
  if (b && b.dataset.tab) switchTab(b.dataset.tab);
});

// ---- Books ----
async function renderBooksSidebar(sb) {
  sb.innerHTML = '<div style="padding:8px;color:var(--text-soft);font-size:12px">作品列表会显示在主区</div>';
}
async function renderBooks() {
  const list = await api.books.list();
  const wrap = $('#bookList');
  wrap.innerHTML = '';
  for (const b of (list || [])) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `
      <div style="font-size:15px;font-weight:600">${escapeHtml(b.title)}</div>
      <div style="font-size:11.5px;color:var(--text-soft);margin-top:2px">${escapeHtml(b.author || '未署名')}${b.platform && b.platform !== 'other' ? ' · ' + platformLabel(b.platform) : ''}${b.genres ? ' · ' + escapeHtml(b.genres) : ''}</div>
      <div style="font-size:12.5px;color:var(--text-soft);margin-top:8px;line-height:1.5;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden">${escapeHtml(b.summary || '—')}</div>
      ${b.targetChapters ? `<div style="font-size:11.5px;color:var(--text-faint);margin-top:6px">目标 ${b.targetChapters} 章 · 每章 ${b.chapterWordCount || '?'} 字</div>` : ''}
      <div style="display:flex;gap:8px;margin-top:10px;justify-content:flex-end">
        <button class="btn-link" data-act="open">打开</button>
        <button class="btn-link" data-act="edit">编辑</button>
        <button class="btn-link danger" data-act="del">删除</button>
      </div>
    `;
    el.querySelector('[data-act="open"]').addEventListener('click', (e) => {
      e.stopPropagation();
      State.currentBookId = b.id; State.bookTitle = b.title; updateBookTitle();
      switchTab('chapters');
    });
    el.querySelector('[data-act="edit"]').addEventListener('click', (e) => { e.stopPropagation(); editBookFlow(b); });
    el.querySelector('[data-act="del"]').addEventListener('click', async (e) => {
      e.stopPropagation();
      if (!confirm('删除 "' + b.title + '"?')) return;
      await api.books.delete({ id: b.id });
      renderBooks();
    });
    wrap.appendChild(el);
  }
  $('#newBook').addEventListener('click', createBookFlow);
}

// ---- Chapters ----
async function renderChaptersSidebar(sb) {
  // 顶栏已经做了"作品下拉" - 这里直接列章节
  if (!State.currentBookId) {
    sb.innerHTML = '<div style="padding:14px;color:var(--text-soft);font-size:12.5px">先在顶栏选择一本作品</div>';
    return;
  }
  const list = await api.chapters.list({ bookId: State.currentBookId });
  list.forEach((c, i) => {
    const el = document.createElement('div');
    el.className = 'list-item' + (State.chapterId === c.id ? ' active' : '');
    el.draggable = true;
    el.dataset.id = c.id;
    el.innerHTML = `<span class="num">${i + 1}</span><span class="title">${escapeHtml(c.title)}</span>
      <span class="actions"><button class="btn-icon" data-act="del" title="删除">✕</button></span>`;
    el.addEventListener('click', () => openChapter(c.id));
    el.querySelector('[data-act="del"]').addEventListener('click', async (e) => {
      e.stopPropagation();
      if (!confirm('删除章节 "' + c.title + '"?')) return;
      await api.chapters.delete({ id: c.id });
      if (State.chapterId === c.id) State.chapterId = null;
      loadSidebar(); loadMain();
    });
    el.addEventListener('dragstart', (e) => { e.dataTransfer.setData('text/plain', c.id); });
    el.addEventListener('dragover', (e) => { e.preventDefault(); el.classList.add('drop-target'); });
    el.addEventListener('dragleave', () => el.classList.remove('drop-target'));
    el.addEventListener('drop', async (e) => {
      e.preventDefault(); el.classList.remove('drop-target');
      const srcId = parseInt(e.dataTransfer.getData('text/plain'));
      const dstId = c.id;
      if (srcId === dstId) return;
      const ids = list.map(x => x.id);
      const srcIdx = ids.indexOf(srcId); const dstIdx = ids.indexOf(dstId);
      if (srcIdx < 0 || dstIdx < 0) return;
      ids.splice(srcIdx, 1); ids.splice(dstIdx, 0, srcId);
      await fetch('/api/books/' + State.currentBookId + '/chapters/reorder', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids })
      });
      loadSidebar();
    });
    sb.appendChild(el);
  });
  // 末尾 + 新建
  const add = document.createElement('div');
  add.className = 'list-item';
  add.style.color = 'var(--text-soft)';
  add.innerHTML = '<span class="num">＋</span><span class="title">新建章节…</span>';
  add.addEventListener('click', createChapterFlow);
  sb.appendChild(add);
}

async function renderChapters() {
  if (!State.currentBookId) {
    $('#main').innerHTML = '<div style="padding:60px 20px;text-align:center;color:var(--text-soft)">请在顶栏选一本作品</div>';
    return;
  }
  const title = $('#chapterTitle'), editor = $('#editor');
  // 加载上次选中的章节
  if (State.chapterId) {
    const r = await fetch('/api/chapters/' + State.chapterId);
    if (r.ok) {
      const c = await r.json();
      title.value = c.title; editor.value = c.content || '';
      updateWordCount();
    }
  }
  title.addEventListener('input', () => scheduleSave());
  editor.addEventListener('input', () => { updateWordCount(); scheduleSave(); });
  $('#saveChapterBtn').addEventListener('click', () => saveChapter(true));
  $('#aiContinueBtn').addEventListener('click', () => aiContinue());
  $('#aiPolishBtn').addEventListener('click', () => aiPolish());
}

async function openChapter(id) {
  const r = await fetch('/api/chapters/' + id);
  if (!r.ok) return;
  const c = await r.json();
  State.chapterId = c.id;
  $$('#sidebar .list-item').forEach(el => el.classList.toggle('active', parseInt(el.dataset.id) === c.id));
  const title = $('#chapterTitle'), editor = $('#editor');
  if (title && editor) { title.value = c.title; editor.value = c.content || ''; updateWordCount(); }
  // 设定命中
  const lore = await api.lore.list();
  const hits = (lore || []).filter(e => e.keywords && e.keywords.split(/[,，]/).some(k => k.trim() && c.content && c.content.includes(k.trim())));
  const hint = $('#loreHint');
  if (hint) hint.textContent = hits.length ? '设定命中: ' + hits.map(h => h.name).join('、') : '';
}

function updateWordCount() {
  const editor = $('#editor'); const wc = $('#wordCount');
  if (!editor || !wc) return;
  const n = (editor.value || '').replace(/\s+/g, '').length;
  wc.textContent = n + ' 字';
}

function scheduleSave() {
  const dot = $('#saveDot'), text = $('#saveText');
  if (dot) dot.classList.remove('saved');
  if (text) text.textContent = '编辑中…';
  if (State.saveTimer) clearTimeout(State.saveTimer);
  State.saveTimer = setTimeout(() => saveChapter(false), 800);
}

async function saveChapter(showMsg) {
  if (!State.chapterId) return;
  const title = $('#chapterTitle').value;
  const content = $('#editor').value;
  await api.chapters.rename({ id: State.chapterId, title });
  await api.chapters.saveContent({ id: State.chapterId, content });
  const dot = $('#saveDot'), text = $('#saveText');
  if (dot) dot.classList.add('saved');
  if (text) text.textContent = '已保存 ' + new Date().toLocaleTimeString();
  if (showMsg) showToast('已保存');
  loadSidebar();
}

async function aiContinue() {
  await aiRunSkill('continue');
}
async function aiPolish() {
  await aiRunSkill('polish');
}

// ---- AI 通用 skill 调用 (跟 macOS performSend 对齐) ----
function findSkill(id) {
  return State.skillCatalog.find(s => s.id === id);
}

async function aiRunSkill(skillId) {
  const skill = findSkill(skillId);
  if (!skill) { showToast('未找到 skill: ' + skillId, true); return; }

  // 校验: 续写/润色/scene/continue 要有章节
  const needChapter = ['continue', 'polish', 'scene'].includes(skillId);
  if (needChapter && !State.chapterId) { showToast('先选章节', true); return; }

  // 收集输入
  const editor = $('#editor'), title = $('#chapterTitle');
  const targetText = (editor && editor.value) || '';
  const chapterTitle = (title && title.value) || '';

  // 命中设定
  const lore = (await api.lore.list()) || [];
  const hits = lore.filter(e => e.keywords && e.keywords.split(/[,，]/).some(k => k.trim() && targetText.includes(k.trim())));

  // 构造 user message (按 skill 类型)
  let userText = '';
  if (skillId === 'continue') userText = `续写《${chapterTitle}》正文, 直接接续, 不要复述.`;
  else if (skillId === 'polish') userText = `润色《${chapterTitle}》:\n\n${targetText}`;
  else if (skillId === 'scene') userText = '创作一段场景正文.';
  else if (skillId === 'outline') userText = '为当前作品生成完整分章大纲.';
  else if (skillId === 'character') userText = '设计一个人物 (名字/性格/背景由你定).';
  else if (skillId === 'worldbuilding') userText = '完善力量体系/地理/势力/历史.';
  else if (skillId === 'location') userText = '设计一个关键地点.';
  else if (skillId === 'faction') userText = '设计一个组织势力.';
  else if (skillId === 'item') userText = '设计一个关键物品/神器.';
  else if (skillId === 'consistency') userText = '检查前文与设定的一致性.';
  else if (skillId === 'inspire') userText = '围绕当前作品做灵感脑暴.';

  // loading 弹窗
  showSkillModal(skill, '⏳ 生成中…', '', false);

  // 流式调用: 边收边显示
  let text = '';
  let errored = false;
  try {
    const resp = await fetch('/api/llm/chat/stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        skillId,
        messages: [{ role: 'user', content: userText }],
        temperature: 0.7,
        loreHits: hits.map(h => ({ name: h.name, content: h.content })),
      }),
    });
    if (!resp.ok || !resp.body) {
      throw new Error('http ' + resp.status);
    }
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value, { stream: true });
      for (const evt of chunk.split('\n\n')) {
        if (!evt.startsWith('data: ')) continue;
        let data;
        try { data = JSON.parse(evt.slice(6)); } catch { continue; }
        if (data.error) {
          showSkillModal(skill, '✗ 调用失败: ' + data.error, text, true);
          errored = true;
        } else if (data.delta) {
          text += data.delta;
          updateSkillModalText(text);
        } else if (data.done) {
          // 完成
        }
      }
    }
  } catch (e) {
    showSkillModal(skill, '✗ 调用失败: ' + e.message, text, true);
    errored = true;
  }

  if (errored) return;
  if (!text) {
    showSkillModal(skill, '⚠ 无内容返回', '请检查 API 配置或换个模型试试.', true);
    return;
  }
  // 根据 skill 类型显示不同操作按钮
  const actions = skillActionsFor(skillId, text);
  showSkillModalActions(actions);
}

function skillActionsFor(skillId, text) {
  // 不同 skill 给出"应用到"按钮
  if (skillId === 'continue') return [{ label: '追加到当前章节', act: 'appendChapter', text }];
  if (skillId === 'polish')   return [{ label: '替换当前章节', act: 'replaceChapter', text }];
  if (skillId === 'scene')    return [{ label: '追加到当前章节', act: 'appendChapter', text }];
  if (skillId === 'character' || skillId === 'location' || skillId === 'faction' || skillId === 'item' || skillId === 'worldbuilding') {
    return [{ label: '加到设定库', act: 'addLore', text, skillId }];
  }
  return [{ label: '复制到剪贴板', act: 'copy', text }];
}

function applyBackground(url, mime) {
  // 替换 body::before 为图片 / 视频
  document.body.style.setProperty('--bg-url', url ? `url('${url}')` : "url('img/DefaultBackground.jpeg')");
  // 视频要用 video 标签代替 background-image, 所以用一层覆盖 div
  let vid = document.getElementById('bgVideo');
  if (mime && mime.startsWith('video/')) {
    if (!vid) {
      vid = document.createElement('video');
      vid.id = 'bgVideo';
      vid.autoplay = true;
      vid.loop = true;
      vid.muted = true;
      vid.playsInline = true;
      vid.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;object-fit:cover;z-index:-3;pointer-events:none';
      document.body.prepend(vid);
    }
    if (url) vid.src = url;
  } else if (vid) {
    vid.remove();
  }
  // 缩略图
  const prev = document.getElementById('bgPreview');
  if (prev) {
    if (mime && mime.startsWith('video/')) {
      prev.innerHTML = '<span>已选视频背景</span>';
      prev.style.background = 'rgba(0,128,0,0.1)';
    } else if (url && url.includes('/api/background')) {
      prev.innerHTML = '<img src="' + url + '" style="width:100%;height:100%;object-fit:cover">';
    } else {
      prev.innerHTML = '<span>默认</span>';
      prev.style.background = 'rgba(0,0,0,0.05)';
    }
  }
}

function showSkillModal(skill, title, body, isError) {
  let modal = document.getElementById('skillModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'skillModal';
    modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.4);backdrop-filter:blur(4px);display:flex;align-items:center;justify-content:center;z-index:9999';
    document.body.appendChild(modal);
  }
  modal.innerHTML = `
    <div style="background:#fff;border-radius:12px;max-width:720px;width:90%;max-height:80vh;display:flex;flex-direction:column;box-shadow:0 20px 60px rgba(0,0,0,0.25);overflow:hidden">
      <div style="padding:14px 18px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:10px">
        <span style="font-size:18px">${skill.icon || '✨'}</span>
        <strong style="font-size:14px">${escapeHtml(skill.name || title)}</strong>
        <span style="flex:1"></span>
        <button class="btn-icon" id="skillModalClose">✕</button>
      </div>
      <div id="skillModalBody" style="padding:16px 20px;overflow:auto;flex:1;white-space:pre-wrap;font:13px/1.7 ui-monospace,Menlo,monospace;color:${isError ? '#b91c1c' : '#1c1917'};background:${isError ? '#fef2f2' : '#fafaf9'}">${escapeHtml(body || title)}</div>
      <div id="skillModalFoot" style="padding:12px 18px;border-top:1px solid var(--border);display:flex;gap:8px;justify-content:flex-end">
        <button class="btn-secondary" id="skillModalClose2">关闭</button>
      </div>
    </div>
  `;
  modal.style.display = 'flex';
  modal._close = () => { modal.style.display = 'none'; };
  modal.querySelector('#skillModalClose').onclick = modal._close;
  modal.querySelector('#skillModalClose2').onclick = modal._close;
}

function updateSkillModalText(text) {
  const m = document.getElementById('skillModalBody');
  if (m) {
    m.textContent = text;
    // 滚到底
    const wrap = m.parentElement;
    if (wrap) wrap.scrollTop = wrap.scrollHeight;
  }
}

function showSkillModalActions(actions) {
  const foot = document.getElementById('skillModalFoot');
  const modal = document.getElementById('skillModal');
  if (!foot || !modal) return;
  // 重新生成 foot 区域, 加操作按钮
  const actBtns = (actions || []).map((a, i) => `<button class="btn-primary" data-act="${i}">${a.label}</button>`).join('');
  foot.innerHTML = actBtns + '<button class="btn-secondary" id="skillModalClose2">关闭</button>';
  foot.querySelector('#skillModalClose2').onclick = modal._close;
  foot.querySelectorAll('[data-act]').forEach(btn => {
    btn.addEventListener('click', () => {
      const a = actions[parseInt(btn.dataset.act)];
      if (a.act === 'appendChapter') {
        const ed = $('#editor');
        if (ed) { ed.value = (ed.value ? ed.value + '\n\n' : '') + a.text; updateWordCount(); saveChapter(false); showToast('已追加到章节'); }
        modal._close();
      } else if (a.act === 'replaceChapter') {
        const ed = $('#editor');
        if (ed) { ed.value = a.text; updateWordCount(); saveChapter(false); showToast('已替换'); }
        modal._close();
      } else if (a.act === 'addLore') {
        const kind = a.skillId === 'character' ? 'character' :
                     a.skillId === 'location'   ? 'location'   :
                     a.skillId === 'faction'    ? 'other'      :
                     a.skillId === 'item'       ? 'item'       :
                     a.skillId === 'worldbuilding' ? 'world'    : 'other';
        const name = prompt('设定名?', extractName(a.text) || '新设定');
        if (name) {
          api.lore.create({ kind, name, content: a.text, keywords: '' }).then(() => { showToast('已加到设定库'); switchTab('lore'); });
          modal._close();
        }
      } else if (a.act === 'copy') {
        navigator.clipboard.writeText(a.text).then(() => showToast('已复制'));
      }
    });
  });
}

function extractName(text) {
  const m = text.match(/^#+\s*(.+)/m) || text.match(/^名称[:：]\s*(.+)/m) || text.match(/^姓名[:：]\s*(.+)/m);
  return m ? m[1].trim().slice(0, 40) : null;
}

// ---- 渲染 AI 工具菜单 (从 catalog 拉) ----
async function renderAIMenu() {
  const menu = $('#menu-ai');
  menu.innerHTML = '';
  try {
    State.skillCatalog = await api.skills.catalog();
  } catch (e) { State.skillCatalog = []; }
  if (!State.skillCatalog.length) {
    menu.innerHTML = '<div style="padding:10px;color:var(--text-soft);font-size:12px">技能加载失败, 稍后重试</div>';
    return;
  }
  // 按 category 分组
  const groups = { write: [], world: [], analyze: [], user: [] };
  const label = { write: '创作', world: '设定', analyze: '分析', user: '我的' };
  for (const s of State.skillCatalog) {
    if (!groups[s.category]) groups[s.category] = [];
    groups[s.category].push(s);
  }
  for (const k of ['write', 'world', 'analyze', 'user']) {
    if (!groups[k] || !groups[k].length) continue;
    const hdr = document.createElement('div');
    hdr.style.cssText = 'padding:6px 10px 4px;font-size:10.5px;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-faint);user-select:none';
    hdr.textContent = label[k];
    menu.appendChild(hdr);
    for (const s of groups[k]) {
      if (s.id === 'chat') continue;  // chat 不在写作工具菜单
      const item = document.createElement('div');
      item.className = 'menu-item';
      item.dataset.skill = s.id;
      item.innerHTML = `<span style="font-size:14px;width:18px">${s.icon || '•'}</span><span>${escapeHtml(s.name)}</span>`;
      item.addEventListener('mouseenter', () => { item.style.background = 'var(--hover)'; });
      item.addEventListener('mouseleave', () => { item.style.background = ''; });
      menu.appendChild(item);
    }
  }
  // 把 aiContinue / aiPolish 顶栏按钮也走通用入口
  $('#aiContinueBtn')?.addEventListener('click', () => aiRunSkill('continue'));
  $('#aiPolishBtn')?.addEventListener('click', () => aiRunSkill('polish'));
}

// ---- Lore ----
let LoreAll = [];
async function renderLoreSidebar(sb) {
  LoreAll = (await api.lore.list()) || [];
  const kind = $('#loreKind').value;
  renderLoreListByKind(kind);
}
async function renderLore() {
  const sel = $('#loreKind');
  sel.value = 'character';
  sel.addEventListener('change', () => { renderLoreListByKind(sel.value); $('#loreName').value = ''; $('#loreContent').value = ''; $('#loreKeywords').value = ''; State.loreId = null; });
  $('#newLoreBtn').addEventListener('click', async () => {
    const r = await api.lore.create({ kind: sel.value, name: '新设定', content: '', keywords: '' });
    State.loreId = r.id;
    LoreAll = await api.lore.list();
    renderLoreListByKind(sel.value);
    loadLoreDetail(r.id);
  });
  $('#saveLoreBtn').addEventListener('click', async () => {
    if (!State.loreId) return;
    await api.lore.update({ id: State.loreId, kind: sel.value, name: $('#loreName').value, content: $('#loreContent').value, keywords: $('#loreKeywords').value });
    showToast('已保存');
    LoreAll = await api.lore.list();
    renderLoreListByKind(sel.value);
  });
  $('#deleteLoreBtn').addEventListener('click', async () => {
    if (!State.loreId) return;
    if (!confirm('删除这条设定?')) return;
    await api.lore.delete({ id: State.loreId });
    State.loreId = null; $('#loreName').value = ''; $('#loreContent').value = ''; $('#loreKeywords').value = '';
    LoreAll = await api.lore.list();
    renderLoreListByKind(sel.value);
  });
  // 首次加载
  LoreAll = await api.lore.list();
  renderLoreListByKind(sel.value);
}
function renderLoreListByKind(kind) {
  const sb = $('#loreList');
  if (!sb) return;
  sb.innerHTML = '';
  for (const e of LoreAll.filter(x => x.kind === kind)) {
    const el = document.createElement('div');
    el.className = 'list-item' + (State.loreId === e.id ? ' active' : '');
    el.innerHTML = `<span class="title">${escapeHtml(e.name)}</span>`;
    el.addEventListener('click', () => loadLoreDetail(e.id));
    sb.appendChild(el);
  }
}
async function loadLoreDetail(id) {
  const r = await fetch('/api/lore/' + id); if (!r.ok) return;
  const e = await r.json();
  State.loreId = e.id;
  $('#loreKind').value = e.kind;
  $('#loreName').value = e.name;
  $('#loreContent').value = e.content;
  $('#loreKeywords').value = e.keywords;
  renderLoreListByKind($('#loreKind').value);
}

// ---- Chat ----
async function renderChatSidebar(sb) {
  const convs = await api.conversations.list();
  for (const c of (convs || [])) {
    const el = document.createElement('div');
    el.className = 'list-item' + (State.convId === c.id ? ' active' : '');
    el.innerHTML = `<span class="title">${escapeHtml(c.title)}</span>
      <span class="actions"><button class="btn-icon" data-act="del" title="删除">✕</button></span>`;
    el.addEventListener('click', () => { State.convId = c.id; renderChatSidebar($('#sidebar')); loadMain(); });
    el.querySelector('[data-act="del"]').addEventListener('click', async (e) => {
      e.stopPropagation();
      if (!confirm('删除此对话?')) return;
      await api.conversations.delete({ id: c.id });
      if (State.convId === c.id) { State.convId = null; }
      renderChatSidebar($('#sidebar')); loadMain();
    });
    sb.appendChild(el);
  }
}
async function renderChat() {
  const sel = $('#chatAgentSel');
  const agents = await api.agents.list();
  sel.innerHTML = '<option value="">(无 Agent)</option>' + (agents || []).map(a => `<option value="${a.id}">${escapeHtml(a.name)}</option>`).join('');
  sel.addEventListener('change', async () => {
    if (!State.convId) return;
    await fetch('/api/conversations/' + State.convId, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agentId: parseInt(sel.value) || 0 }) });
  });
  $('#newChatBtn').addEventListener('click', createConvFlow);
  $('#chatInput').addEventListener('keydown', (e) => { if (e.ctrlKey && e.key === 'Enter') { e.preventDefault(); sendChat(); } });
  $('#chatSendBtn').addEventListener('click', sendChat);
  await loadMessages();
}
async function loadMessages() {
  const list = $('#chatMessages');
  if (!list) return;
  list.innerHTML = '';
  if (!State.convId) {
    list.innerHTML = '<div style="margin:auto;color:var(--text-soft);text-align:center;padding:40px">选左侧的对话, 或点"＋ 新对话"</div>';
    return;
  }
  // 加载 agent
  const convs = await api.conversations.list();
  const conv = (convs || []).find(c => c.id === State.convId);
  let agent = null;
  if (conv && conv.agentId) {
    const agents = await api.agents.list();
    agent = (agents || []).find(a => a.id === conv.agentId);
  }
  if (agent) {
    const opt = $('#chatAgentSel option[value="' + agent.id + '"]');
    if (opt) opt.selected = true;
  }

  const msgs = await api.conversations.messages({ id: State.convId });
  for (const m of (msgs || [])) {
    const row = document.createElement('div');
    row.className = 'bubble-row';
    if (m.role === 'user') {
      row.style.flexDirection = 'row-reverse';
      row.innerHTML = `<div class="bubble user">${escapeHtml(m.content)}</div>`;
    } else if (m.role === 'assistant') {
      const av = avatarFor(agent);
      row.innerHTML = `<div class="avatar"><img src="${av}" alt=""></div><div class="bubble assistant">${escapeHtml(m.content)}</div>`;
    } else {
      row.style.justifyContent = 'center';
      row.innerHTML = `<div class="bubble system">${escapeHtml(m.content)}</div>`;
    }
    list.appendChild(row);
  }
  list.scrollTop = list.scrollHeight;
}
async function sendChat() {
  if (!State.convId) { showToast('先选一个对话', true); return; }
  const input = $('#chatInput');
  const text = input.value.trim(); if (!text) return;
  input.value = '';
  await api.conversations.appendMessage({ convId: State.convId, role: 'user', content: text });
  const hist = await api.conversations.messages({ id: State.convId });
  const messages = (hist || []).map(m => ({ role: m.role, content: m.content }));
  const convs = await api.conversations.list();
  const conv = (convs || []).find(c => c.id === State.convId);
  let agent = null;
  if (conv && conv.agentId) agent = (await api.agents.list()).find(a => a.id === conv.agentId);
  if (agent && agent.prompt) messages.unshift({ role: 'system', content: agent.prompt });
  else messages.unshift({ role: 'system', content: '你是一位中文写作助手.' });

  const list = $('#chatMessages');
  const placeholder = document.createElement('div');
  placeholder.className = 'bubble-row';
  const av = avatarFor(agent);
  placeholder.innerHTML = `<div class="avatar"><img src="${av}" alt=""></div><div class="bubble assistant">⏳ 思考中…</div>`;
  list.appendChild(placeholder);
  list.scrollTop = list.scrollHeight;

  try {
    const r = await api.llm.chat({ messages, temperature: 0.7 });
    const text = (r && (r.content || r.data?.content)) || '';
    placeholder.querySelector('.bubble').textContent = text || '(空)';
    if (text) await api.conversations.appendMessage({ convId: State.convId, role: 'assistant', content: text });
  } catch (e) {
    placeholder.querySelector('.bubble').textContent = '错误: ' + e.message;
  }
  list.scrollTop = list.scrollHeight;
}

// ---- Agents ----
async function renderAgentsSidebar(sb) {
  const list = await api.agents.list();
  for (const a of (list || [])) {
    const el = document.createElement('div');
    el.className = 'list-item';
    el.innerHTML = `<div style="width:18px;height:18px;border-radius:50%;overflow:hidden;flex:0 0 18px"><img src="${avatarFor(a)}" style="width:100%;height:100%;object-fit:cover"></div><span class="title">${escapeHtml(a.name)}</span>`;
    el.addEventListener('click', () => switchTab('agents'));
    sb.appendChild(el);
  }
}
async function renderAgents() {
  const list = await api.agents.list();
  const wrap = $('#agentList'); wrap.innerHTML = '';
  for (const a of (list || [])) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `
      <div class="agent-card">
        <div class="avatar"><img src="${avatarFor(a)}" alt=""></div>
        <div class="info">
          <div class="name">${escapeHtml(a.name)}</div>
          <div class="meta">模型: ${escapeHtml(a.model || '(默认)')} · 技能: ${escapeHtml(a.skill || '-')}</div>
          <div class="desc">${escapeHtml(a.prompt || '(无提示词)')}</div>
        </div>
      </div>
      <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:8px">
        <button class="btn-link" data-act="edit">编辑</button>
        <button class="btn-link danger" data-act="del">删除</button>
      </div>
    `;
    el.querySelector('[data-act="edit"]').addEventListener('click', () => editAgentFlow(a));
    el.querySelector('[data-act="del"]').addEventListener('click', async () => {
      if (!confirm('删除 Agent "' + a.name + '"?')) return;
      await api.agents.delete({ id: a.id });
      renderAgents(); renderAgentsSidebar($('#sidebar'));
    });
    wrap.appendChild(el);
  }
  $('#newAgentBtn').addEventListener('click', () => editAgentFlow(null));
  renderAgentsSidebar($('#sidebar'));
}
async function editAgentFlow(a) {
  const name = prompt('Agent 名称', a ? a.name : ''); if (name === null) return;
  const model = prompt('模型 (留空用默认)', a ? a.model : '') ?? '';
  const skill = prompt('固定技能名 (留空不用)', a ? a.skill : '') ?? '';
  const prompt = prompt('系统提示词', a ? a.prompt : '') ?? '';
  await api.agents.save({ id: a ? a.id : 0, name, model, skill, prompt, toolGroups: a ? a.toolGroups : '' });
  renderAgents(); renderAgentsSidebar($('#sidebar'));
}

// ---- Search ----
async function renderSearch() {
  const input = $('#searchInput');
  const btn = $('#searchBtn');
  if (!input) return;
  // Ctrl+K 聚焦
  document.addEventListener('keydown', function onKey(e) {
    if (e.ctrlKey && e.key === 'k') { e.preventDefault(); input.focus(); input.select(); }
  });
  // 提交
  const doSearch = async () => {
    const q = input.value.trim();
    if (!q) return;
    const out = $('#searchResults');
    out.innerHTML = '<div style="color:var(--text-soft);padding:8px">搜索中…</div>';
    try {
      const results = await api.search.query({ q });
      if (!results || !results.length) {
        out.innerHTML = '<div style="color:var(--text-soft);padding:20px">无结果</div>';
        return;
      }
      // 分组
      const groups = { book: [], chapter: [], lore: [] };
      const labels = { book: '📚 作品', chapter: '📄 章节', lore: '📖 设定' };
      for (const r of results) {
        if (!groups[r.type]) groups[r.type] = [];
        groups[r.type].push(r);
      }
      out.innerHTML = '';
      for (const k of ['book', 'chapter', 'lore']) {
        if (!groups[k] || !groups[k].length) continue;
        const hdr = document.createElement('div');
        hdr.style.cssText = 'font-size:11px;color:var(--text-faint);margin:14px 0 6px;text-transform:uppercase;letter-spacing:0.05em';
        hdr.textContent = labels[k] + ' (' + groups[k].length + ')';
        out.appendChild(hdr);
        for (const r of groups[k]) {
          const card = document.createElement('div');
          card.className = 'card';
          card.style.marginBottom = '6px';
          const title = r.type === 'lore' ? r.name : r.title;
          const snippet = (r.snippet || '').replace(/</g, '&lt;');
          card.innerHTML = `<div style="font-weight:600;font-size:13.5px">${escapeHtml(title)}</div>
            <div style="font-size:12px;color:var(--text-soft);margin-top:4px;line-height:1.5">${escapeHtml(snippet)}</div>`;
          card.addEventListener('click', () => {
            if (r.type === 'book') { State.currentBookId = r.id; State.bookTitle = r.title; updateBookTitle(); switchTab('chapters'); }
            else if (r.type === 'chapter') {
              State.currentBookId = r.bookId; switchTab('chapters');
              setTimeout(() => openChapter(r.id), 100);
            }
            else if (r.type === 'lore') { switchTab('lore'); setTimeout(() => loadLoreDetail(r.id), 100); }
          });
          out.appendChild(card);
        }
      }
    } catch (e) {
      $('#searchResults').innerHTML = '<div style="color:#b91c1c;padding:8px">搜索失败: ' + e.message + '</div>';
    }
  };
  btn.addEventListener('click', doSearch);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSearch(); });
  setTimeout(() => input.focus(), 50);
}

// ---- Vectors ----
async function renderVectorsSidebar(sb) {
  const stats = await api.vectors.stats();
  sb.innerHTML = `<div style="padding:8px;font-size:11.5px;color:var(--text-soft)">索引: <code>${escapeHtml(stats.index || '')}</code><br>块数: ${stats.chunks}</div>`;
}
async function renderVectors() {
  const stats = await api.vectors.stats();
  $('#vecStats').textContent = `索引路径: ${stats.index} | 共 ${stats.chunks} 块`;
  $('#vecImportBtn').addEventListener('click', async () => {
    if (!State.chapterId) { showToast('先在章节视图选一章', true); return; }
    const r = await fetch('/api/chapters/' + State.chapterId);
    const c = await r.json();
    const source = $('#vecSource').value || ('chapter-' + c.id);
    await api.vectors.import({ source, text: c.content || '' });
    showToast('已导入');
    renderVectors(); renderVectorsSidebar($('#sidebar'));
  });
  $('#vecSearchBtn').addEventListener('click', async () => {
    const q = $('#vecQuery').value; if (!q) return;
    const hits = await api.vectors.search({ query: q, topK: 8 });
    const box = $('#vecHits'); box.innerHTML = '';
    for (const h of (hits || [])) {
      const el = document.createElement('div');
      el.style.cssText = 'padding:8px 10px;background:rgba(255,255,255,0.6);border:1px solid var(--border);border-radius:6px;';
      el.innerHTML = `<div style="font-size:11px;color:var(--text-soft)">${escapeHtml(h.source)} · 分数 ${h.score.toFixed(2)}</div><div style="margin-top:2px">${escapeHtml(h.snippet)}…</div>`;
      box.appendChild(el);
    }
    if (!hits || !hits.length) box.innerHTML = '<div style="color:var(--text-soft);font-size:12.5px">无命中</div>';
  });
  renderVectorsSidebar($('#sidebar'));
}

// ---- Skills ----
async function renderSkillsSidebar(sb) {
  const list = await api.skills.list();
  for (const s of (list || [])) {
    const el = document.createElement('div');
    el.className = 'list-item';
    el.innerHTML = `<span class="title">🧩 ${escapeHtml(s.name)}</span>`;
    el.addEventListener('click', () => switchTab('skills'));
    sb.appendChild(el);
  }
}
async function renderSkills() {
  const list = await api.skills.list();
  const wrap = $('#skillList'); wrap.innerHTML = '';
  if (!list || !list.length) {
    wrap.innerHTML = '<div style="color:var(--text-soft);font-size:12.5px">还没有技能. 在 <code>%APPDATA%\\ZhinaiNovelEditor\\skills\\&lt;name&gt;\\SKILL.md</code> 里写一个.</div>';
    return;
  }
  for (const s of list) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `<div style="font-size:14px;font-weight:600">🧩 ${escapeHtml(s.name)}</div>
      <div style="font-size:11.5px;color:var(--text-soft);margin-top:2px">${escapeHtml(s.path || '')}</div>
      <div style="font-size:12.5px;color:var(--text-soft);margin-top:6px;line-height:1.5">${escapeHtml(s.summary || '')}</div>`;
    wrap.appendChild(el);
  }
  renderSkillsSidebar($('#sidebar'));
}

// ---- Settings ----
async function renderSettings() {
  const cfg = await api.config.get();
  const providers = cfg.providers || [];
  const defaults = cfg.defaults || {};
  // 模型商下拉
  const sel = $('#cfgProvider');
  sel.innerHTML = providers.map(p => `<option value="${p.id}">${p.name || p.id}</option>`).join('');
  // 推断当前 provider
  const currentProvider = inferProvider(providers, cfg.baseURL || '', cfg.model || '');
  sel.value = currentProvider || 'custom';
  sel.addEventListener('change', () => {
    const p = providers.find(x => x.id === sel.value);
    if (p) {
      $('#cfgBaseURL').value = p.baseURL || '';
      const dl = $('#cfgModelList');
      dl.innerHTML = (p.models || []).map(m => `<option value="${m}">`).join('');
    }
  });
  // 初始化 datalist
  const p = providers.find(x => x.id === (sel.value || 'custom'));
  if (p) {
    const dl = $('#cfgModelList');
    dl.innerHTML = (p.models || []).map(m => `<option value="${m}">`).join('');
  }

  // 表单值
  $('#cfgBaseURL').value = cfg.baseURL || '';
  $('#cfgApiKey').value = cfg.apiKey || '';
  $('#cfgModel').value = cfg.model || '';
  const temp = cfg.temperature ?? defaults.temperature ?? 0.7;
  $('#cfgTemp').value = temp; $('#cfgTempVal').textContent = temp.toFixed(2);
  $('#cfgMaxTokens').value = cfg.maxTokens ?? defaults.maxTokens ?? 8192;
  $('#cfgContextWindow').value = cfg.contextWindow ?? defaults.contextWindow ?? 131072;
  $('#cfgEnableTools').checked = cfg.enableTools ?? defaults.enableTools ?? true;
  $('#cfgEnableComp').checked = cfg.enableContextCompression ?? defaults.enableContextCompression ?? true;
  $('#cfgFollowStream').checked = cfg.followsStreamingOutput ?? defaults.followsStreamingOutput ?? true;
  const op = cfg.backgroundOpacity ?? defaults.backgroundOpacity ?? 0.64;
  $('#bgOpacity').value = Math.round(op * 100); $('#bgOpacityVal').textContent = Math.round(op * 100);
  State.bgOpacity = op;
  document.documentElement.style.setProperty('--bg-opacity', op);
  // (旧 bgPath 已废弃, 改用上传按钮)
  // 数据目录 (后端可以查, 但前端写死简化)
  $('#cfgDataDir').textContent = (cfg.dataDir || navigator.platform.includes('Win')
    ? '%APPDATA%\\ZhinaiNovelEditor\\' : '~/Library/Application Support/ZhinaiNovelEditor/');

  // 事件
  $('#bgPickBtn').addEventListener('click', () => $('#bgFile').click());
  $('#bgFile').addEventListener('change', async (e) => {
    const f = e.target.files[0]; if (!f) return;
    const reader = new FileReader();
    reader.onload = async () => {
      const dataUrl = reader.result;
      const mime = f.type;
      try {
        const r = await fetch('/api/system/uploadBackground', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ data: dataUrl, mime }),
        });
        const j = await r.json();
        if (!j.ok) { showToast('上传失败: ' + (j.error || ''), true); return; }
        applyBackground('/api/background?v=' + Date.now(), mime);
        showToast('背景已更新');
      } catch (err) { showToast('上传失败: ' + err.message, true); }
    };
    reader.readAsDataURL(f);
  });
  $('#bgResetBtn').addEventListener('click', async () => {
    await fetch('/api/system/background', { method: 'DELETE' });
    applyBackground(null);
    showToast('已恢复默认');
  });
  // 启动时检查背景
  fetch('/api/background', { method: 'HEAD' }).then(r => {
    if (r.ok) {
      const mime = r.headers.get('content-type') || '';
      applyBackground('/api/background?v=' + Date.now(), mime);
    }
  });

  $('#cfgKeyToggle').addEventListener('click', () => {
    const k = $('#cfgApiKey');
    if (k.type === 'password') { k.type = 'text'; $('#cfgKeyToggle').textContent = '隐藏'; }
    else { k.type = 'password'; $('#cfgKeyToggle').textContent = '显示'; }
  });
  $('#cfgTemp').addEventListener('input', (e) => {
    const v = parseFloat(e.target.value);
    $('#cfgTempVal').textContent = v.toFixed(2);
  });
  $('#bgOpacity').addEventListener('input', (e) => {
    const v = parseInt(e.target.value, 10);
    State.bgOpacity = v / 100;
    $('#bgOpacityVal').textContent = v;
    document.documentElement.style.setProperty('--bg-opacity', State.bgOpacity);
  });
  $('#cfgOpenDir').addEventListener('click', () => api.system.openDataDir().catch(e => showToast(e.message, true)));
  $('#cfgSaveBtn').addEventListener('click', async () => {
    const newCfg = {
      provider: sel.value,
      baseURL: $('#cfgBaseURL').value.trim(),
      apiKey: $('#cfgApiKey').value.trim(),
      model: $('#cfgModel').value.trim(),
      temperature: parseFloat($('#cfgTemp').value),
      maxTokens: parseInt($('#cfgMaxTokens').value, 10),
      contextWindow: parseInt($('#cfgContextWindow').value, 10),
      enableTools: $('#cfgEnableTools').checked,
      enableContextCompression: $('#cfgEnableComp').checked,
      followsStreamingOutput: $('#cfgFollowStream').checked,
      backgroundOpacity: State.bgOpacity,
    };
    await api.config.set(newCfg);
    showToast('已保存');
  });
  $('#cfgTestBtn').addEventListener('click', async () => {
    const out = $('#cfgTestResult');
    out.textContent = '测试中…'; out.style.color = 'var(--text-soft)';
    try {
      const r = await api.llm.test({
        baseURL: $('#cfgBaseURL').value.trim(),
        apiKey: $('#cfgApiKey').value.trim(),
        model: $('#cfgModel').value.trim(),
      });
      if (r.ok) { out.textContent = '✓ 连接 OK: ' + (r.content || '').slice(0, 50); out.style.color = '#15803d'; }
      else { out.textContent = '✗ 失败: ' + (r.error || ''); out.style.color = '#b91c1c'; }
    } catch (e) { out.textContent = '✗ ' + e.message; out.style.color = '#b91c1c'; }
  });
}

function inferProvider(providers, baseURL, model) {
  for (const p of providers) {
    if (!p.baseURL) continue;
    if (baseURL && baseURL.startsWith(p.baseURL.replace(/\/+$/, ''))) return p.id;
  }
  if (model) {
    if (model.startsWith('gpt-')) return 'openai';
    if (model.startsWith('deepseek-')) return 'deepseek';
    if (model.startsWith('qwen-')) return 'dashscope';
    if (model.startsWith('glm-')) return 'zhipu';
  }
  return 'custom';
}

function platformLabel(p) {
  return { tomato: '番茄', qidian: '起点', feilu: '飞卢', other: '其他' }[p] || p;
}

// ---- 启动 ----
(async function init() {
  setupToolbar();
  setupResizers();
  // 加载作品列表更新顶栏
  try {
    const books = await api.books.list();
    if (books && books.length && !State.currentBookId) {
      State.currentBookId = books[0].id;
      State.bookTitle = books[0].title;
      updateBookTitle();
    }
  } catch (_) {}
  // 加载 skill catalog 渲染 AI 工具菜单
  await renderAIMenu();
  switchTab('chapters');
})();

// ---- 侧栏宽度可拖动 (跟 macOS HorizontalResizeDivider 对齐) ----
function setupResizers() {
  const saved = parseInt(localStorage.getItem('zhinai-sidebar-width') || '240', 10);
  applySidebarWidth(clamp(saved, 160, 480));
  const div = document.getElementById('sidebarDivider');
  if (!div) return;
  let dragging = false, startX = 0, startW = 0;
  div.addEventListener('mousedown', (e) => {
    dragging = true;
    startX = e.clientX;
    const sb = document.getElementById('sidebarPane');
    startW = sb ? sb.getBoundingClientRect().width : 240;
    div.classList.add('dragging');
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'col-resize';
    e.preventDefault();
  });
  document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    const dx = e.clientX - startX;
    applySidebarWidth(clamp(startW + dx, 160, 480));
  });
  document.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    div.classList.remove('dragging');
    document.body.style.userSelect = '';
    document.body.style.cursor = '';
    const sb = document.getElementById('sidebarPane');
    if (sb) {
      const w = sb.getBoundingClientRect().width;
      localStorage.setItem('zhinai-sidebar-width', String(Math.round(w)));
    }
  });
  // 双击 reset 到默认
  div.addEventListener('dblclick', () => {
    applySidebarWidth(240);
    localStorage.setItem('zhinai-sidebar-width', '240');
  });
}
function applySidebarWidth(w) {
  document.documentElement.style.setProperty('--sidebar-width', w + 'px');
}
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
