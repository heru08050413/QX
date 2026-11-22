// Isolated API contract fixtures for single-file Stash_Pro_V26.00.stoverride.
// No real phone traffic and no network access.
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
    $persistentStore: {read: k => store[k] || null, write: (v, k) => {store[k] = v; return true;}},
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
  for (let i = 0; i < 20 && !calls; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 1, '$done must be called exactly once');
  assert.notEqual(answer, undefined, 'no interrupt via bare $done');
  count++;
  return answer;
}

(async () => {
  const cfg = input.cfg;
  const rewriteRegexes = [];
  for (const line of cfg.http['url-rewrite']) {
    const parts = line.split(' ');
    assert.equal(parts.length, 3, 'invalid url-rewrite syntax: ' + line);
    rewriteRegexes.push(new RegExp(parts[0]));
  }
  const scriptRegexes = [];
  for (const hook of cfg.http.script) {
    scriptRegexes.push({name: hook.name, rx: new RegExp(hook.match)});
  }

  const code = cfg['script-providers']['stash-pro-ads'].payload;

  // 1. Weibo sdkad.php (JSON + trailing OK suffix)
  const sdkUrl = 'https://sdkapp.uve.weibo.com/interface/sdk/sdkad.php?v=1';
  const sdkBody = JSON.stringify({ads: [{id: 1}], background_delay_display_time: 5, show_push_splash_ad: true, keep: 'ok'}) + 'OK';
  let res = await run(code, sdkUrl, sdkBody);
  assert(res.body.endsWith('OK'), 'sdkad trailing OK preserved');
  let out = JSON.parse(res.body.slice(0, -2));
  assert.equal(out.ads.length, 0);
  assert.equal(out.background_delay_display_time, 86400000);
  assert.equal(out.show_push_splash_ad, false);
  assert.equal(out.keep, 'ok');

  // 2. Weibo wbpullad.lua & /2/!/client/openscreen
  const wbPullUrl = 'https://wbapp.uve.weibo.com/wbapplua/wbpullad.lua';
  out = JSON.parse((await run(code, wbPullUrl, JSON.stringify({cached_ad: {ads: [{id: 1}]}, keep: 42}))).body);
  assert.equal(out.cached_ad.ads.length, 0);
  assert.equal(out.keep, 42);

  const wbClientSplashUrl = 'https://api.weibo.cn/2/!/client/openscreen?v=1';
  out = JSON.parse((await run(code, wbClientSplashUrl, JSON.stringify({cached_ad: {ads: [{id: 2}]}, ads: [{id: 3}], show_push_splash_ad: true}))).body);
  assert.equal(out.cached_ad.ads.length, 0);
  assert.equal(out.ads.length, 0);
  assert.equal(out.show_push_splash_ad, false);

  // 3. Weibo timeline
  const wbUrl = 'https://api.weibo.cn/2/groups/timeline?count=20';
  out = JSON.parse((await run(code, wbUrl, JSON.stringify({statuses: [{id: 'normal', title: {type: 'likerecommend'}}, {mblogtype: 1}, {promotion: {type: 'ad'}}], next_cursor: 123}))).body);
  assert.equal(out.statuses.length, 1);
  assert.equal(out.statuses[0].id, 'normal');
  assert.equal(out.next_cursor, 123);
  out = JSON.parse((await run(code, wbUrl, JSON.stringify({items: [{category: 'feed', data: {mblogtype: 1}}, {category: 'feed', data: {id: 2}}, {category: 'other'}]}))).body);
  assert.equal(out.items.length, 2);

  // 4. Zhihu feed
  const zhUrl = 'https://api.zhihu.com/topstory/recommend?limit=20';
  out = JSON.parse((await run(code, zhUrl, JSON.stringify({data: [{type: 'feed_advert'}, {type: 'answer', answer_type: 'paid'}, {type: 'aggregation_card'}], paging: {next: 'cursor'}}))).body);
  assert.equal(out.data.length, 2);
  assert.equal(out.paging.next, 'cursor');
  out = JSON.parse((await run(code, zhUrl, JSON.stringify({data: {data: [{type: 'ad'}, {type: 'answer'}]}}))).body);
  assert.equal(out.data.data.length, 1);

  // 5. Xiaohongshu feed & splash_config
  const xhUrl = 'https://edith.xiaohongshu.com/api/sns/v1/homefeed?num=20';
  const xhSplashUrl = 'https://edith.xiaohongshu.com/api/sns/v1/system_service/splash_config';
  out = JSON.parse((await run(code, xhUrl, JSON.stringify({data: {items: [{model_type: 'ad'}, {model_type: 'note'}, {model_type: 'live'}]}}))).body);
  assert.equal(out.data.items.length, 2);
  out = JSON.parse((await run(code, xhSplashUrl, JSON.stringify({data: {ads_groups: [{ads: [1]}], other: 7}}))).body);
  assert.equal(out.data.ads_groups.length, 0);
  assert.equal(out.data.other, 7);

  // 6. Taobao splash video, splash image, and poplayer
  const tbVideoUrl = 'https://guide-acs.m.taobao.com/gw/mtop.taobao.cloudvideo.video.query/1.0/';
  out = JSON.parse((await run(code, tbVideoUrl, JSON.stringify({data: {duration: '5', resources: ['v1'], caches: ['c1'], respTimeInMs: '100', keep: 1}}))).body);
  assert.equal(out.data.duration, '0');
  assert.equal(out.data.resources.length, 0);
  assert.equal(out.data.caches.length, 0);
  assert.equal(out.data.respTimeInMs, '3818332800000');
  assert.equal(out.data.keep, 1);

  const tbSplashUrl = 'https://guide-acs.m.taobao.com/gw/mtop.taobao.wireless.home.splash.awesome.get/1.0/';
  out = JSON.parse((await run(code, tbSplashUrl, JSON.stringify({
    data: {containers: {splash_home_base: {base: {sections: [{bizData: {'taobao-splash': {data: [{waitTime: '5', times: '3', hotStart: 'true', imgUrl: 'https://img', videoUrl: 'https://vid'}]}}}]}}}}
  }))).body);
  const tbItem = out.data.containers.splash_home_base.base.sections[0].bizData['taobao-splash'].data[0];
  assert.equal(tbItem.waitTime, '0');
  assert.equal(tbItem.times, '0');
  assert.equal(tbItem.hotStart, 'false');
  assert.equal(tbItem.imgUrl, '');
  assert.equal(tbItem.videoUrl, '');
  assert.equal(tbItem.startTime, '3818332800000');

  const tbPopUrl = 'https://poplayer.template.alibaba.com/campaign2026.json';
  out = JSON.parse((await run(code, tbPopUrl, JSON.stringify({res: {images: ['a'], videos: ['b']}, mainRes: {images: ['c']}, enable: true, keep: 3}))).body);
  assert.equal(out.res.images.length, 0);
  assert.equal(out.res.videos.length, 0);
  assert.equal(out.mainRes.images.length, 0);
  assert.equal(out.enable, false);
  assert.equal(out.keep, 3);

  // 7. JD splash only (functionId=start)
  const jdSplashUrl = 'https://api.m.jd.com/client.action?functionId=start&client=apple';
  out = JSON.parse((await run(code, jdSplashUrl, JSON.stringify({images: [{url: 'ad'}], showTimesDaily: 3, keep: 9}))).body);
  assert.equal(out.images.length, 0);
  assert.equal(out.showTimesDaily, 0);
  assert.equal(out.keep, 9);

  // 8. Defensive pass-through on empty / malformed / non-200 / unchanged responses
  for (const body of ['', '<html>error</html>', 'null', '[]', '{"data":null}', '{"data":[{"type":"answer"}]}']) {
    assert.equal(JSON.stringify(await run(code, zhUrl, body)), '{}');
  }
  assert.equal(JSON.stringify(await run(code, sdkUrl, 'not-json')), '{}');
  assert.equal(JSON.stringify(await run(code, zhUrl, '{"data":[{"type":"ad"}]}', {context: {$response: {status: 503, body: '{"data":[{"type":"ad"}]}'}}})), '{}');

  // 9. Hooks & url-rewrite MUST NEVER touch login, payment, order, or comments
  const protectedUrls = [
    'https://api.weibo.cn/2/account/login',
    'https://api.zhihu.com/questions/1/answers',
    'https://edith.xiaohongshu.com/api/sns/v1/note/feed',
    'https://api.m.jd.com/client.action?functionId=myOrderInfo',
    'https://api.m.jd.com/client.action?functionId=newWallet',
    'https://acs.m.taobao.com/gw/mtop.order.query/1.0/',
    'https://acs.m.taobao.com/gw/mtop.trade.buildOrder/4.0/',
  ];
  for (const u of protectedUrls) {
    assert(!scriptRegexes.some(h => h.rx.test(u)), 'script hook touched protected URL: ' + u);
    assert(!rewriteRegexes.some(rx => rx.test(u)), 'url-rewrite touched protected URL: ' + u);
  }

  // 10. All positive splash & feed URLs must match stash-pro-ads
  for (const u of [sdkUrl, wbPullUrl, wbClientSplashUrl, wbUrl, zhUrl, xhUrl, xhSplashUrl, tbVideoUrl, tbSplashUrl, tbPopUrl, jdSplashUrl]) {
    assert(scriptRegexes.some(h => h.name === 'stash-pro-ads' && h.rx.test(u)), 'missing stash-pro-ads match for ' + u);
  }

  // 11. Remote YouTube contract tests (--online mode)
  if (input.remote['yt-request']) {
    const req = input.remote['yt-request'];
    let request = {url: 'https://youtubei.googleapis.com/youtubei/v1/log_event', headers: {'User-Agent': 'com.google.ios.youtube', 'Content-Encoding': 'gzip', 'X-YouTube-Hot-Hash-Data': 'test'}, body: new Uint8Array()};
    out = await run(req, '', '', {context: {$request: request}});
    assert.equal(out.headers['Content-Encoding'], undefined);
    assert.equal(out.headers['X-YouTube-Hot-Hash-Data'], undefined);

    request = {url: 'https://rr1.googlevideo.com/initplayback?foo=1&ack=1', headers: {'User-Agent': 'com.google.ios.youtube'}, body: new Uint8Array()};
    out = await run(req, '', '', {context: {$request: request}});
    assert.equal(out.response.status, 200);
    assert(out.response.body instanceof Uint8Array);

    request.body = new Uint8Array([26, 3, 42, 1, 1]);
    out = await run(req, '', '', {context: {$request: request}, store: {YouTubeConfig: JSON.stringify({youtube: {clientKey: 'fixture-key', encryptKey: 'AQ=='}})}});
    assert(out.url.startsWith('https://init-stream.maasea.workers.dev/'));
    assert(out.url.includes('target='));

    const ytResp = input.remote['yt-response'];
    const ytHook = cfg.http.script.find(h => h.name === 'yt-response');
    out = await run(ytResp, 'https://youtubei.googleapis.com/youtubei/v1/player', new Uint8Array(), {context: {$argument: ytHook.argument}});
    assert(out && typeof out === 'object');
  }

  console.log(`PASS ${count} isolated script executions, ${rewriteRegexes.length} url-rewrites & ${scriptRegexes.length} script hooks checked (not native Stash or real ad traffic).`);
})().catch(error => {console.error(error); process.exitCode = 1;});
