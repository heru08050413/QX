"""Static, regex, and routing-fixture audit for Clash_iso and MITM_Safe.

Requires PyYAML. Verifies offline invariants only (not live Hako/Mihomo import).
Does not modify any configuration or contain real credentials.
"""
import re
import unittest
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
CLASH_ISO_DIR = ROOT / "Clash_iso"
YAML_PATH = CLASH_ISO_DIR / "Clash_iso_V26.00.yaml"
MITM_PATH = CLASH_ISO_DIR / "MITM_Safe.sgmodule"
SR_PATH = ROOT / "proxy-configs" / "shadowrocket_V26.00.lsr"


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader, node, deep=False):
    out = {}
    for k, v in node.value:
        key = loader.construct_object(k, deep=deep)
        if key in out:
            raise ValueError(f"Duplicate YAML key: {key!r}")
        out[key] = loader.construct_object(v, deep=deep)
    return out


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping
)


CONFIG = yaml.load(YAML_PATH.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
BUILTINS = {"DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"}


def evaluate_rule(rules, domain, network="TCP", port=443, active_sets=()):
    def match_suffix(host, suffix):
        return host == suffix or host.endswith("." + suffix)

    for rule in rules:
        parts = rule.split(",")
        kind = parts[0]
        hit = False
        if kind == "DOMAIN":
            hit = domain == parts[1]
        elif kind == "DOMAIN-SUFFIX":
            hit = match_suffix(domain, parts[1])
        elif kind == "RULE-SET":
            hit = parts[1] in active_sets
        elif kind == "MATCH":
            hit = True
        elif kind == "AND":
            m = re.fullmatch(
                r"AND,\(\((DOMAIN(?:-SUFFIX)?),([^()]+)\),\(NETWORK,UDP\),\(DST-PORT,443\)\),([^,]+)",
                rule,
            )
            if not m:
                raise AssertionError(f"Unexpected AND syntax: {rule}")
            d_type, d_val, target = m.group(1), m.group(2), m.group(3)
            matched = (
                domain == d_val if d_type == "DOMAIN" else match_suffix(domain, d_val)
            )
            if matched and network == "UDP" and port == 443:
                return target
            continue
        elif kind in ("IP-CIDR", "IP-CIDR6"):
            continue
        else:
            raise AssertionError(f"Unsupported rule type in fixture evaluator: {rule}")

        if hit:
            return parts[-2] if parts[-1] == "no-resolve" else parts[-1]
    raise AssertionError("No MATCH rule hit")


class ClashIsoAuditTests(unittest.TestCase):
    def test_line_endings_consistent(self):
        targets = [
            YAML_PATH,
            MITM_PATH,
            CLASH_ISO_DIR / "README.md",
            ROOT / "proxy-configs" / "Clash_Hako_V26.00.js",
            ROOT / "proxy-configs" / "Clash_Hako_README.md",
            ROOT / "proxy-configs" / "scripts" / "test-clash-hako.cjs",
            Path(__file__),
        ]
        for path in targets:
            raw = path.read_bytes()
            lf = raw.count(b"\n")
            crlf = raw.count(b"\r\n")
            self.assertGreater(lf, 0, f"{path} unexpectedly empty")
            # Cross-platform (.gitattributes * text=auto): allow all-LF (Linux/macOS) or all-CRLF (Windows), reject mixed.
            self.assertIn(crlf, (0, lf), f"{path} mixes LF and CRLF line endings (lf={lf}, crlf={crlf})")

    def test_security_defaults(self):
        raw_text = YAML_PATH.read_text(encoding="utf-8")
        non_comment = "\n".join(
            line for line in raw_text.splitlines() if not line.lstrip().startswith("#")
        )
        self.assertNotIn("skip-cert-verify: true", non_comment.lower())
        self.assertFalse(CONFIG["allow-lan"])
        self.assertFalse(CONFIG["ipv6"])
        self.assertEqual(CONFIG["mode"], "rule")
        self.assertEqual(CONFIG["log-level"], "warning")

    def test_groups_dag_and_probe_homogeneity(self):
        groups = {g["name"]: g for g in CONFIG["proxy-groups"]}
        self.assertEqual(len(groups), len(CONFIG["proxy-groups"]))
        known = set(groups) | BUILTINS

        for name, g in groups.items():
            self.assertIn(g["type"], {"select", "url-test", "fallback"})
            if "proxies" in g:
                self.assertGreater(len(g["proxies"]), 0, name)
                for member in g["proxies"]:
                    self.assertIn(member, known, f"{name} -> unknown member {member}")
            else:
                self.assertTrue(g.get("include-all"), name)

            if g["type"] == "url-test":
                self.assertTrue(g.get("lazy"), f"{name} must be lazy")
                self.assertEqual(
                    g["url"],
                    "https://www.gstatic.com/generate_204",
                    f"{name} must use unified Google probe URL",
                )
                self.assertEqual(g["expected-status"], 204, name)
                self.assertEqual(g["interval"], 900, name)
                self.assertEqual(g["tolerance"], 200, name)
                self.assertEqual(g["timeout"], 5000, name)

        self.assertEqual(
            CONFIG["proxy-groups"][
                next(i for i, g in enumerate(CONFIG["proxy-groups"]) if g["name"] == "微软服务")
            ]["proxies"],
            ["DIRECT", "节点选择", "美国节点", "香港节点", "自动选择"],
        )

        # Cycle check
        def visit(node, stack):
            self.assertNotIn(node, stack, f"Cycle detected at {node}")
            if node in groups and "proxies" in groups[node]:
                for child in groups[node]["proxies"]:
                    visit(child, stack + [node])

        for name in groups:
            visit(name, [])

    def test_rule_providers_and_targets(self):
        groups = {g["name"] for g in CONFIG["proxy-groups"]}
        known = groups | BUILTINS
        providers = CONFIG["rule-providers"]
        seen_paths = set()
        for name, p in providers.items():
            self.assertEqual(p["type"], "http", name)
            self.assertEqual(p["format"], "mrs", name)
            self.assertEqual(p["interval"], 86400, name)
            self.assertEqual(p["proxy"], "节点选择", name)
            self.assertTrue(p["url"].startswith("https://raw.githubusercontent.com/"), name)
            self.assertNotIn(p["path"], seen_paths, name)
            seen_paths.add(p["path"])

        for rule in CONFIG["rules"]:
            parts = rule.split(",")
            target = parts[-2] if parts[-1] == "no-resolve" else parts[-1]
            self.assertIn(target, known, f"Unknown target in rule: {rule}")
            if parts[0] == "RULE-SET":
                self.assertIn(parts[1], providers, f"Undefined rule-provider: {rule}")
                if providers[parts[1]]["behavior"] == "ipcidr":
                    self.assertEqual(
                        parts[-1], "no-resolve", f"IP ruleset missing no-resolve: {rule}"
                    )
            if parts[0] in ("IP-CIDR", "IP-CIDR6"):
                self.assertEqual(
                    parts[-1], "no-resolve", f"IP rule missing no-resolve: {rule}"
                )

        self.assertEqual(CONFIG["rules"][-1], "MATCH,漏网之鱼")

    def test_six_pool_node_partition_and_junk_filter(self):
        groups = {g["name"]: g for g in CONFIG["proxy-groups"]}
        region_pools = ["美国节点", "香港节点", "台湾节点", "日本节点", "新加坡节点"]
        compiled = {}
        for name in region_pools + ["其他节点", "自动选择", "全部节点"]:
            g = groups[name]
            compiled[name] = (
                re.compile(g["filter"]) if "filter" in g else None,
                re.compile(g["exclude-filter"]) if "exclude-filter" in g else None,
            )

        def in_pool(pool_name, node_name):
            inc, exc = compiled[pool_name]
            if inc and not inc.search(node_name):
                return False
            if exc and exc.search(node_name):
                return False
            return True

        junk_nodes = [
            "剩余流量：88.5 GB",
            "套餐到期：2027-01-01",
            "过期时间 2026-12-31",
            "官网地址：example.invalid",
            "联系客服售后",
            "Expire: 2027-01-01",
            "Traffic Reset",
        ]
        for j in junk_nodes:
            for pool in region_pools + ["其他节点", "自动选择", "全部节点"]:
                self.assertFalse(in_pool(pool, j), f"Junk {j!r} leaked into {pool}")

        expected = {
            "美国节点": [
                "US01",
                "[US] 02",
                "USA-03",
                "🇺🇸 自建-洛杉矶",
                "沪美-IPLC-01",
                "美西-CN2",
                "美东-02",
                "美東-03",
                "美中-01",
                "圣何塞-GIA",
                "Silicon Valley-01",
                "United States 05",
            ],
            "香港节点": ["HK-01", "香港 01", "深港专线", "沪港-02", "京港-03", "🇭🇰 HKG-04", "Hong Kong"],
            "台湾节点": ["TW-01", "台湾-01", "台北-02", "台中-03", "新北-04", "彰化-05", "🇹🇼 TWN"],
            "日本节点": [
                "JP-01",
                "日本-东京",
                "大阪-02",
                "京日-01",
                "苏日-02",
                "沪日-03",
                "上日-04",
                "川日-05",
                "深日-06",
                "广日-07",
                "🇯🇵 Tokyo",
            ],
            "新加坡节点": [
                "SG-01",
                "新加坡-01",
                "狮城-02",
                "獅城-03",
                "沪新-01",
                "京新-02",
                "深新-03",
                "杭新-04",
                "广新-05",
                "🇸🇬 SGP",
            ],
            "其他节点": [
                "RUS-01",
                "Russia-MOW",
                "AUS-01",
                "Australia-SYD",
                "Austria-VIE",
                "BUSINESS-01",
                "Plus-01",
                "Status-01",
                "Campus-01",
                "Focus-01",
                "JustMySocks",
                "Home-KR",
                "德国-FRA",
                "自建-Hysteria2",
            ],
        }
        all_pools = region_pools + ["其他节点"]
        for target_pool, samples in expected.items():
            for sample in samples:
                hits = [p for p in all_pools if in_pool(p, sample)]
                self.assertEqual(
                    hits,
                    [target_pool],
                    f"Node {sample!r} matched {hits}, expected [{target_pool}]",
                )
                self.assertTrue(in_pool("自动选择", sample), sample)
                self.assertTrue(in_pool("全部节点", sample), sample)

    def test_tailscale_dns_and_routing(self):
        dns = CONFIG["dns"]
        fake_ip = set(dns["fake-ip-filter"])
        self.assertNotIn("*.lan", fake_ip)
        for required in [
            "+.lan",
            "+.local",
            "+.localhost",
            "+.home.arpa",
            "+.ts.net",
            "+.tailscale.com",
            "+.tailscale.io",
            "+.miwifi.com",
            "+.tplogin.cn",
            "router.asus.com",
            "router.synology.com",
            "+.synology.me",
            "+.quickconnect.to",
            "+.cmpassport.com",
            "id6.me",
            "open.e.189.cn",
            "mdn.open.wo.cn",
            "opencloud.wostore.cn",
            "auth.wosms.cn",
            "+.10099.com.cn",
        ]:
            self.assertIn(required, fake_ip, f"Missing fake-ip-filter: {required}")

        policy = dns.get("nameserver-policy", {})
        # +.ts.net intentionally omitted until iPhone Hako confirms built-in type: tailscale + ts://tailscale.
        self.assertNotIn("+.ts.net", policy)
        for lan_key in ["+.lan", "+.local", "+.home.arpa", "+.miwifi.com", "router.asus.com", "router.synology.com"]:
            self.assertEqual(policy.get(lan_key), "system", lan_key)

        rules = CONFIG["rules"]
        self.assertIn("IP-CIDR6,fd7a:115c:a1e0::/48,DIRECT,no-resolve", rules)
        for host in [
            "nas.tail123.ts.net",
            "login.tailscale.com",
            "derp.tailscale.io",
            "printer.home.arpa",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, active_sets=("广告", "海外")),
                "DIRECT",
                host,
            )

    def test_connectivity_telemetry_youtube_and_google_isolation(self):
        rules = CONFIG["rules"]
        # Connectivity protections beat 广告 ruleset
        for host in [
            "short.weixin.qq.com",
            "teg.tencent-cloud.net",
            "dns.weixin.qq.com",
            "mapi.weibo.cn",
            "sdkapp.uve.weibo.com",
            "amdc.alipay.com",
            "c-hzgt2.getui.com",
            "open.e.189.cn",
            "mdn.open.wo.cn",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, active_sets=("广告",)), "DIRECT", host
            )

        # Telemetry circuit breaker beats 广告 and uses REJECT-DROP
        for host in [
            "umc.danuoyi.alicdn.com",
            "Aisou.ialicdn.com",
            "a.xz.fbcdn.net",
            "b.xy.fbcdn.net",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, active_sets=("广告",)),
                "REJECT-DROP",
                host,
            )

        # YouTube QUIC UDP 443 REJECT + TCP routing + Maasea endpoint
        for host in [
            "rr1.googlevideo.com",
            "www.youtube.com",
            "youtubei.googleapis.com",
            "youtubei-att.googleapis.com",
            "i.ytimg.com",
            "yt3.ggpht.com",
        ]:
            self.assertEqual(evaluate_rule(rules, host, "UDP", 443), "REJECT", host)

        for host in [
            "rr1.googlevideo.com",
            "youtubei.googleapis.com",
            "youtubei-att.googleapis.com",
            "i.ytimg.com",
            "yt3.ggpht.com",
            "yt3.googleusercontent.com",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, "TCP", 443, active_sets=("Google",)),
                "YouTube",
                host,
            )

        self.assertEqual(
            evaluate_rule(
                rules, "www.youtube.com", "TCP", 443, active_sets=("YouTube", "Google")
            ),
            "YouTube",
        )
        self.assertEqual(
            evaluate_rule(rules, "init-stream.maasea.workers.dev", "TCP", 443),
            "YouTube",
        )

        # Google shared auth / FCM isolated from YouTube and AI
        for host in [
            "accounts.google.com",
            "oauth2.googleapis.com",
            "securetoken.googleapis.com",
            "identitytoolkit.googleapis.com",
            "mtalk.google.com",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, "TCP", 443, active_sets=("YouTube", "Google")),
                "谷歌服务",
                host,
            )

        # AI agents, Claude Web, Grok, Muse, Discord, Notion beat 国内 ruleset (today.ai is in cn.mrs!)
        # Note: deliberately evaluated after 广告 so telemetry subhosts (exp.notion.so / client-metrics.discordapp.net) stay blocked.
        for host in [
            "claude.com",
            "claudeusercontent.com",
            "api.x.ai",
            "grok.com",
            "muse.ai",
            "meta.ai",
            "hatch.metaaivm.com",
            "hark.com",
            "gethark.ai",
            "wabi.ai",
            "cueai.app",
            "manus.im",
            "manus.ai",
            "today.ai",
            "oneintent.today",
        ]:
            self.assertEqual(
                evaluate_rule(rules, host, "TCP", 443, active_sets=("国内",)),
                "AI",
                host,
            )

        for host in ["www.meta.com", "discord.com", "gateway.discord.gg", "cdn.discordapp.com", "media.discordapp.net"]:
            self.assertEqual(
                evaluate_rule(rules, host, "TCP", 443, active_sets=("国内",)),
                "社交媒体",
                host,
            )

        for host in ["www.notion.so", "docs.notion.site", "www.notion.com", "a.notion-static.com", "makenotion.com"]:
            self.assertEqual(
                evaluate_rule(rules, host, "TCP", 443, active_sets=("国内",)),
                "节点选择",
                host,
            )

        for telemetry in ["exp.notion.so", "client-metrics.discordapp.net"]:
            self.assertEqual(
                evaluate_rule(rules, telemetry, "TCP", 443, active_sets=("广告", "国内")),
                "广告拦截",
                telemetry,
            )

    def test_mitm_safe_parity_with_shadowrocket(self):
        mitm_text = MITM_PATH.read_text(encoding="utf-8")
        m_mitm = re.search(r"(?m)^hostname\s*=\s*%APPEND%\s*(.+)$", mitm_text)
        self.assertIsNotNone(m_mitm)
        mitm_items = {x.strip() for x in m_mitm.group(1).split(",") if x.strip()}

        sr_text = SR_PATH.read_text(encoding="utf-8")
        m_sr = re.search(r"(?m)^hostname\s*=\s*(.+)$", sr_text)
        self.assertIsNotNone(m_sr)
        sr_excludes = {
            x.strip()
            for x in m_sr.group(1).split(",")
            if x.strip().startswith("-")
        }

        missing = sr_excludes - mitm_items
        self.assertEqual(missing, set(), f"Missing SR exclusions in MITM_Safe: {missing}")
        self.assertGreaterEqual(len(mitm_items), 185)
        self.assertIn("-*.ts.net", mitm_items)
        self.assertIn("-119.29.29.*", mitm_items)
        self.assertIn("-*.gov.cn", mitm_items)


if __name__ == "__main__":
    unittest.main(verbosity=2)
