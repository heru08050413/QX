"""Stash Pro static/fixture audit for unified single-file Stash_Pro_V26.00.stoverride.

Requires PyYAML (plus Node for embedded/YouTube JS runtime checks).
--online checks all 18 MRS binary providers and both pinned YouTube scripts.
No configuration or subscription is modified. TLS verification stays enabled.
"""
import argparse
import copy
import hashlib
import ipaddress
import json
import re
import subprocess
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--dependency-dir')
parser.add_argument('--online', action='store_true')
args, rest = parser.parse_known_args()
if args.dependency_dir:
    sys.path.insert(0, args.dependency_dir)
import yaml

BASE = Path(__file__).resolve().parents[1]
CFG_NAME = 'Stash_Pro_V26.00.stoverride'

FORBIDDEN_MITM_KEYWORDS = (
    'bank', 'pay', '955', 'icbc', 'ccb', 'abc', 'boc', 'cmb', 'psbc', 'spdb',
    'ceb', 'citic', 'pingan', 'hxb', 'cib', 'lakala', 'helipay', 'ysepay',
    'unionpay', 'tenpay', 'alipay', 'jdpay', 'jr.', 'fin', 'credit', 'loan',
    'wallet', 'cash', 'stock', 'fund', 'sec', 'broker', 'xueqiu', 'futu',
    'eastmoney', 'insur', 'picc', 'cpic', 'taikang', 'gov', '12306', 'tax',
    'police', 'court', 'ybj', 'hospital', 'weixin110', 'security', 'passport',
    'login', 'auth', 'account', 'oauth', 'sso', 'icloud', 'apple.com',
    'ts.net', 'tailscale', '10086', '10010', '189.cn', 'wostore', 'alipan',
    'aliyundrive', 'pan.baidu', '115.com',
)


class Strict(yaml.SafeLoader):
    pass


def mapping(loader, node, deep=False):
    out = {}
    for k, v in node.value:
        key = loader.construct_object(k, deep=deep)
        if key in out:
            raise ValueError('duplicate YAML key: ' + str(key))
        out[key] = loader.construct_object(v, deep=deep)
    return out


Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)


def load(text):
    return yaml.load(text, Loader=Strict)


def read(name):
    return load((BASE / name).read_text(encoding='utf-8'))


STASH_PRO = read(CFG_NAME)


def merge(a, b):
    """Default Stash merge; #!replace keys are applied separately in override fixture."""
    if isinstance(a, dict) and isinstance(b, dict):
        result = copy.deepcopy(a)
        for key, val in b.items():
            result[key] = merge(result[key], val) if key in result else copy.deepcopy(val)
        return result
    if isinstance(a, list) and isinstance(b, list):
        return copy.deepcopy(b + a)
    return copy.deepcopy(b)


def validate(c, is_merged=False):
    assert c['mode'] == 'rule'
    assert c['tcp-concurrent'] is True
    if not is_merged:
        assert 'dns' not in c and 'proxy-providers' not in c

    groups = {g['name']: g for g in c['proxy-groups']}
    assert len(groups) == len(c['proxy-groups']) == 20
    builtins = {'DIRECT', 'REJECT', 'REJECT-DROP'}

    def walk(name, stack):
        assert name not in stack, 'policy cycle'
        for dest in groups[name].get('proxies', []):
            assert dest in groups or dest in builtins, f'unknown policy {dest}'
            if dest in groups:
                walk(dest, stack | {name})

    regions = {'美国节点', '日本节点', '新加坡节点', '台湾节点', '香港节点'}
    pools = regions | {'稳定切换', '手动节点', '其他节点'}
    for name, g in groups.items():
        walk(name, set())
        if name in regions:
            assert 'filter' in g and 'exclude-filter' in g, f'{name} must filter region and exclude junk'
            assert '(?!' not in g['filter'] and '(?!' not in g['exclude-filter']
        elif name in {'稳定切换', '手动节点', '其他节点'}:
            assert 'filter' not in g and 'exclude-filter' in g, f'{name} must only carry exclude-filter'
            assert '(?!' not in g['exclude-filter']
        else:
            assert 'filter' not in g and 'exclude-filter' not in g
        if g['type'] == 'url-test':
            assert g.get('url') == 'https://www.gstatic.com/generate_204', f'bad probe url on {name}'
            assert g.get('interval') == 900
            assert g.get('tolerance') == 200
            assert g.get('lazy') is True
        else:
            assert 'url' not in g and 'benchmark-url' not in g
        assert 'benchmark-url' not in g
        assert g.get('proxies') or g.get('include-all')
        assert not g.get('use'), 'groups must use include-all for universal airport compatibility'
        icon = g.get('icon', '')
        assert icon.startswith('https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/') and icon.endswith('.png'), name

    for name in pools:
        assert groups[name].get('include-all') is True, name
        excl_rx = re.compile(groups[name]['exclude-filter'])
        for junk in ('剩余流量 100GB', '到期时间 2027-01-01', '官网地址 example.com', '套餐重置'):
            assert excl_rx.search(junk), f'{name} failed to exclude {junk}'
        assert not excl_rx.search('KR-Home'), f'{name} wrongly excluded KR-Home'
        if name != '其他节点':
            assert not excl_rx.search('US-1') and not excl_rx.search('SG-1')
    assert groups['手动节点']['type'] == 'select'

    for name in ('默认代理', 'YouTube', 'AI', 'Google', '社交媒体', '国际媒体'):
        assert groups[name]['proxies'][0] == '美国节点', name
    assert '香港节点' not in groups['AI']['proxies'] and 'DIRECT' not in groups['AI']['proxies']
    assert 'include-all' not in groups['AI'] and 'use' not in groups['AI']
    assert groups['Spotify']['proxies'][0] == '新加坡节点'
    assert groups['Telegram']['proxies'][0] == '新加坡节点'
    assert groups['Apple']['proxies'][0] == 'DIRECT'
    assert groups['Microsoft']['proxies'][0] == 'DIRECT'
    assert groups['广告过滤']['proxies'] == ['REJECT', 'DIRECT']
    assert groups['兜底流量']['proxies'] == ['默认代理', 'DIRECT']

    rps = c['rule-providers']
    assert len(rps) == 18
    paths = set()
    for name, rp in rps.items():
        assert rp['format'] == 'mrs', name
        assert rp['behavior'] in {'domain', 'ipcidr'}, name
        assert rp['url'].startswith('https://raw.githubusercontent.com/'), name
        assert rp['path'].endswith('.mrs') and rp['path'] not in paths, name
        paths.add(rp['path'])
        assert rp['interval'] == 86400, name

    rules = c['rules']
    assert rules[-1] == 'MATCH,兜底流量'
    refs = set()
    for rule in rules:
        parts = rule.split(',')
        target = parts[-2] if parts[-1] == 'no-resolve' else parts[-1]
        assert target in groups or target in builtins, f'unknown rule policy: {rule}'
        if parts[0] == 'RULE-SET':
            assert parts[1] in rps, f'unknown provider {parts[1]}'
            refs.add(parts[1])
            if rps[parts[1]]['behavior'] == 'ipcidr':
                assert parts[-1] == 'no-resolve', rule
        if parts[0] in {'GEOIP', 'IP-CIDR', 'IP-CIDR6'}:
            assert parts[-1] == 'no-resolve', rule
    assert refs == set(rps)

    # Critical ordering & safety invariants
    assert sum(1 for r in rules if r.endswith(',REJECT-DROP')) == 12
    for host in ('googlevideo.com', 'youtube.com', 'youtubei.googleapis.com',
                 'youtubei-att.googleapis.com', 'ytimg.com', 'ggpht.com',
                 'api.zhihu.com', 'api.weibo.cn', 'sdkapp.uve.weibo.com',
                 'edith.xiaohongshu.com', 'api.m.jd.com', 'guide-acs.m.taobao.com'):
        assert any(r.startswith('AND,') and host in r and '(NETWORK,udp),(DST-PORT,443)' in r for r in rules), host

    for req_idx_host in ('DOMAIN,api.weibo.cn,DIRECT', 'DOMAIN,sdkapp.uve.weibo.com,DIRECT',
                         'DOMAIN,api.zhihu.com,DIRECT', 'DOMAIN,edith.xiaohongshu.com,DIRECT',
                         'DOMAIN,dns.weixin.qq.com,DIRECT', 'DOMAIN-SUFFIX,cmpassport.com,DIRECT',
                         'DOMAIN-SUFFIX,browser-intake-datadoghq.com,AI'):
        assert rules.index(req_idx_host) < rules.index('RULE-SET,Ads,广告过滤'), req_idx_host
    assert rules.index('AND,((DOMAIN,api.zhihu.com),(NETWORK,udp),(DST-PORT,443)),REJECT') < rules.index('DOMAIN,api.zhihu.com,DIRECT')
    assert rules.index('AND,((DOMAIN,sdkapp.uve.weibo.com),(NETWORK,udp),(DST-PORT,443)),REJECT') < rules.index('DOMAIN,sdkapp.uve.weibo.com,DIRECT')
    assert rules.index('DOMAIN,gemini.google.com,AI') < rules.index('RULE-SET,Google,Google')
    assert rules.index('DOMAIN,copilot.microsoft.com,AI') < rules.index('RULE-SET,Microsoft,Microsoft')
    assert rules.index('DOMAIN-SUFFIX,bing.com,默认代理') < rules.index('RULE-SET,Microsoft,Microsoft')
    assert rules.index('DOMAIN-SUFFIX,github.com,默认代理') < rules.index('RULE-SET,Microsoft,Microsoft')
    assert rules.index('DOMAIN,init-stream.maasea.workers.dev,YouTube') < rules.index('RULE-SET,ChinaDomains,DIRECT')

    for ts_rule in ('DOMAIN-SUFFIX,ts.net,DIRECT', 'DOMAIN-SUFFIX,tailscale.com,DIRECT',
                    'DOMAIN-SUFFIX,tailscale.io,DIRECT', 'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve',
                    'IP-CIDR6,fd7a:115c:a1e0::/48,DIRECT,no-resolve'):
        assert ts_rule in rules, ts_rule

    for synced in ('DOMAIN-SUFFIX,claude.com,AI', 'DOMAIN-SUFFIX,claudeusercontent.com,AI',
                   'DOMAIN-SUFFIX,wabi.ai,AI', 'DOMAIN-SUFFIX,hark.com,AI', 'DOMAIN-SUFFIX,cueai.app,AI',
                   'DOMAIN-SUFFIX,muse.ai,AI', 'DOMAIN-SUFFIX,today.ai,AI', 'DOMAIN-SUFFIX,grok.com,AI',
                   'DOMAIN-SUFFIX,discord.com,社交媒体', 'DOMAIN-SUFFIX,meta.com,社交媒体',
                   'DOMAIN-SUFFIX,notion.com,默认代理', 'DOMAIN-SUFFIX,wasabisys.com,默认代理'):
        assert synced in rules, synced

    # MITM safety & rewrite/script checks
    http = c['http']
    assert 'ca' not in http and 'ca-passphrase' not in http
    mitm_hosts = http['mitm']
    assert len(mitm_hosts) >= 35
    for host in mitm_hosts:
        h = str(host).lower()
        assert '*' not in h or h == '*.googlevideo.com', f'unexpected wildcard MITM {host}'
        for kw in FORBIDDEN_MITM_KEYWORDS:
            assert kw not in h, f'sensitive keyword {kw!r} in MITM host {host}'

    assert len(http['url-rewrite']) == 67
    for rw in http['url-rewrite']:
        pat, _, _ = rw.rsplit(' ', 2)
        re.compile(pat)

    for hook in http['script']:
        assert hook['name'] in c['script-providers']
        assert hook['require-body'] is True
        assert 0 < hook['max-size'] <= 5242880
        assert 0 < hook['timeout'] <= 10
        re.compile(hook['match'])
        if hook['name'].startswith('yt-'):
            assert hook['binary-mode'] is True

    sps = c['script-providers']
    assert 'payload' in sps['stash-pro-ads'] and 'url' not in sps['stash-pro-ads']
    for yt_key in ('yt-response', 'yt-request'):
        assert '/65075cdb388fc5e3094afd7e7314c67b243f3525/' in sps[yt_key]['url']

    encoded = json.dumps(c)
    assert 'skip-cert-verify' not in encoded
    assert 'external-controller' not in c


def route(host, network='tcp', port=443, sets=None, config=STASH_PRO):
    sets = sets or {}
    def suffix(pattern):
        return host == pattern or host.endswith('.' + pattern)
    for line in config['rules']:
        p = line.split(',')
        kind = p[0]
        target = p[-2] if p[-1] == 'no-resolve' else p[-1]
        if kind == 'MATCH':
            return target
        if kind == 'DOMAIN' and host == p[1] or kind == 'DOMAIN-SUFFIX' and suffix(p[1]) or kind == 'DOMAIN-KEYWORD' and p[1] in host:
            return target
        if kind == 'AND':
            terms = re.findall(r'\((DOMAIN-SUFFIX|DOMAIN|NETWORK|DST-PORT),([^()]+)\)', line)
            if terms and all({'DOMAIN': host == val, 'DOMAIN-SUFFIX': suffix(val),
                              'NETWORK': network == val, 'DST-PORT': str(port) == val}[key]
                             for key, val in terms):
                return target
        if kind == 'RULE-SET' and host in sets.get(p[1], set()):
            return target
        if kind in {'IP-CIDR', 'IP-CIDR6'}:
            try:
                if ipaddress.ip_address(host) in ipaddress.ip_network(p[1]):
                    return target
            except ValueError:
                pass
    raise AssertionError('no final route')


def node_fixtures(remote=None):
    payload = {'cfg': STASH_PRO, 'remote': remote or {}}
    result = subprocess.run(['node', str(BASE / 'scripts/test-stash-pro-runtime.cjs')],
                            input=json.dumps(payload), text=True, encoding='utf-8',
                            capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip(), flush=True)


class Audit(unittest.TestCase):
    def test_single_override_invariants(self):
        text = (BASE / CFG_NAME).read_text(encoding='utf-8')
        for key in ('proxy-groups', 'rule-providers', 'rules'):
            self.assertIn(f'{key}: #!replace', text)
        validate(STASH_PRO)

    def test_airport_switch_preserves_rules_and_groups(self):
        for i in range(1, 4):
            airport = {
                'proxies': [{'name': f'US-{i}', 'type': 'ss'}, {'name': f'HK-{i}', 'type': 'ss'}],
                'proxy-groups': [{'name': f'机场{i}', 'type': 'select', 'proxies': [f'US-{i}']}],
                'rules': [f'MATCH,机场{i}'],
                'dns': {'nameserver': ['9.9.9.9']},
                'rule-providers': {'机场旧集': {'url': f'https://airport-{i}.invalid/old'}},
            }
            result = merge(airport, STASH_PRO)
            for key in ('proxy-groups', 'rule-providers', 'rules'):
                result[key] = copy.deepcopy(STASH_PRO[key])
            validate(result, is_merged=True)
            self.assertEqual(result['rules'], STASH_PRO['rules'])
            self.assertEqual(result['proxy-groups'], STASH_PRO['proxy-groups'])
            self.assertEqual(result['proxies'], airport['proxies'])
            self.assertEqual(result['dns'], airport['dns'])

    def test_six_region_filters_and_boundaries(self):
        groups = {g['name']: g for g in STASH_PRO['proxy-groups']}
        filters = {name: re.compile(groups[name]['filter'])
                   for name in ('美国节点', '日本节点', '新加坡节点', '台湾节点', '香港节点')}
        other_excl = re.compile(groups['其他节点']['exclude-filter'])

        positives = {
            '美国节点': ('US1-HY2', 'US-3', '美国-01', '🇺🇸 LA', 'United States 2', 'Silicon Valley'),
            '日本节点': ('JP-1', 'Japan-Tokyo', '日本-大阪', '🇯🇵 01'),
            '新加坡节点': ('SG1-HY2', 'Singapore-2', '新加坡-01', '🇸🇬 03'),
            '台湾节点': ('TW-01', 'Taiwan-Taipei', '台湾-02', '🇹🇼 台北'),
            '香港节点': ('HK-01', 'Hong Kong-2', '香港-IEPL', '🇭🇰 05'),
        }
        for target, names in positives.items():
            for n in names:
                matched = [g for g, rx in filters.items() if rx.search(n)]
                self.assertEqual(matched, [target], f'{n} matched {matched}')
                self.assertIsNotNone(other_excl.search(n), f'其他节点 failed to exclude {n}')

        for other in ('KR-Home', 'DE-Frankfurt', 'UK-London', 'Network-Test', 'Twitter解锁', 'AUS-Sydney', 'RUS-Moscow'):
            matched = [g for g, rx in filters.items() if rx.search(other)]
            self.assertEqual(matched, [], f'{other} leaked into {matched}')
            self.assertIsNone(other_excl.search(other), f'其他节点 wrongly excluded {other}')

        for junk in ('剩余流量 100GB', '到期时间 2027-01-01', '官网 example.com', '套餐说明'):
            self.assertIsNotNone(other_excl.search(junk), junk)

    def test_duplicate_keys_rejected(self):
        with self.assertRaises(ValueError):
            load('mode: rule\nmode: global\n')

    def test_routing_fixtures(self):
        tests = {
            'dns.weixin.qq.com.cn': 'DIRECT', 'dns.weixin.qq.com': 'DIRECT',
            'api.weibo.cn': 'DIRECT', 'sdkapp.uve.weibo.com': 'DIRECT',
            'api.zhihu.com': 'DIRECT', 'edith.xiaohongshu.com': 'DIRECT',
            'cmpassport.com': 'DIRECT', 'home.ts.net': 'DIRECT', '100.64.1.2': 'DIRECT',
            'umc.danuoyi.alicdn.com': 'REJECT-DROP', 'Aisou.ialicdn.com': 'REJECT-DROP',
            'xz.fbcdn.net': 'REJECT-DROP',
            'appcloud.zhihu.com': '广告过滤', 'ads-img-qc.xhscdn.com': '广告过滤',
            'gemini.google.com': 'AI', 'generativelanguage.googleapis.com': 'AI',
            'chatgpt.com': 'AI', 'copilot.microsoft.com': 'AI', 'claude.com': 'AI',
            'sydney.bing.com': 'AI', 'wabi.ai': 'AI', 'hark.com': 'AI',
            'cueai.app': 'AI', 'muse.ai': 'AI', 'today.ai': 'AI', 'grok.com': 'AI',
            'browser-intake-datadoghq.com': 'AI',
            'accounts.google.com': 'Google', 'mtalk.google.com': 'Google',
            'rr1.googlevideo.com': 'YouTube', 'youtubei.googleapis.com': 'YouTube',
            'init-stream.maasea.workers.dev': 'YouTube',
            'discord.com': '社交媒体', 'meta.com': '社交媒体',
            'github.com': '默认代理', 'notion.com': '默认代理', 'www.bing.com': '默认代理',
            'omny.fm': '默认代理', 'unknown.example': '兜底流量',
            'open.spotify.com': 'Spotify',
        }
        for host, expected in tests.items():
            with self.subTest(host=host):
                self.assertEqual(route(host), expected)

        sets = {'Ads': {'api.zhihu.com', 'sdkapp.uve.weibo.com', 'dns.weixin.qq.com', 'ads.example'}}
        for host in ('api.zhihu.com', 'sdkapp.uve.weibo.com', 'dns.weixin.qq.com'):
            self.assertEqual(route(host, sets=sets), 'DIRECT')
        self.assertEqual(route('ads.example', sets=sets), '广告过滤')

        self.assertEqual(route('api.zhihu.com', 'udp', 443), 'REJECT')
        self.assertEqual(route('api.zhihu.com', 'tcp', 443), 'DIRECT')
        self.assertEqual(route('sdkapp.uve.weibo.com', 'udp', 443), 'REJECT')
        self.assertEqual(route('sdkapp.uve.weibo.com', 'tcp', 443), 'DIRECT')
        self.assertEqual(route('api.m.jd.com', 'udp', 443), 'REJECT')
        self.assertEqual(route('rr1.googlevideo.com', 'udp', 443), 'REJECT')
        self.assertEqual(route('rr1.googlevideo.com', 'udp', 53), 'YouTube')

    def test_negative_mutations(self):
        def alter(path, val):
            c = copy.deepcopy(STASH_PRO)
            o = c
            for k in path[:-1]:
                o = o[k]
            o[path[-1]] = val
            return c

        pool_idx = next(i for i, g in enumerate(STASH_PRO['proxy-groups']) if g['name'] == '稳定切换')
        ai_idx = next(i for i, g in enumerate(STASH_PRO['proxy-groups']) if g['name'] == 'AI')
        mutations = [
            alter(['tcp-concurrent'], False),
            alter(['proxy-groups', 0, 'proxies'], ['missing']),
            alter(['proxy-groups', 0, 'proxies'], ['默认代理']),
            alter(['proxy-groups', ai_idx, 'proxies'], ['美国节点', '香港节点']),
            alter(['proxy-groups', pool_idx, 'use'], ['missing']),
            alter(['proxy-groups', pool_idx, 'filter'], 'US'),
            alter(['proxy-groups', pool_idx, 'interval'], 300),
            alter(['proxy-groups', pool_idx, 'lazy'], False),
            alter(['proxy-groups', pool_idx, 'type'], 'fallback'),
            alter(['proxy-groups', pool_idx, 'url'], 'http://cp.cloudflare.com/generate_204'),
            alter(['rule-providers', 'Ads', 'format'], 'yaml'),
            alter(['rules', -1], 'MATCH,DIRECT'),
            alter(['http', 'mitm'], ['*.icbc.com.cn']),
            alter(['http', 'script', -1, 'binary-mode'], False),
            alter(['http', 'script', 0, 'max-size'], -1),
        ]
        for i, c in enumerate(mutations):
            with self.subTest(mutation=i), self.assertRaises(AssertionError):
                validate(c)

    def test_embedded_script(self):
        node_fixtures()

    @unittest.skipUnless(args.online, 'use --online for public MRS & script GETs')
    def test_remote_resources(self):
        tasks = [('mrs', name, p) for name, p in STASH_PRO['rule-providers'].items()]
        tasks += [('script', name, p) for name, p in STASH_PRO['script-providers'].items() if 'url' in p]

        def fetch(task):
            kind, name, p = task
            request = Request(p['url'], headers={'User-Agent': 'Stash-Pro-Audit/2.0'})
            with urlopen(request, timeout=45) as response:
                self.assertEqual(response.status, 200)
                data = response.read(16000000)
            self.assertGreater(len(data), 100, name)
            if kind == 'mrs':
                self.assertEqual(data[:4], b'\x28\xb5\x2f\xfd', f'{name} is not Zstd MRS binary')
                print(f'PASS mrs {name}: {len(data)} bytes; sha256={hashlib.sha256(data).hexdigest()}', flush=True)
                return kind, name, data
            text = data.decode('utf-8-sig')
            self.assertNotIn('<!DOCTYPE html', text)
            syntax = subprocess.run(['node', '--check'], input=text, text=True, encoding='utf-8', capture_output=True)
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
            print(f'PASS script {name}: {len(data)} bytes; sha256={hashlib.sha256(data).hexdigest()}', flush=True)
            return kind, name, text

        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(fetch, tasks))
        node_fixtures({name: text for kind, name, text in results if kind == 'script'})


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]] + rest, verbosity=2)
