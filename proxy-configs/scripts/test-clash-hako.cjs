// Node >= 24. No dependencies. Synthetic nodes only; never opens a proxy tunnel.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const zlib = require('node:zlib');
const os = require('node:os');
const cp = require('node:child_process');
const code = fs.readFileSync(path.join(__dirname, '../Clash_Hako_V26.00.js'), 'utf8');
let passed = 0;
function run(input) {
  const ctx = {input: JSON.parse(JSON.stringify(input))};
  vm.runInNewContext(code + '\nvar before = JSON.stringify(input); var output = main(input); var unchanged = before === JSON.stringify(input);', ctx, {timeout: 5000});
  assert(ctx.unchanged, 'input must not be mutated');
  return JSON.parse(JSON.stringify(ctx.output));
}
function node(name) { return {name, type:'trojan', server:'node.example.invalid', port:443, password:'TEST-ONLY-NOT-A-CREDENTIAL', sni:'cert.example.invalid', 'skip-cert-verify':false}; }
function fixture(names) {
  return {proxies:names.map(node), 'proxy-providers':{}, mode:'global', 'allow-lan':true,
    dns:{enable:true, ipv6:false, 'enhanced-mode':'fake-ip', nameserver:['https://dns.alidns.com/dns-query'], 'proxy-server-nameserver':['223.5.5.5']},
    tun:{stack:'gvisor'}, hosts:{'local.example.invalid':'192.168.1.2'}, ipv6:false,
    profile:{'store-fake-ip':true}, 'proxy-groups':[{name:'OLD',type:'select',proxies:names}],
    rules:['MATCH,OLD'], 'rule-providers':{OldSet:{type:'inline',behavior:'domain',payload:['+.example.invalid']}}};
}
const builtins = new Set(['DIRECT','REJECT','REJECT-DROP','PASS','PASS-RULE','COMPATIBLE','GLOBAL']);
function validate(config) {
  const nodes = new Set(config.proxies.map(p => p.name));
  const groups = new Map(config['proxy-groups'].map(g => [g.name,g]));
  assert.equal(groups.size,config['proxy-groups'].length);
  const known = new Set([...nodes, ...groups.keys(), ...builtins]);
  for (const group of groups.values()) {
    assert(!nodes.has(group.name));
    assert(['select','fallback','url-test'].includes(group.type));
    assert(group.proxies.length > 0, 'no empty groups');
    for (const n of group.proxies) assert(known.has(n), 'dangling member: '+n);
    if (group.type !== 'select') {
      assert(group.url.startsWith('https://'));
      assert.equal(group['expected-status'],'204');
      assert(group.interval >= 60 && group.timeout === 5000);
      assert(!group.proxies.includes('DIRECT'));
    }
  }
  function walk(name, stack) {
    assert(!stack.includes(name),'group cycle');
    if(groups.has(name)) for(const member of groups.get(name).proxies) walk(member,[...stack,name]);
  }
  for(const name of groups.keys()) walk(name,[]);
  for(const rule of config.rules) {
    const parts = rule.split(',');
    const target = parts.at(-1) === 'no-resolve' ? parts.at(-2) : parts.at(-1);
    assert(known.has(target),'undefined rule target '+target);
    if(parts[0]==='RULE-SET') assert(config['rule-providers'][parts[1]]);
  }
  assert.equal(config.rules.at(-1),'MATCH,QXH-代理');
  assert.equal(config.mode,'rule'); assert.equal(config['allow-lan'],false);
  assert.equal(Object.keys(config['rule-providers']).length,10);
  const paths = new Set();
  for(const p of Object.values(config['rule-providers'])) {
    assert.equal(p.format,'mrs'); assert.equal(p.proxy,'QXH-代理');
    assert(!paths.has(p.path)); paths.add(p.path);
    assert(p.url.startsWith('https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/') ||
      p.url==='https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockmihomo.mrs');
  }
}
function test(name, fn) { fn(); passed++; console.log('PASS '+name); }
function group(cfg,name) { return cfg['proxy-groups'].find(g=>g.name===name); }
// A deliberately limited rule evaluator for the domains/logic generated here.
// Remote sets are injected fixtures: this is NOT a native-core or live route test.
function route(cfg, domain, network='TCP', port=443, remote=[], adSelection='REJECT') {
  const suffix = d => domain===d || domain.endsWith('.'+d);
  for(const rule of cfg.rules) {
    const p = rule.split(','); let hit=false;
    if(p[0]==='DOMAIN') hit=domain===p[1];
    if(p[0]==='DOMAIN-SUFFIX') hit=suffix(p[1]);
    if(p[0]==='RULE-SET') hit=remote.includes(p[1]);
    if(p[0]==='MATCH') hit=true;
    if(p[0]==='AND') {
      const match=rule.match(/^AND,\(\(DOMAIN-SUFFIX,([^()]+)\),\(NETWORK,UDP\),\(DST-PORT,443\)\),REJECT$/);
      assert(match,'unexpected AND syntax');
      hit=suffix(match[1]) && network==='UDP' && port===443;
    }
    if(hit) {
      let target=p.at(-1)==='no-resolve'?p.at(-2):p.at(-1);
      if(target==='QXH-广告') { if(adSelection==='PASS') continue; return 'REJECT'; }
      return target;
    }
  }
}
const sample = fixture(['US01','JP-01','JP-02','SG1','TW 1','HK-01','unknown-1']);
const output=run(sample);
test('full airport: references, DAG, providers and policy',()=>validate(output));
test('DNS/TUN/hosts/IPv6/node credentials preserved',()=>{
  for(const key of ['dns','tun','hosts','ipv6','proxies']) assert.deepEqual(output[key],sample[key]);
  assert.equal(output.profile['store-fake-ip'],true);
});
test('idempotent output',()=>assert.deepEqual(run(output),output));
test('single node / one region does not create empty fallback',()=>validate(run(fixture(['JP-1']))));
test('airport replacement removes all former nodes',()=>{
  const b=run(fixture(['US-New','SG-New'])); validate(b);
  assert(!JSON.stringify(b).includes('JP-01'));
});
test('US boundaries and ambiguous transit names',()=>{
  const r=run(fixture(['US01','[US] 02','USA-03','BUSINESS','RUS-01','AUS-1','HK-US transit','🇺🇸 04']));
  assert.deepEqual(group(r,'QXH-US').proxies,['US01','[US] 02','USA-03','🇺🇸 04']);
});
test('unknown/HK-only AI requires explicit selection',()=>{
  const r=run(fixture(['HK-1','unknown'])); validate(r);
  assert.equal(group(r,'QXH-AI').proxies[0],'REJECT');
  assert(group(r,'QXH-AI').proxies.includes('QXH-手动'));
});
test('YouTube two-level Google probes, stable tolerance',()=>{
  assert.equal(group(output,'QXH-YT故障转移').interval,60);
  for(const n of group(output,'QXH-YT故障转移').proxies) {
    const g=group(output,n); assert.equal(g.type,'url-test'); assert.equal(g.interval,120);
    assert.equal(g.tolerance,150); assert.equal(g.url,'https://www.gstatic.com/generate_204');
  }
});
test('AI stable ordering has no HK / DIRECT automatic fallback',()=>{
  assert.deepEqual(group(output,'QXH-AI稳定').proxies,['US01','JP-01','JP-02','SG1','TW 1']);
  assert.equal(group(output,'QXH-AI稳定').type,'fallback');
});
test('TLS verification is hardened, never disabled',()=>{
  const f=fixture(['US-1']); f.proxies[0]['skip-cert-verify']=true;
  assert.equal(run(f).proxies[0]['skip-cert-verify'],false);
  assert.equal(f.proxies[0]['skip-cert-verify'],true);
});
for(const [label,input] of [
  ['null',null],['array',[]],['empty',{}],['no nodes',fixture([])],
  ['duplicate',fixture(['US-1','US-1'])],['reserved',fixture(['DIRECT'])],
  ['prefix collision',fixture(['QXH-代理'])]
]) test('reject '+label,()=>assert.throws(()=>run(input),/QX Hako:/));
test('provider-only / mixed providers fail explicitly',()=>{
  const f=fixture(['US1']); f['proxy-providers']={airport:{type:'http',url:'https://subscription.example.invalid'}};
  assert.throws(()=>run(f),/proxy-providers/);
});
test('missing port and non-node outbound fail',()=>{
  const f=fixture(['US1']); delete f.proxies[0].port; assert.throws(()=>run(f),/server\/port/);
  f.proxies[0]= {name:'US1',type:'direct'}; assert.throws(()=>run(f),/非机场/);
});
test('old DNS group reference fails instead of dangling',()=>{
  const f=fixture(['US1']); f.dns.nameserver=['https://dns.google/dns-query#OLD'];
  assert.throws(()=>run(f),/旧策略组/);
});
test('old DNS policy ruleset fails explicitly',()=>{
  const f=fixture(['US1']); f.dns['nameserver-policy']={'rule-set:OldSet':['223.5.5.5']};
  assert.throws(()=>run(f),/旧规则集/);
});
test('old TUN address-set fails explicitly',()=>{
  const f=fixture(['US1']); f.tun['route-address-set']=['OldSet'];
  assert.throws(()=>run(f),/旧规则集/);
});
test('node-to-node dialer chain preserved; dangling/cycle rejected',()=>{
  const f=fixture(['US1','JP1']); f.proxies[0]['dialer-proxy']='JP1'; validate(run(f));
  f.proxies[1]['dialer-proxy']='US1'; assert.throws(()=>run(f),/循环/);
  f.proxies[1]['dialer-proxy']='OLD'; assert.throws(()=>run(f),/旧策略组/);
});
test('domestic connectivity protection precedes ad rejection',()=>{
  for(const d of ['short.weixin.qq.com','api.weibo.cn','www.zhihu.com','courier.push.apple.com'])
    assert.equal(route(output,d,'TCP',443,['QXH-Ads']),'DIRECT');
});
test('YouTube TCP routes; UDP 443 rejected; other UDP untouched',()=>{
  assert.equal(route(output,'r1.googlevideo.com'),'QXH-YouTube');
  assert.equal(route(output,'youtubei.googleapis.com'),'QXH-YouTube');
  assert.equal(route(output,'r1.googlevideo.com','UDP'),'REJECT');
  assert.equal(route(output,'r1.googlevideo.com','UDP',123),'QXH-YouTube');
  assert.equal(route(output,'node.example.invalid','UDP'),'QXH-代理');
});
test('Gemini, GPT, Claude precede Google/CN sets',()=>{
  for(const n of ['Gemini','OpenAI','Claude'])
    assert.equal(route(output,'service.example.invalid','TCP',443,['QXH-'+n,'QXH-Google','QXH-CN']),'QXH-AI');
});
test('ad bypass resumes routing, not blanket direct',()=>{
  assert.equal(route(output,'ads.example.invalid','TCP',443,['QXH-Ads']),'REJECT');
  assert.equal(route(output,'ads.example.invalid','TCP',443,['QXH-Ads'],'PASS'),'QXH-代理');
  assert.equal(route(output,'ads.example.invalid','TCP',443,['QXH-Ads','QXH-CN'],'PASS'),'DIRECT');
});
test('large normal subscription stays inside 5-second script budget',()=>validate(run(fixture(Array.from({length:1000},(_,i)=>'US-'+i)))));

async function online(corePath) {
  const dir = corePath ? fs.mkdtempSync(path.join(os.tmpdir(),'qxh-core-check-')) : null;
  const resources = {};
  for(const [name,p] of Object.entries(output['rule-providers'])) {
    const r=await fetch(p.url,{signal:AbortSignal.timeout(30000)});
    assert.equal(r.status,200,name);
    const compressed=Buffer.from(await r.arrayBuffer());
    assert(compressed.length>0 && compressed.length<16*1024*1024);
    const data=zlib.zstdDecompressSync(compressed,{maxOutputLength:16*1024*1024});
    assert.equal(data.subarray(0,4).toString('hex'),'4d525301','MRS v1 header');
    assert.equal(data[4],p.behavior==='domain'?0:1,'MRS behavior');
    const count=data.readBigInt64BE(5); assert(count>0n);
    const extra=Number(data.readBigInt64BE(13)); assert(extra>=0 && 21+extra<data.length);
    assert.equal(data[21+extra],1,'domain/ip-set format version');
    if(dir) { resources[name]=path.join(dir,name+'.mrs'); fs.writeFileSync(resources[name],compressed); }
    console.log('ONLINE '+name+' status=200 compressed='+compressed.length+' decoded='+data.length+' rules='+count);
  }
  for(const url of ['https://cp.cloudflare.com/generate_204','https://www.gstatic.com/generate_204']) {
    const r=await fetch(url,{signal:AbortSignal.timeout(30000)});
    assert.equal(r.status,204,url); console.log('ONLINE probe 204 '+url);
  }
  if(corePath) {
    assert(fs.existsSync(corePath),'core executable missing');
    const domainSets = {};
    for(const [name,p] of Object.entries(output['rule-providers'])) {
      const textPath=path.join(dir,name+'.txt');
      const result=cp.spawnSync(corePath,['convert-ruleset',p.behavior,'mrs',resources[name],textPath],
        {encoding:'utf8',timeout:60000,windowsHide:true});
      assert.equal(result.status,0,'native MRS decode '+name+': '+result.stderr);
      const lines=fs.readFileSync(textPath,'utf8').trim().split(/\r?\n/);
      assert(lines.length>0,'empty decoded ruleset');
      if(p.behavior==='domain') domainSets[name]=lines;
      console.log('CORE MRS decode PASS '+name);
    }
    function remoteFor(domain) {
      return Object.keys(domainSets).filter(name=>domainSets[name].some(rule=>{
        if(rule.startsWith('+.')) return domain===rule.slice(2) || domain.endsWith(rule.slice(1));
        return domain===rule;
      }));
    }
    for(const [domain,target] of [['gemini.google.com','QXH-AI'],['chatgpt.com','QXH-AI'],
      ['claude.ai','QXH-AI'],['youtube.com','QXH-YouTube'],['r1.googlevideo.com','QXH-YouTube'],
      ['youtubei.googleapis.com','QXH-YouTube'],['api.weibo.cn','DIRECT'],['www.zhihu.com','DIRECT'],
      ['short.weixin.qq.com','DIRECT'],['www.baidu.com','DIRECT']]) {
      assert.equal(route(output,domain,'TCP',443,remoteFor(domain)),target,'live ruleset fixture '+domain);
    }
    console.log('LIVE DATA route fixtures PASS 10 (local evaluator, not actual traffic)');
    for(const [label,names] of [['multi',['US01','JP1','HK1']],['single',['JP1']],['unknown',['unknown']],['large',Array.from({length:1000},(_,i)=>'US-'+i)]]) {
      const candidate = run(fixture(names));
      for(const [name,p] of Object.entries(candidate['rule-providers'])) {
        p.type='file'; p.path=resources[name]; delete p.url; delete p.proxy; delete p.interval;
      }
      // JSON is a YAML subset. Same object is serialized to YAML by Hako's bridge.
      const file=path.join(dir,label+'.yaml'); fs.writeFileSync(file,JSON.stringify(candidate,null,2));
      const result=cp.spawnSync(corePath,['-t','-f',file,'-d',dir],{encoding:'utf8',timeout:60000,windowsHide:true});
      assert.equal(result.status,0,'native check '+label+': '+result.stdout+' '+result.stderr);
      console.log('CORE parse PASS '+label);
    }
    console.log('CORE test artifacts (synthetic only): '+dir);
  }
}
(async()=>{
  const coreIndex=process.argv.indexOf('--core');
  if(coreIndex>=0) assert(process.argv[coreIndex+1],'--core requires an executable path');
  if(process.argv.includes('--online')) await online(coreIndex>=0?process.argv[coreIndex+1]:null);
  console.log('PASS '+passed+' offline cases'+(process.argv.includes('--online')?' + 10 live MRS headers + 2 live probes':''));
  console.log('NOT TESTED: iOS JavaScriptCore / Hako native import, actual airport reachability, video continuity or ad removal.');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
