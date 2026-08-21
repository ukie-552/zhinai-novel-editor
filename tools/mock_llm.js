'use strict';
// Mock OpenAI 兼容服务：本地端到端测试用
const http = require('node:http');
const port = parseInt(process.argv[2] || '19001', 10);
http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    if (body.includes('"stream":true')) {
      const chunks = ['这是', '一段由', 'Mock', '模型', '流式返回的', '测试内容。', '\n\n第二段。'];
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      let i = 0;
      const t = setInterval(() => {
        if (i >= chunks.length) { clearInterval(t); res.write('data: [DONE]\n\n'); res.end(); return; }
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: chunks[i] }, finish_reason: null }] })}\n\n`);
        i++;
      }, 15);
    } else {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: '连接成功' } }] }));
    }
  });
}).listen(port, '127.0.0.1', () => console.log('MOCK LLM on ' + port));
