/*
 * QX / Clash by Hako — V26.00 revision 2, 2026-11-14.
 * Import as an Override Script, NOT as an airport subscription or YAML profile.
 * main(config) consumes an airport's full Clash/mihomo profile with proxies.
 * Keeps DNS/TUN and credentials local. No fetch, telemetry, MITM or body rewrite.
 * See Clash_Hako_README.md for scope, installation and actual test boundaries.
 */
function main(config) {
  "use strict";
  function fail(message) { throw new Error("QX Hako: " + message); }
  function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
  if (!object(config)) fail("需要完整 Clash/mihomo 配置对象。");
  var out = JSON.parse(JSON.stringify(config));
  // Runtime-only providers are not expanded by JavaScriptCore. Never guess their nodes.
  if (Object.keys(out["proxy-providers"] || {}).length) {
    fail("此版需要含 proxies 的完整机场配置；不支持仅在运行时加载的 proxy-providers。请向机场选择 Clash/mihomo 完整订阅输出。");
  }
  if (!Array.isArray(out.proxies) || !out.proxies.length) fail("没有机场节点，请先导入完整机场订阅，再绑定脚本。");
  if (out.proxies.length > 2000) fail("节点超过 2000，请先精简订阅，避免 iPhone 资源过载。");
  var builtins = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE", "GLOBAL"];
  var names = Object.create(null);
  out.proxies.forEach(function (p) {
    if (!object(p) || typeof p.name !== "string" || !p.name.trim() || typeof p.type !== "string") fail("节点条目缺少 name/type。");
    if (names[p.name] || builtins.indexOf(p.name) >= 0 || p.name.indexOf("QXH-") === 0) fail("节点重名或占用保留名称；请在机场订阅中修正。");
    if (["direct", "reject", "dns", "compatible", "pass"].indexOf(p.type.toLowerCase()) >= 0) fail("proxies 中含非机场出站，请使用纯机场节点配置。");
    if (typeof p.server !== "string" || !p.server || !Number.isInteger(p.port) || p.port < 1 || p.port > 65535) fail("节点缺少有效 server/port。");
    names[p.name] = p;
    // Never ship disabled TLS verification from an airport into the working copy.
    if (Object.prototype.hasOwnProperty.call(p, "skip-cert-verify")) p["skip-cert-verify"] = false;
  });
  var visited = Object.create(null), visiting = Object.create(null);
  function checkChain(name) {
    if (visited[name]) return;
    if (visiting[name]) fail("节点 dialer-proxy 存在循环。");
    visiting[name] = true;
    var target = names[name]["dialer-proxy"];
    if (target && target !== "DIRECT") {
      if (!names[target]) fail("dialer-proxy 依赖旧策略组；不能安全覆盖，请先简化机场配置。");
      checkChain(target);
    }
    visiting[name] = false; visited[name] = true;
  }
  Object.keys(names).forEach(checkChain);

  var all = out.proxies.map(function (p) { return p.name; });
  var junk = /剩余|到期|过期|官网|流量|套餐|网站|售后|客服|更新|expire|traffic|reset/i;
  var poolNodes = all.filter(function (n) { return !junk.test(n); });
  if (!poolNodes.length) poolNodes = all;
  var G = "QXH-代理", MAN = "QXH-手动", AUTO = "QXH-自动";
  var YT = "QXH-YouTube", YTF = "QXH-YT故障转移", AI = "QXH-AI";
  var GOOGLE = "QXH-Google", TG = "QXH-Telegram", ADS = "QXH-广告";
  var google = "https://www.gstatic.com/generate_204";
  var groups = [];
  function select(name, members) { groups.push({name:name, type:"select", proxies:members}); }
  function check(name, type, members, url, interval) {
    var group = {name:name, type:type, proxies:members, url:url, interval:interval,
      timeout:5000, lazy:true, "expected-status":"204"};
    if (type === "url-test") group.tolerance = 150;
    groups.push(group);
  }
  // Boundaries accept US01 / [US] / US-HY2, but not RUS / AUS / BUSINESS.
  var regions = [
    ["JP", /日本|京日|苏日|沪日|上日|川日|深日|广日|东京|東京|大阪|🇯🇵|(?:^|[^a-z])(?:jp|japan|tokyo|osaka)(?=$|[^a-z])/i],
    ["SG", /新加坡|沪新|京新|深新|杭新|广新|狮城|獅城|🇸🇬|(?:^|[^a-z])(?:sg|sgp|singapore)(?=$|[^a-z])/i],
    ["TW", /台湾|台灣|台北|台中|新北|彰化|🇹🇼|(?:^|[^a-z])(?:tw|twn|taiwan|taipei)(?=$|[^a-z])/i],
    ["HK", /香港|深港|沪港|京港|🇭🇰|(?:^|[^a-z])(?:hk|hkg|hong[ _-]?kong)(?=$|[^a-z])/i],
    ["US", /美国|美國|沪美|美西|美东|美東|美中|洛杉矶|洛杉磯|圣何塞|西雅图|芝加哥|纽约|凤凰城|硅谷|🇺🇸|(?:^|[^a-z])(?:us|usa|united[ _-]?states|america|los[ _-]?angeles|silicon[ _-]?valley)(?=$|[^a-z])/i]
  ];
  var buckets = Object.create(null), used = Object.create(null), regionGroups = [], ytGroups = [];
  regions.forEach(function (r) {
    // Ambiguous multi-country labels stay in OTHER; names are hints, not IP geolocation.
    var members = poolNodes.filter(function (name) {
      return r[1].test(name) && regions.filter(function (x) { return x[1].test(name); }).length === 1;
    });
    buckets[r[0]] = members;
    if (!members.length) return;
    members.forEach(function (n) { used[n] = true; });
    var generalName = "QXH-" + r[0];
    regionGroups.push(generalName); ytGroups.push(generalName);
    check(generalName, "url-test", members, google, 300);
  });
  var others = poolNodes.filter(function (n) { return !used[n]; });
  if (others.length) {
    check("QXH-OTHER", "url-test", others, google, 300);
    regionGroups.push("QXH-OTHER");
    ytGroups.push("QXH-OTHER");
  }
  check(AUTO, "url-test", poolNodes, google, 300);
  check(YTF, "fallback", ytGroups, google, 120);
  // AI: stable priority rather than fastest-node rotation; no silent DIRECT fallback.
  var aiNodes = [].concat(buckets.US, buckets.JP, buckets.SG, buckets.TW);
  if (aiNodes.length) check("QXH-AI稳定", "fallback", aiNodes, google, 300);
  var aiRegions = ["US", "JP", "SG", "TW"].filter(function (r) { return buckets[r].length; })
    .map(function (r) { return "QXH-" + r; });
  select(G, [AUTO, MAN].concat(regionGroups));
  select(YT, [YTF, MAN].concat(ytGroups));
  select(AI, [aiNodes.length ? "QXH-AI稳定" : "REJECT", MAN].concat(aiRegions));
  select(GOOGLE, [G, MAN].concat(regionGroups));
  select(TG, [G, MAN]);
  // PASS is intentional: disabling ad rejection resumes subsequent routing, not DIRECT.
  select(ADS, ["REJECT", "PASS"]);
  select(MAN, all);

  var providers = {};
  function provider(name, category, file) {
    providers["QXH-" + name] = {type:"http", behavior:category === "geoip" ? "ipcidr" : "domain",
      format:"mrs", url:"https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/" + category + "/" + file + ".mrs",
      path:"./ruleset/qxh-" + name + ".mrs", interval:86400, proxy:G};
  }
  provider("Ads", "geosite", "category-ads-all");
  // One deduplicated ad feed, not several overlapping text lists in the iOS tunnel.
  providers["QXH-Ads"].url = "https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockmihomo.mrs";
  provider("CN", "geosite", "cn");
  provider("CNIP", "geoip", "cn");
  provider("YouTube", "geosite", "youtube");
  provider("OpenAI", "geosite", "openai");
  provider("Gemini", "geosite", "google-gemini");
  provider("Claude", "geosite", "anthropic");
  provider("Google", "geosite", "google");
  provider("Telegram", "geosite", "telegram");
  provider("TelegramIP", "geoip", "telegram");

  // Retaining a DNS/TUN/listener referring to groups/rulesets removed below is unsafe.
  var groupNames = groups.map(function (g) { return g.name; });
  var removedGroups = (out["proxy-groups"] || []).map(function (g) { return g.name; })
    .filter(function (n) { return groupNames.indexOf(n) < 0 && !names[n]; });
  var removedSets = Object.keys(out["rule-providers"] || {}).filter(function (n) { return !providers[n]; });
  function inspect(value, key) {
    if (typeof value === "string") {
      var fragments = value.split(/[#,;&=]/);
      if (removedGroups.some(function (n) { return fragments.indexOf(n) >= 0; })) fail("保留的网络字段引用旧策略组；请先移除该 DNS/出站绑定，不能盲目覆盖。");
      if (removedSets.some(function (n) { return value.indexOf("rule-set:" + n) >= 0 || (key && key.indexOf("rule-set:" + n) >= 0) || ((key || "").indexOf("address-set") >= 0 && value === n); })) fail("DNS/TUN 依赖旧规则集；请先简化网络配置。");
    } else if (Array.isArray(value)) value.forEach(function (v) { inspect(v, key); });
    else if (object(value)) Object.keys(value).forEach(function (k) { inspect(k, k); inspect(value[k], k); });
  }
  Object.keys(out).filter(function (k) {
    return ["proxy-groups", "rule-providers", "rules", "proxies", "proxy-providers", "profile"].indexOf(k) < 0;
  }).forEach(function (k) { inspect(out[k], k); });

  var rules = [];
  function domain(d, target) { rules.push("DOMAIN-SUFFIX," + d + "," + target); }
  ["lan", "local", "localhost", "home.arpa", "ts.net", "tailscale.com", "tailscale.io"].forEach(function (d) { domain(d, "DIRECT"); });
  ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4"].forEach(function (cidr) { rules.push("IP-CIDR," + cidr + ",DIRECT,no-resolve"); });
  ["::1/128", "fc00::/7", "fd7a:115c:a1e0::/48", "fe80::/10", "ff00::/8"].forEach(function (cidr) { rules.push("IP-CIDR6," + cidr + ",DIRECT,no-resolve"); });
  // Connectivity protection is deliberately narrower than all of qq.com/tencent.com.
  ["weixin.qq.com", "weixin.com", "wechat.com", "qq.com.cn", "teg.tencent-cloud.net", "wx.qq.com", "weixinbridge.com",
    "qpic.cn", "qlogo.cn", "weibo.cn", "weibo.com.cn", "weibo.com", "sinaimg.cn", "weibocdn.com",
    "zhihu.com", "zhimg.com", "push.apple.com", "cmpassport.com", "id6.me", "10099.com.cn"].forEach(function (d) { domain(d, "DIRECT"); });
  ["dns.weixin.qq.com", "amdc.alipay.com", "c-hzgt2.getui.com", "open.e.189.cn", "mdn.open.wo.cn",
    "opencloud.wostore.cn", "auth.wosms.cn", "sdkapp.uve.weibo.com", "wbapp.uve.weibo.com",
    "sdkapp.mob.uve.weibo.com", "wbapp.mob.uve.weibo.com"].forEach(function (d) { rules.push("DOMAIN," + d + ",DIRECT"); });
  domain("browser-intake-datadoghq.com", AI);
  domain("raw.githubusercontent.com", G);
  // High-frequency telemetry circuit-breaker (REJECT-DROP silences tight SDK reconnect loops).
  ["umc.danuoyi.alicdn.com", "Aisou.ialicdn.com"].forEach(function (d) { rules.push("DOMAIN," + d + ",REJECT-DROP"); });
  ["xz.fbcdn.net", "xy.fbcdn.net"].forEach(function (d) { domain(d, "REJECT-DROP"); });
  rules.push("RULE-SET,QXH-Ads," + ADS);
  // Inner application QUIC only. Does NOT block Hysteria2/TUIC's outer UDP tunnel.
  ["googlevideo.com", "youtube.com", "youtubei.googleapis.com", "ytimg.com", "ggpht.com"].forEach(function (d) {
    rules.push("AND,((DOMAIN-SUFFIX," + d + "),(NETWORK,UDP),(DST-PORT,443)),REJECT");
  });
  rules.push("AND,((DOMAIN,youtubei-att.googleapis.com),(NETWORK,UDP),(DST-PORT,443)),REJECT");
  ["OpenAI", "Gemini", "Claude"].forEach(function (n) { rules.push("RULE-SET,QXH-" + n + "," + AI); });
  // Route Claude Web, Grok/Muse(Meta AI)/Hark/Wabi/Cue/Today and AI agents to QXH-AI before CN ruleset.
  ["claude.com", "claudeusercontent.com", "x.ai", "grok.com", "muse.ai", "meta.ai", "metaaivm.com",
    "hark.com", "gethark.ai", "wabi.ai", "cueai.app", "manus.im", "manus.ai",
    "today.ai", "oneintent.today", "perplexity.ai", "poe.com", "claude.ai"].forEach(function (d) { domain(d, AI); });
  // Keep shared Google auth / FCM isolated from both AI and YouTube pools.
  ["accounts.google.com", "oauth2.googleapis.com", "securetoken.googleapis.com", "identitytoolkit.googleapis.com", "mtalk.google.com"]
    .forEach(function (d) { rules.push("DOMAIN," + d + "," + GOOGLE); });
  rules.push("RULE-SET,QXH-YouTube," + YT);
  ["youtubei.googleapis.com", "youtubei-att.googleapis.com", "yt3.googleusercontent.com", "init-stream.maasea.workers.dev"]
    .forEach(function (d) { rules.push("DOMAIN," + d + "," + YT); });
  ["googlevideo.com", "ytimg.com", "youtube.com", "youtu.be", "ggpht.com"].forEach(function (d) { domain(d, YT); });
  rules.push("RULE-SET,QXH-Google," + GOOGLE);
  rules.push("RULE-SET,QXH-Telegram," + TG);
  rules.push("RULE-SET,QXH-TelegramIP," + TG + ",no-resolve");
  // Ensure Meta general accounts, Discord, Notion, and X/Twitter (Grok bot) hit proxy before QXH-CN/MATCH.
  ["meta.com", "discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media", "discordcdn.com", "dis.gd",
    "notion.so", "notion.site", "notion.com", "notion-static.com", "makenotion.com",
    "x.com", "twitter.com", "twimg.com", "t.co", "pscp.tv"].forEach(function (d) { domain(d, G); });
  rules.push("RULE-SET,QXH-CN,DIRECT");
  rules.push("RULE-SET,QXH-CNIP,DIRECT,no-resolve");
  rules.push("MATCH," + G);
  out.mode = "rule";
  out["allow-lan"] = false;
  out.profile = Object.assign({}, out.profile || {}, {"store-selected":true});
  out["proxy-groups"] = groups;
  var displayOrder = [G, YT, AI, GOOGLE, TG, ADS, MAN];
  out["proxy-groups"].sort(function (a, b) {
    var ai = displayOrder.indexOf(a.name), bi = displayOrder.indexOf(b.name);
    return (ai < 0 ? 99 : ai) - (bi < 0 ? 99 : bi);
  });
  out["rule-providers"] = providers;
  out.rules = rules;
  return out;
}
