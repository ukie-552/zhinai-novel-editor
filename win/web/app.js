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
    'books.update':         ['PUT',  '/api/books/' + params.id, { title: params.title, author: params.author, summary: params.summary }],
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

  // AI 工具菜单
  $('#menu-ai').addEventListener('click', async (e) => {
    const item = e.target.closest('.menu-item');
    if (!item) return;
    const skill = item.dataset.skill;
    if (skill === 'continue') await aiContinue();
    else if (skill === 'polish') await aiPolish();
    else if (skill === 'consistency') showToast('一致性检查: 待实现');
    else if (skill === 'outline') showToast('生成大纲: 待实现');
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
  const title = prompt('作品名');
  if (!title) return;
  const r = await api.books.create({ title, author: '', summary: '' });
  State.currentBookId = r.id;
  State.bookTitle = title;
  updateBookTitle();
  switchTab('books');
}

// ---- 视图切换 ----
const TAB_TITLES = {
  books: '作品', chapters: '章节', lore: '设定库', chat: '对话',
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
      <div style="font-size:11.5px;color:var(--text-soft);margin-top:2px">${escapeHtml(b.author || '未署名')}</div>
      <div style="font-size:12.5px;color:var(--text-soft);margin-top:8px;line-height:1.5;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden">${escapeHtml(b.summary || '—')}</div>
      <div style="display:flex;gap:8px;margin-top:10px;justify-content:flex-end">
        <button class="btn-link" data-act="open">打开</button>
        <button class="btn-link danger" data-act="del">删除</button>
      </div>
    `;
    el.querySelector('[data-act="open"]').addEventListener('click', (e) => {
      e.stopPropagation();
      State.currentBookId = b.id; State.bookTitle = b.title; updateBookTitle();
      switchTab('chapters');
    });
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
  if (!State.chapterId) { showToast('先选章节', true); return; }
  const content = $('#editor').value, title = $('#chapterTitle').value;
  const btn = $('#aiContinueBtn'); btn.disabled = true; const orig = btn.innerHTML; btn.innerHTML = '⏳ 生成中…';
  try {
    const lore = (await api.lore.list()) || [];
    const hits = lore.filter(e => e.keywords && e.keywords.split(/[,，]/).some(k => k.trim() && content.includes(k.trim())));
    const sys = '你是一位中文小说续写助手, 文笔自然, 保持人物一致.' +
      (hits.length ? ('\n\n参考设定:\n' + hits.map(h => `- ${h.name}: ${h.content}`).join('\n')) : '');
    const result = await api.llm.chat({
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: `续写《${title}》:\n\n${content}\n\n(直接接续正文, 不复述, 不解释, 不分段标题)` }
      ],
      temperature: 0.8,
    });
    const text = (result && (result.content || result.data?.content)) || '';
    if (text) {
      $('#editor').value = (content ? content + '\n\n' : '') + text;
      updateWordCount();
      showToast('续写完成');
    } else showToast('无内容返回', true);
  } catch (e) { showToast('续写失败: ' + e.message, true); }
  finally { btn.disabled = false; btn.innerHTML = orig; saveChapter(false); }
}
async function aiPolish() {
  if (!State.chapterId) { showToast('先选章节', true); return; }
  const content = $('#editor').value, title = $('#chapterTitle').value;
  if (!content.trim()) { showToast('章节是空的', true); return; }
  const btn = $('#aiPolishBtn'); btn.disabled = true; const orig = btn.innerHTML; btn.innerHTML = '⏳ 润色中…';
  try {
    const result = await api.llm.chat({
      messages: [
        { role: 'system', content: '你是一位中文小说润色助手, 在保持原意和风格的前提下润色文字, 不要改变剧情. 直接给出润色后的全文, 不要复述要求.' },
        { role: 'user', content: `润色《${title}》:\n\n${content}` }
      ],
      temperature: 0.6,
    });
    const text = (result && (result.content || result.data?.content)) || '';
    if (text) {
      if (confirm('用润色版替换当前章节?')) {
        $('#editor').value = text; updateWordCount(); showToast('已润色');
        saveChapter(false);
      }
    } else showToast('无内容返回', true);
  } catch (e) { showToast('润色失败: ' + e.message, true); }
  finally { btn.disabled = false; btn.innerHTML = orig; }
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
  $('#cfgBaseURL').value = cfg.baseURL || '';
  $('#cfgApiKey').value = cfg.apiKey || '';
  $('#cfgModel').value = cfg.model || '';
  $('#bgOpacity').value = State.bgOpacity;
  $('#bgPath').value = cfg.backgroundMediaPath || '';
  $('#cfgSaveBtn').addEventListener('click', async () => {
    const newCfg = {
      baseURL: $('#cfgBaseURL').value.trim(),
      apiKey: $('#cfgApiKey').value.trim(),
      model: $('#cfgModel').value.trim(),
      backgroundMediaPath: $('#bgPath').value.trim(),
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
  $('#bgOpacity').addEventListener('input', (e) => {
    State.bgOpacity = parseFloat(e.target.value) || 0.64;
    document.documentElement.style.setProperty('--bg-opacity', State.bgOpacity);
  });
  document.documentElement.style.setProperty('--bg-opacity', State.bgOpacity);
}

// ---- 启动 ----
(async function init() {
  setupToolbar();
  // 加载作品列表更新顶栏
  try {
    const books = await api.books.list();
    if (books && books.length && !State.currentBookId) {
      State.currentBookId = books[0].id;
      State.bookTitle = books[0].title;
      updateBookTitle();
    }
  } catch (_) {}
  switchTab('chapters');
})();
