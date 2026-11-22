"""Verify MITM financial, payment, gov, and security exclusions across all configs.

Offline checks validate that Shadowrocket, Clash_iso/MITM_Safe.sgmodule, Loon,
Egern, and Quantumult X all share the canonical exclusion baseline (185+ hosts).
--online additionally fetches upstream fmz200 blockAds.module / blockAds.plugin and
fails if any financial, bank, payment, broker, insurance, security, gov, airline,
carrier, or cloud-drive host is left unexcluded.
"""
import argparse
import re
import sys
import unittest
from pathlib import Path
from urllib.request import Request, urlopen

import yaml

ROOT = Path(__file__).resolve().parents[2]
PROXY_DIR = ROOT / "proxy-configs"
CLASH_ISO_DIR = ROOT / "Clash_iso"

SENSITIVE_KEYWORDS = (
    "bank", "pay", "955", "cgb", "icbc", "ccb", "abc", "boc", "cmb", "psbc",
    "spdb", "ceb", "citic", "pingan", "hxb", "cib", "lakala", "helipay", "ysepay",
    "unionpay", "tenpay", "alipay", "jdpay", "jr.", "fin", "credit", "loan",
    "wallet", "cash", "stock", "fund", "sec", "broker", "xueqiu", "futu",
    "eastmoney", "insur", "life", "picc", "cpic", "taikang", "gov", "12306",
    "tax", "police", "court", "edu.cn", "health", "ybj", "hospital", "med",
    "weixin110", "security", "passport", "login", "auth", "account", "oauth",
    "sso", "shenzhentong", "yikatong", "transit", "bus", "metro", "air", "flight",
    "umetrip", "10086", "10010", "189.cn", "pan.", "alipan", "aliyundrive", "115",
    "quark", "icloud", "apple.com", "thsi.cn", "10jqka", "jrj.com", "u51.com",
    "wostore", "mcloud.139",
)

UPSTREAM_BLOCKADS = [
    ("module", "https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/blockAds.module"),
    ("plugin", "https://raw.githubusercontent.com/fmz200/wool_scripts/main/Loon/plugin/blockAds.plugin"),
]


def _extract_ini_hostname_excludes(path: Path, append_prefix: bool = False) -> set[str]:
    text = path.read_text(encoding="utf-8")
    in_mitm = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            in_mitm = s.lower() == "[mitm]"
            continue
        if in_mitm and re.match(r"^hostname\s*=", s, re.I):
            rhs = s.split("=", 1)[1].strip()
            if append_prefix:
                rhs = re.sub(r"^%APPEND%\s*", "", rhs)
            return {
                x.strip()[1:].lower()
                for x in rhs.split(",")
                if x.strip().startswith("-") and len(x.strip()) > 1
            }
    raise ValueError(f"No [MITM] hostname line found in {path}")


def _extract_egern_excludes(path: Path) -> set[str]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return {
        str(x).strip().lower()
        for x in data["mitm"]["hostnames"]["excludes"]
        if str(x).strip()
    }


def load_all_excludes() -> dict[str, set[str]]:
    return {
        "Shadowrocket": _extract_ini_hostname_excludes(PROXY_DIR / "shadowrocket_V26.00.lsr"),
        "Clash_MITM_Safe": _extract_ini_hostname_excludes(CLASH_ISO_DIR / "MITM_Safe.sgmodule", append_prefix=True),
        "Loon": _extract_ini_hostname_excludes(PROXY_DIR / "Loon_V26.00"),
        "QuantumultX": _extract_ini_hostname_excludes(PROXY_DIR / "quantumult_B_V26.00"),
        "Egern": _extract_egern_excludes(PROXY_DIR / "Egern_Pro_V26.00.yml"),
    }


def matches_any_exclusion(host: str, exclusions: set[str]) -> bool:
    h = host.lower()
    for pat in exclusions:
        rx = "^" + re.escape(pat).replace(r"\*", ".*") + "$"
        if re.match(rx, h):
            return True
    return False


class MitmExclusionTests(unittest.TestCase):
    def test_cross_app_parity_with_shadowrocket_baseline(self):
        all_ex = load_all_excludes()
        canonical = all_ex["Shadowrocket"]
        self.assertGreaterEqual(len(canonical), 185, "Expected >= 185 exclusions in Shadowrocket baseline")
        for spot in (
            "*.ts.net", "*.alipay.com", "alipay.com", "alipay.com.cn", "*.gov.cn",
            "12306.cn", "*.12306.cn", "*.95508.com", "*.lakala.com", "*.helipay.com",
            "*.ysepay.com", "*.xueqiu.com", "*.51credit.com", "*.u51.com", "*.jr.mi.com",
            "*.shenzhentong.com", "weixin110.qq.com", "security.wechat.com",
            "*.thsi.cn", "*.10jqka.com.cn", "*.jrj.com", "*.jrj.com.cn", "*.wostore.cn",
        ):
            self.assertIn(spot, canonical, f"Missing canonical exclusion {spot}")

        for name, ex in all_ex.items():
            if name == "Shadowrocket":
                continue
            missing = canonical - ex
            self.assertEqual(missing, set(), f"{name} missing Shadowrocket MITM exclusions: {sorted(missing)}")


def check_online() -> None:
    all_ex = load_all_excludes()
    canonical = all_ex["Shadowrocket"]
    positive_hosts: set[str] = set()
    for kind, url in UPSTREAM_BLOCKADS:
        req = Request(url, headers={"User-Agent": "QX-MITM-Audit/1.0"})
        with urlopen(req, timeout=25) as r:
            if r.status != 200:
                raise RuntimeError(f"HTTP {r.status} fetching {url}")
            text = r.read().decode("utf-8", errors="ignore")
        pat = r"(?m)^hostname\s*=\s*%APPEND%\s*(.+)$" if kind == "module" else r"(?m)^hostname\s*=\s*(.+)$"
        m = re.search(pat, text)
        if not m:
            raise RuntimeError(f"No hostname line in {url}")
        for h in m.group(1).split(","):
            hs = h.strip().lower()
            if hs and not hs.startswith("-"):
                positive_hosts.add(hs)

    # Known non-financial advertising/media hosts that contain substring overlaps (e.g. 'air' in caiyicloud/variflight? Keep variflight excluded; allow known ad CDNs like 'life' in benlailife)
    benign_allowlist = {
        "abcapi.lenovoimage.com",
        "ad.life.360.cn",
        "api.sodalife.xyz",
        "api.ulife.group",
        "apicloud.zol.com.cn",
        "apis.lifeweek.com.cn",
        "appapi.caiyicloud.com",
        "business-cdn.shouji.sogou.com",
        "business.msstatic.com",
        "common.diditaxi.com.cn",
        "conf.diditaxi.com.cn",
        "dict-mobile.iciba.com",
        "dictvip-business.youdao.com",
        "fc-video.cdn.bcebos.com",
        "fcvbjbcebos.baidu.com",
        "img0*.benlailife.com",
        "m.ibuscloud.com",
        "media.qyer.com",
        "mobads-pre-config.cdn.bcebos.com",
        "mobile-pic.cache.iciba.com",
        "ndstatic.cdn.bcebos.com",
        "res.mall.10010.cn",
        "service.busi.inke.cn",
        "service.iciba.com",
        "staticsns.cdn.bcebos.com",
        "zt-app.go189.cn",
    }
    flagged = [
        h for h in sorted(positive_hosts)
        if any(k in h for k in SENSITIVE_KEYWORDS)
        and not matches_any_exclusion(h, canonical)
        and h not in benign_allowlist
    ]
    if flagged:
        raise AssertionError(f"Unexcluded sensitive blockAds hosts: {flagged}")
    print(f"ONLINE PASS: audited {len(positive_hosts)} upstream blockAds hosts against {len(canonical)} canonical exclusions (0 unexcluded sensitive gaps).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--online", action="store_true")
    ns, rest = parser.parse_known_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(MitmExclusionTests)
    res = unittest.TextTestRunner(verbosity=2).run(suite)
    if not res.wasSuccessful():
        sys.exit(1)
    if ns.online:
        check_online()
