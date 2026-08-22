// app.js - 织奈编辑器 前端主逻辑
// 通信:
//   通过 window.chrome.webview.postMessage() 走原生桥, 在 C++ 端分发到本地 HTTP API.
//   如果在浏览器里直接打开 (没 webview 环境), 走 fetch 直连同源 server.

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
  } else {
    // 浏览器调试: 直接走 REST
    return callRest(method, params);
  }
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

// ---- 视图切换 ----
const views = ['books', 'chapters', 'lore', 'chat', 'agents', 'vectors', 'skills', 'settings'];
let currentView = 'books';
let appState = { books: [], agents: [], skills: [] };

function showView(name) {
  currentView = name;
  document.querySelectorAll('.nav-item').forEach(b => {
    b.classList.toggle('nav-active', b.dataset.view === name);
  });
  const tpl = document.getElementById('tpl-' + name);
  const main = document.getElementById('main');
  main.innerHTML = '';
  if (tpl) main.appendChild(tpl.content.cloneNode(true));
  if (name === 'books') renderBooks();
  if (name === 'chapters') renderChaptersView();
  if (name === 'lore') renderLoreView();
  if (name === 'chat') renderChatView();
  if (name === 'agents') renderAgentsView();
  if (name === 'vectors') renderVectorsView();
  if (name === 'skills') renderSkillsView();
  if (name === 'settings') renderSettingsView();
}

document.querySelectorAll('[data-view]').forEach(b => {
  b.addEventListener('click', () => showView(b.dataset.view));
});

// ---- 顶栏 ----
document.getElementById('openDataDir').addEventListener('click', () => {
  api.system.openDataDir().catch(e => alert(e.message));
});

(async () => {
  try {
    await api.system.openDataDir();
  } catch (_) {}
  // health
  try {
    const cfg = await api.config.get();
    document.getElementById('health').textContent =
      (cfg && cfg.model) ? ('模型: ' + cfg.model) : '未配置模型';
  } catch (e) {
    document.getElementById('health').textContent = '未连接';
  }
})();

// ---- Books ----
async function renderBooks() {
  const list = document.getElementById('bookList');
  const books = await api.books.list();
  appState.books = books || [];
  list.innerHTML = '';
  for (const b of appState.books) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `
      <div class="text-base font-semibold">${escapeHtml(b.title)}</div>
      <div class="text-xs text-stone-500 mt-1">${escapeHtml(b.author || '')}</div>
      <div class="text-sm text-stone-600 mt-2 line-clamp-2">${escapeHtml(b.summary || '')}</div>
      <div class="flex justify-end gap-2 mt-3">
        <button class="btn-link" data-act="open">打开章节</button>
        <button class="btn-link" data-act="del">删除</button>
      </div>
    `;
    el.querySelector('[data-act="open"]').addEventListener('click', (e) => {
      e.stopPropagation();
      appState.currentBookId = b.id;
      showView('chapters');
    });
    el.querySelector('[data-act="del"]').addEventListener('click', async (e) => {
      e.stopPropagation();
      if (!confirm('删除作品 "' + b.title + '"?')) return;
      await api.books.delete({ id: b.id });
      renderBooks();
    });
    list.appendChild(el);
  }
  document.getElementById('newBook').addEventListener('click', async () => {
    const title = prompt('作品名');
    if (!title) return;
    await api.books.create({ title, author: '', summary: '' });
    renderBooks();
  });
}

// ---- Chapters ----
let chapterState = { bookId: null, chapterId: null, saveTimer: null };

async function renderChaptersView() {
  const sel = document.getElementById('bookSelect');
  const books = await api.books.list();
  sel.innerHTML = '';
  for (const b of books || []) {
    const opt = document.createElement('option');
    opt.value = b.id;
    opt.textContent = b.title;
    if (appState.currentBookId === b.id || (!appState.currentBookId && b === (books || [])[0])) {
      opt.selected = true;
      appState.currentBookId = b.id;
    }
    sel.appendChild(opt);
  }
  sel.addEventListener('change', () => { appState.currentBookId = parseInt(sel.value); loadChapters(); });

  document.getElementById('newChapter').addEventListener('click', async () => {
    if (!appState.currentBookId) return;
    const title = prompt('章节标题', '新章节');
    if (!title) return;
    const r = await api.chapters.create({ bookId: appState.currentBookId, title });
    chapterState.chapterId = r.id;
    await loadChapters();
    openChapter(r.id);
  });

  document.getElementById('saveChapter').addEventListener('click', async () => {
    if (!chapterState.chapterId) return;
    const title = document.getElementById('chapterTitle').value;
    const content = document.getElementById('editor').value;
    await api.chapters.rename({ id: chapterState.chapterId, title });
    await api.chapters.saveContent({ id: chapterState.chapterId, content });
    showToast('已保存');
  });

  document.getElementById('aiContinue').addEventListener('click', aiContinue);

  const editor = document.getElementById('editor');
  editor.addEventListener('input', () => {
    if (chapterState.saveTimer) clearTimeout(chapterState.saveTimer);
    chapterState.saveTimer = setTimeout(async () => {
      if (!chapterState.chapterId) return;
      const content = editor.value;
      const title = document.getElementById('chapterTitle').value;
      await api.chapters.rename({ id: chapterState.chapterId, title });
      await api.chapters.saveContent({ id: chapterState.chapterId, content });
    }, 800);
  });

  await loadChapters();
}

async function loadChapters() {
  if (!appState.currentBookId) return;
  const list = document.getElementById('chapterList');
  const chapters = await api.chapters.list({ bookId: appState.currentBookId });
  list.innerHTML = '';
  chapters = chapters || [];
  for (const c of chapters) {
    const el = document.createElement('div');
    el.className = 'list-item';
    el.draggable = true;
    el.dataset.id = c.id;
    el.innerHTML = `<span class="text-stone-400 text-xs w-6">${c.orderIndex + 1}</span><span class="truncate">${escapeHtml(c.title)}</span>`;
    if (chapterState.chapterId === c.id) el.classList.add('active');
    el.addEventListener('click', () => openChapter(c.id));
    el.addEventListener('dragstart', (e) => { e.dataTransfer.setData('text/plain', c.id); });
    el.addEventListener('dragover', (e) => { e.preventDefault(); el.classList.add('drop-target'); });
    el.addEventListener('dragleave', () => el.classList.remove('drop-target'));
    el.addEventListener('drop', async (e) => {
      e.preventDefault();
      el.classList.remove('drop-target');
      const srcId = parseInt(e.dataTransfer.getData('text/plain'));
      const dstId = c.id;
      if (srcId === dstId) return;
      // 简单交换顺序
      const ids = chapters.map(x => x.id);
      const srcIdx = ids.indexOf(srcId);
      const dstIdx = ids.indexOf(dstId);
      if (srcIdx < 0 || dstIdx < 0) return;
      ids.splice(srcIdx, 1);
      ids.splice(dstIdx, 0, srcId);
      await fetch('/api/books/' + appState.currentBookId + '/chapters/reorder', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids })
      });
      loadChapters();
    });
    list.appendChild(el);
  }
}

async function openChapter(id) {
  const r = await fetch('/api/chapters/' + id);
  if (!r.ok) return;
  const c = await r.json();
  chapterState.chapterId = c.id;
  document.getElementById('chapterTitle').value = c.title;
  document.getElementById('editor').value = c.content || '';
  document.querySelectorAll('#chapterList .list-item').forEach(el => {
    el.classList.toggle('active', parseInt(el.dataset.id) === c.id);
  });
  // 触发关键词命中提示
  const lore = await api.lore.list();
  const editor = document.getElementById('editor');
  const hits = (lore || []).filter(e => e.keywords && e.keywords.split(/[,，]/).some(k => k.trim() && c.content && c.content.includes(k.trim())));
  document.getElementById('loreHint').textContent = hits.length
    ? '设定命中: ' + hits.map(h => h.name).join('、')
    : '';
}

async function aiContinue() {
  if (!chapterState.chapterId) { alert('请先选章节'); return; }
  const content = document.getElementById('editor').value;
  const title = document.getElementById('chapterTitle').value;
  const btn = document.getElementById('aiContinue');
  btn.disabled = true; btn.textContent = '生成中…';
  try {
    // 命中设定
    const lore = (await api.lore.list()) || [];
    const hits = lore.filter(e => e.keywords && e.keywords.split(/[,，]/).some(k => k.trim() && content.includes(k.trim())));
    const sys = '你是一位中文小说续写助手，续写文笔自然，保持人物一致。' +
      (hits.length ? ('\n\n参考设定:\n' + hits.map(h => `- ${h.name}: ${h.content}`).join('\n')) : '');
    const result = await api.llm.chat({
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: `续写以下章节《${title}》:\n\n${content}\n\n(直接接续正文, 不要复述, 不要解释, 不要分段标题)` }
      ],
      temperature: 0.8,
    });
    const text = (result && (result.content || result.data?.content)) || '';
    if (text) {
      document.getElementById('editor').value = content + '\n\n' + text;
      showToast('续写完成');
    } else {
      showToast('无内容返回', true);
    }
  } catch (e) {
    alert('续写失败: ' + e.message);
  } finally {
    btn.disabled = false; btn.textContent = 'AI 续写';
  }
}

// ---- Lore ----
let loreState = { id: null };

async function renderLoreView() {
  const kind = document.getElementById('loreKind');
  kind.addEventListener('change', () => loadLoreList());
  document.getElementById('newLore').addEventListener('click', async () => {
    const r = await api.lore.create({ kind: kind.value, name: '新设定', content: '', keywords: '' });
    loreState.id = r.id;
    await loadLoreList();
    loadLoreDetail(r.id);
  });
  document.getElementById('saveLore').addEventListener('click', async () => {
    if (!loreState.id) return;
    await api.lore.update({
      id: loreState.id,
      kind: document.getElementById('loreKind').value,
      name: document.getElementById('loreName').value,
      content: document.getElementById('loreContent').value,
      keywords: document.getElementById('loreKeywords').value,
    });
    showToast('已保存');
    loadLoreList();
  });
  document.getElementById('deleteLore').addEventListener('click', async () => {
    if (!loreState.id) return;
    if (!confirm('删除这条设定?')) return;
    await api.lore.delete({ id: loreState.id });
    loreState.id = null;
    document.getElementById('loreName').value = '';
    document.getElementById('loreContent').value = '';
    document.getElementById('loreKeywords').value = '';
    loadLoreList();
  });
  await loadLoreList();
}

async function loadLoreList() {
  const list = document.getElementById('loreList');
  const kind = document.getElementById('loreKind').value;
  const all = await api.lore.list();
  const items = (all || []).filter(e => e.kind === kind);
  list.innerHTML = '';
  for (const e of items) {
    const el = document.createElement('div');
    el.className = 'list-item' + (loreState.id === e.id ? ' active' : '');
    el.innerHTML = `<span>${escapeHtml(e.name)}</span>`;
    el.addEventListener('click', () => loadLoreDetail(e.id));
    list.appendChild(el);
  }
}

async function loadLoreDetail(id) {
  const r = await fetch('/api/lore/' + id);
  if (!r.ok) return;
  const e = await r.json();
  loreState.id = e.id;
  document.getElementById('loreKind').value = e.kind;
  document.getElementById('loreName').value = e.name;
  document.getElementById('loreContent').value = e.content;
  document.getElementById('loreKeywords').value = e.keywords;
  loadLoreList();
}

// ---- Chat ----
let chatState = { convId: null };

async function renderChatView() {
  const sel = document.getElementById('agentSelect');
  const agents = await api.agents.list();
  sel.innerHTML = '<option value="">(无 Agent)</option>';
  for (const a of (agents || [])) {
    const opt = document.createElement('option');
    opt.value = a.id;
    opt.textContent = a.name;
    sel.appendChild(opt);
  }

  document.getElementById('newConv').addEventListener('click', async () => {
    const r = await api.conversations.create({
      title: '新对话 ' + new Date().toLocaleString(),
      agentId: parseInt(sel.value) || 0,
      bookId: 0
    });
    chatState.convId = r.id;
    loadConvList();
    loadMessages();
  });

  document.getElementById('sendChat').addEventListener('click', sendChat);
  document.getElementById('chatInput').addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key === 'Enter') { e.preventDefault(); sendChat(); }
  });

  await loadConvList();
}

async function loadConvList() {
  const list = document.getElementById('convList');
  const convs = await api.conversations.list();
  list.innerHTML = '';
  for (const c of (convs || [])) {
    const el = document.createElement('div');
    el.className = 'list-item' + (chatState.convId === c.id ? ' active' : '');
    el.innerHTML = `<span class="truncate">${escapeHtml(c.title)}</span>`;
    el.addEventListener('click', () => { chatState.convId = c.id; loadConvList(); loadMessages(); });
    list.appendChild(el);
  }
}

async function loadMessages() {
  const list = document.getElementById('messages');
  list.innerHTML = '';
  if (!chatState.convId) return;
  const msgs = await api.conversations.messages({ id: chatState.convId });
  for (const m of (msgs || [])) {
    const el = document.createElement('div');
    el.className = 'bubble ' + m.role;
    el.textContent = m.content;
    el.style.alignSelf = m.role === 'user' ? 'flex-end' : 'flex-start';
    list.appendChild(el);
  }
  list.scrollTop = list.scrollHeight;
}

async function sendChat() {
  if (!chatState.convId) { alert('请先创建对话'); return; }
  const input = document.getElementById('chatInput');
  const text = input.value.trim();
  if (!text) return;
  input.value = '';

  // 立刻把 user 消息显示
  await api.conversations.appendMessage({ convId: chatState.convId, role: 'user', content: text });

  // 取所有历史
  const hist = await api.conversations.messages({ id: chatState.convId });
  const messages = (hist || []).map(m => ({ role: m.role, content: m.content }));

  // 取 agent 提示词
  const convs = await api.conversations.list();
  const conv = (convs || []).find(c => c.id === chatState.convId);
  let agent = null;
  if (conv && conv.agentId) {
    const agents = await api.agents.list();
    agent = (agents || []).find(a => a.id === conv.agentId);
  }
  if (agent && agent.prompt) {
    messages.unshift({ role: 'system', content: agent.prompt });
  } else {
    messages.unshift({ role: 'system', content: '你是一位中文写作助手。' });
  }

  // 占位 assistant
  const placeholder = document.createElement('div');
  placeholder.className = 'bubble assistant';
  placeholder.textContent = '…';
  document.getElementById('messages').appendChild(placeholder);

  try {
    const r = await api.llm.chat({ messages, temperature: 0.7 });
    const text = (r && (r.content || r.data?.content)) || '';
    placeholder.textContent = text || '(空)';
    if (text) {
      await api.conversations.appendMessage({ convId: chatState.convId, role: 'assistant', content: text });
    }
  } catch (e) {
    placeholder.textContent = '错误: ' + e.message;
  }
}

// ---- Agents ----
async function renderAgentsView() {
  document.getElementById('newAgent').addEventListener('click', async () => {
    const name = prompt('Agent 名称');
    if (!name) return;
    const r = await api.agents.save({ name, prompt: '', model: '', skill: '', toolGroups: '' });
    renderAgentsView();
    editAgentPrompt(r.id);
  });
  const list = await api.agents.list();
  const wrap = document.getElementById('agentList');
  wrap.innerHTML = '';
  for (const a of (list || [])) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `
      <div class="text-base font-semibold">${escapeHtml(a.name)}</div>
      <div class="text-xs text-stone-500 mt-1">模型: ${escapeHtml(a.model || '(默认)')} | 技能: ${escapeHtml(a.skill || '-')}</div>
      <div class="text-sm text-stone-600 mt-2 line-clamp-3">${escapeHtml(a.prompt || '(无提示词)')}</div>
      <div class="flex justify-end gap-2 mt-3">
        <button class="btn-link" data-act="edit">编辑</button>
        <button class="btn-link" data-act="del">删除</button>
      </div>
    `;
    el.querySelector('[data-act="edit"]').addEventListener('click', () => editAgentPrompt(a.id));
    el.querySelector('[data-act="del"]').addEventListener('click', async () => {
      if (!confirm('删除 Agent "' + a.name + '"?')) return;
      await api.agents.delete({ id: a.id });
      renderAgentsView();
    });
    wrap.appendChild(el);
  }
}

async function editAgentPrompt(id) {
  const list = await api.agents.list();
  const a = (list || []).find(x => x.id === id);
  if (!a) return;
  const newName = prompt('Agent 名称', a.name);
  if (newName === null) return;
  const newModel = prompt('模型 (留空用默认)', a.model) ?? a.model;
  const newSkill = prompt('固定技能名 (留空不用)', a.skill) ?? a.skill;
  const newPrompt = prompt('系统提示词', a.prompt) ?? a.prompt;
  await api.agents.save({ id, name: newName, model: newModel, skill: newSkill, prompt: newPrompt, toolGroups: a.toolGroups });
  renderAgentsView();
}

// ---- Vectors ----
async function renderVectorsView() {
  const stats = await api.vectors.stats();
  document.getElementById('vecStats').textContent =
    `索引路径: ${stats.index} | 共 ${stats.chunks} 块`;
  document.getElementById('vecImport').addEventListener('click', async () => {
    if (!chapterState.chapterId) { alert('先在章节视图选一章'); return; }
    const r = await fetch('/api/chapters/' + chapterState.chapterId);
    const c = await r.json();
    const source = document.getElementById('vecSource').value || ('chapter-' + c.id);
    await api.vectors.import({ source, text: c.content || '' });
    showToast('已导入');
    renderVectorsView();
  });
  document.getElementById('vecSearch').addEventListener('click', async () => {
    const q = document.getElementById('vecQuery').value;
    if (!q) return;
    const hits = await api.vectors.search({ query: q, topK: 8 });
    const box = document.getElementById('vecHits');
    box.innerHTML = '';
    for (const h of (hits || [])) {
      const el = document.createElement('div');
      el.className = 'p-3 border border-stone-200 rounded bg-stone-50';
      el.innerHTML = `<div class="text-xs text-stone-500">${escapeHtml(h.source)} · 分数 ${h.score.toFixed(2)}</div>
        <div class="text-sm mt-1">${escapeHtml(h.snippet)}…</div>`;
      box.appendChild(el);
    }
    if (!hits || !hits.length) box.innerHTML = '<div class="text-sm text-stone-500">无命中</div>';
  });
}

// ---- Skills ----
async function renderSkillsView() {
  const list = await api.skills.list();
  const wrap = document.getElementById('skillList');
  wrap.innerHTML = '';
  if (!list || !list.length) {
    wrap.innerHTML = '<div class="text-sm text-stone-500">还没有技能。在数据目录的 <code>skills/&lt;name&gt;/SKILL.md</code> 里写一个试试。</div>';
    return;
  }
  for (const s of list) {
    const el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = `<div class="text-base font-semibold">${escapeHtml(s.name)}</div>
      <div class="text-xs text-stone-500 mt-1">${escapeHtml(s.path)}</div>
      <div class="text-sm text-stone-600 mt-2">${escapeHtml(s.summary || '')}</div>`;
    wrap.appendChild(el);
  }
}

// ---- Settings ----
async function renderSettingsView() {
  const cfg = await api.config.get();
  document.getElementById('cfgBaseURL').value = cfg.baseURL || '';
  document.getElementById('cfgApiKey').value = cfg.apiKey || '';
  document.getElementById('cfgModel').value = cfg.model || '';
  document.getElementById('cfgSave').addEventListener('click', async () => {
    const newCfg = {
      baseURL: document.getElementById('cfgBaseURL').value.trim(),
      apiKey: document.getElementById('cfgApiKey').value.trim(),
      model: document.getElementById('cfgModel').value.trim(),
    };
    await api.config.set(newCfg);
    showToast('已保存');
  });
  document.getElementById('cfgTest').addEventListener('click', async () => {
    const out = document.getElementById('cfgTestResult');
    out.textContent = '测试中…';
    try {
      const r = await api.llm.test({
        baseURL: document.getElementById('cfgBaseURL').value.trim(),
        apiKey: document.getElementById('cfgApiKey').value.trim(),
        model: document.getElementById('cfgModel').value.trim(),
      });
      out.textContent = r.ok ? ('OK: ' + (r.content || '').slice(0, 40)) : ('失败: ' + r.error);
    } catch (e) {
      out.textContent = '失败: ' + e.message;
    }
  });
}

// ---- utils ----
function escapeHtml(s) {
  return (s || '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

let toastTimer = null;
function showToast(msg, isError) {
  let t = document.getElementById('toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'toast';
    t.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#1c1917;color:#fafaf9;padding:8px 16px;border-radius:8px;font-size:13px;z-index:9999;';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.style.background = isError ? '#b91c1c' : '#1c1917';
  t.style.display = 'block';
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.display = 'none'; }, 1800);
}

// 启动
showView('books');
