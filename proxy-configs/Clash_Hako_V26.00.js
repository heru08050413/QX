/*
 * QX / Clash by Hako — V26.00 revision 1, 2026-09-20.
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
  var G = "QXH-代理", MAN = "QXH-手动", AUTO = "QXH-自动";
  var YT = "QXH-YouTube", YTF = "QXH-YT故障转移", AI = "QXH-AI";
  var GOOGLE = "QXH-Google", TG = "QXH-Telegram", ADS = "QXH-广告";
  var cf = "https://cp.cloudflare.com/generate_204";
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
    ["JP", /日本|东京|東京|大阪|🇯🇵|(?:^|[^a-z])(?:jp|japan)(?=$|[^a-z])/i],
    ["SG", /新加坡|狮城|獅城|🇸🇬|(?:^|[^a-z])(?:sg|singapore)(?=$|[^a-z])/i],
    ["TW", /台湾|台灣|台北|🇹🇼|(?:^|[^a-z])(?:tw|taiwan)(?=$|[^a-z])/i],
    ["HK", /香港|🇭🇰|(?:^|[^a-z])(?:hk|hong[ _-]?kong)(?=$|[^a-z])/i],
    ["US", /美国|美國|洛杉矶|洛杉磯|🇺🇸|(?:^|[^a-z])(?:us|usa|united[ _-]?states)(?=$|[^a-z])/i]
  ];
  var buckets = Object.create(null), used = Object.create(null), regionGroups = [], ytGroups = [];
  regions.forEach(function (r) {
    // Ambiguous multi-country labels stay in OTHER; names are hints, not IP geolocation.
    var members = all.filter(function (name) {
      return r[1].test(name) && regions.filter(function (x) { return x[1].test(name); }).length === 1;
    });
    buckets[r[0]] = members;
    if (!members.length) return;
    members.forEach(function (n) { used[n] = true; });
    var generalName = "QXH-" + r[0], ytName = "QXH-YT-" + r[0];
    regionGroups.push(generalName); ytGroups.push(ytName);
    check(generalName, "url-test", members, cf, 300);
    check(ytName, "url-test", members, google, 120);
  });
  var others = all.filter(function (n) { return !used[n]; });
  if (others.length) {
    check("QXH-YT-OTHER", "url-test", others, google, 120);
    ytGroups.push("QXH-YT-OTHER");
  }
  check(AUTO, "url-test", all, cf, 300);
  check(YTF, "fallback", ytGroups, google, 60);
  // AI: stable priority rather than fastest-node rotation; no silent DIRECT fallback.
  var aiNodes = [].concat(buckets.US, buckets.JP, buckets.SG, buckets.TW);
  if (aiNodes.length) check("QXH-AI稳定", "fallback", aiNodes, cf, 180);
  var aiRegions = ["US", "JP", "SG", "TW"].filter(function (r) { return buckets[r].length; })
    .map(function (r) { return "QXH-" + r; });
  select(G, [AUTO, MAN].concat(regionGroups));
  select(YT, [YTF, MAN].concat(ytGroups));
  select(AI, [aiNodes.length ? "QXH-AI稳定" : "REJECT", MAN].concat(aiRegions));
  select(GOOGLE, [G, AI, MAN]);
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
  ["lan", "local", "localhost"].forEach(function (d) { domain(d, "DIRECT"); });
  ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4"].forEach(function (cidr) { rules.push("IP-CIDR," + cidr + ",DIRECT,no-resolve"); });
  ["::1/128", "fc00::/7", "fe80::/10", "ff00::/8"].forEach(function (cidr) { rules.push("IP-CIDR6," + cidr + ",DIRECT,no-resolve"); });
  // Connectivity protection is deliberately narrower than all of qq.com/tencent.com.
  ["weixin.qq.com", "weixin.com", "wechat.com", "qq.com.cn", "teg.tencent-cloud.net", "qpic.cn", "qlogo.cn",
    "api.weibo.cn", "weibo.com", "zhihu.com", "zhimg.com", "push.apple.com"].forEach(function (d) { domain(d, "DIRECT"); });
  domain("raw.githubusercontent.com", G);
  rules.push("RULE-SET,QXH-Ads," + ADS);
  // Inner application QUIC only. Does NOT block Hysteria2/TUIC's outer UDP tunnel.
  ["googlevideo.com", "youtube.com", "youtubei.googleapis.com"].forEach(function (d) {
    rules.push("AND,((DOMAIN-SUFFIX," + d + "),(NETWORK,UDP),(DST-PORT,443)),REJECT");
  });
  rules.push("RULE-SET,QXH-YouTube," + YT);
  rules.push("DOMAIN,youtubei.googleapis.com," + YT);
  ["googlevideo.com", "ytimg.com", "youtube.com", "youtu.be"].forEach(function (d) { domain(d, YT); });
  ["OpenAI", "Gemini", "Claude"].forEach(function (n) { rules.push("RULE-SET,QXH-" + n + "," + AI); });
  // Keep Gemini login on its chosen AI exit, not the video failover pool.
  rules.push("DOMAIN,accounts.google.com," + AI);
  rules.push("RULE-SET,QXH-Google," + GOOGLE);
  rules.push("RULE-SET,QXH-Telegram," + TG);
  rules.push("RULE-SET,QXH-TelegramIP," + TG + ",no-resolve");
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
