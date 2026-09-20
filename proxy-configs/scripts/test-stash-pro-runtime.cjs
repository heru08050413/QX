// Isolated API contract fixtures. No real phone traffic and no network access.
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
let count = 0;
async function run(code, url, body, extra = {}) {
  let calls = 0, answer;
  const store = extra.store || {};
  const context = {
    $request: {url, method: 'POST', headers: {'User-Agent': 'com.google.ios.youtube/fixture'}, body: new Uint8Array()},
    $response: {status: 200, headers: {}, body},
    $argument: '{}',
    $environment: {'stash-version': '3.4.1'},
    $persistentStore: {read: k => store[k] || null, write: (v,k) => {store[k]=v; return true;}},
    $notification: {post() {}},
    $httpClient: new Proxy({}, {get() {return () => {throw Error('external request forbidden in fixtures');};}}),
    $done: value => {calls++; answer = value;},
    console: {log() {}, warn() {}, error() {}},
    TextEncoder, TextDecoder, Uint8Array, ArrayBuffer, URL,
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
  };
  Object.assign(context, extra.context || {});
  vm.runInNewContext(code, context, {timeout: 3000});
  for (let i=0; i<20 && !calls; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 1, '$done exactly once');
  assert.notEqual(answer, undefined, 'no interrupt via bare $done');
  count++;
  return answer;
}
(async () => {
  for (const cfg of [input.app, input.yt]) {
    for (const hook of cfg.http.script) new RegExp(hook.match);
  }
  const code = input.app['script-providers']['precise-app-ads'].payload;
  const wb = 'https://api.weibo.cn/2/groups/timeline?count=20';
  const zh = 'https://api.zhihu.com/topstory/recommend?limit=20';
  const xh = 'https://edith.xiaohongshu.com/api/sns/v1/homefeed?num=20';
  const wbFixture = {statuses:[{id:'normal',title:{type:'likerecommend'}},{mblogtype:1},{promotion:{type:'ad'}}], next_cursor:123};
  let out = JSON.parse((await run(code, wb, JSON.stringify(wbFixture))).body);
  assert.equal(out.statuses.length, 1); assert.equal(out.statuses[0].id,'normal'); assert.equal(out.next_cursor,123);
  out = JSON.parse((await run(code, wb, JSON.stringify({items:[{category:'feed',data:{mblogtype:1}},{category:'feed',data:{id:2}},{category:'other'}]}))).body);
  assert.equal(out.items.length,2);
  out = JSON.parse((await run(code, zh, JSON.stringify({data:[{type:'feed_advert'},{type:'answer',answer_type:'paid'},{type:'aggregation_card'}],paging:{next:'cursor'}}))).body);
  assert.equal(out.data.length,2); assert.equal(out.paging.next,'cursor');
  out = JSON.parse((await run(code, zh, JSON.stringify({data:{data:[{type:'ad'},{type:'answer'}]}}))).body);
  assert.equal(out.data.data.length,1);
  out = JSON.parse((await run(code, xh, JSON.stringify({data:{items:[{model_type:'ad'},{model_type:'note'},{model_type:'live'}]}}))).body);
  assert.equal(out.data.items.length,2);
  out = JSON.parse((await run(code, 'https://edith.xiaohongshu.com/api/sns/v1/system_service/splash_config', JSON.stringify({data:{ads_groups:[{ads:[1]}],other:7}}))).body);
  assert.equal(out.data.ads_groups.length,0); assert.equal(out.data.other,7);
  for (const body of ['', '<html>error</html>', 'null', '[]', '{"data":null}', '{"data":[{"type":"answer"}]}']) {
    assert.equal(JSON.stringify(await run(code, zh, body)), '{}');
  }
  assert.equal(JSON.stringify(await run(code, zh, '{"data":[{"type":"ad"}]}', {context:{$response:{status:503,body:'{"data":[{"type":"ad"}]}'}}})), '{}');
  // Hooks must never touch login, payment, comments or normal video media bodies.
  for (const url of ['https://api.weibo.cn/2/account/login','https://api.zhihu.com/questions/1/answers','https://edith.xiaohongshu.com/api/sns/v1/note/feed']) {
    assert(!input.app.http.script.some(h => new RegExp(h.match).test(url)), url);
  }
  for (const url of [wb,zh,xh]) assert(input.app.http.script.some(h => new RegExp(h.match).test(url)), url);
  if (input.remote['yt-request']) {
    const req = input.remote['yt-request'];
    let request = {url:'https://youtubei.googleapis.com/youtubei/v1/log_event', headers:{'User-Agent':'com.google.ios.youtube','Content-Encoding':'gzip','X-YouTube-Hot-Hash-Data':'test'},body:new Uint8Array()};
    out = await run(req, '', '', {context:{$request:request}});
    assert.equal(out.headers['Content-Encoding'],undefined);
    assert.equal(out.headers['X-YouTube-Hot-Hash-Data'],undefined);
    request = {url:'https://rr1.googlevideo.com/initplayback?foo=1&ack=1',headers:{'User-Agent':'com.google.ios.youtube'},body:new Uint8Array()};
    out = await run(req, '', '', {context:{$request:request}});
    assert.equal(out.response.status,200); assert(out.response.body instanceof Uint8Array);
    request.body = new Uint8Array([26,3,42,1,1]);
    out = await run(req, '', '', {context:{$request:request}, store:{YouTubeConfig:JSON.stringify({youtube:{clientKey:'fixture-key',encryptKey:'AQ=='}})}});
    assert(out.url.startsWith('https://init-stream.maasea.workers.dev/'));
    assert(out.url.includes('target='));
    const response = input.remote['yt-response'];
    out = await run(response, 'https://youtubei.googleapis.com/youtubei/v1/player', new Uint8Array(), {context:{$argument:input.yt.http.script[0].argument}});
    assert(out && typeof out === 'object');
  }
  console.log(`PASS ${count} isolated script executions; routing/regex contracts checked (not native Stash or real ad traffic).`);
})().catch(error => {console.error(error); process.exitCode=1;});
