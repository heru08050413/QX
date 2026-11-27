"""Egern-only YAML/semantic regression tests; NOT an iOS runtime emulator.

Requires PyYAML 6.0.2. Supply --dependency-dir for an isolated installation.
No files, subscriptions, credentials, or client settings are changed.
"""
import argparse
import copy
import fnmatch
import ipaddress
import re
import subprocess
import sys
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

options = argparse.ArgumentParser(add_help=False)
options.add_argument('--dependency-dir')
options.add_argument('--online', action='store_true')
args, rest = options.parse_known_args()
if args.dependency_dir:
    sys.path.insert(0, args.dependency_dir)
import yaml

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'proxy-configs/Egern_Pro_V26.00.yml'
BASE = '6fcf24d4cf3d75ef6d69583972f9a1bd019cab2e'


class UniqueLoader(yaml.SafeLoader):
    """Reject duplicate keys instead of silently discarding earlier values."""


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f'duplicate YAML key: {key}')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def load(text):
    return yaml.load(text, Loader=UniqueLoader)


def body(rule):
    assert len(rule) == 1, f'Expected tagged rule/group: {list(rule)}'
    return next(iter(rule.values()))


def group(config, name):
    matches = [g for g in config['policy_groups'] if body(g)['name'] == name]
    assert len(matches) == 1, f'Missing/duplicate group: {name}'
    return matches[0]


def domain(host, policy, kind='domain'):
    return {kind: {'match': host, 'policy': policy}}


GEMINI = ['geller-pa.googleapis.com', 'robinfrontend-pa.googleapis.com',
          'gemini.gstatic.com', 'alkalicore-pa.clients6.google.com',
          'webchannel-alkalimakersuite-pa.clients6.google.com']
IMAGES = ['fastimage.uve.weibo.com', 'adimg.uve.weibo.com', 'adimg.vue.weibo.com']
WECHAT = ['dns.weixin.qq.com', 'dns.weixin.qq.com.cn',
          'apd-pcdnwxlogin.teg.tencent-cloud.net']
YT_URL = 'https://raw.githubusercontent.com/Maasea/sgmodule/65075cdb388fc5e3094afd7e7314c67b243f3525/YouTube.Enhance.sgmodule'
YT_ARGS = {'屏蔽上传按钮': 'true', '屏蔽选段按钮': 'true', '屏蔽Shorts按钮': 'false',
           '字幕翻译语言': 'off', '启用调试模式': 'false'}
NEW_WEIBO_HOSTS = ['api.weibo.cn', 'mapi.weibo.cn', 'api.weibo.com', 'mapi.weibo.com',
                   'sdkapp.uve.weibo.com', 'wbapp.uve.weibo.com']
OLD_WEIBO_HOSTS = ['*.weibo.cn', '*.weibo.com', '*.weibo.com.cn', '*.weibocdn.com',
                   '*.sina.cn', '*.sina.com.cn', '*.sinajs.cn']
PINNED_MODULES = {
    'https://raw.githubusercontent.com/sub-store-org/Sub-Store/b90aab7775f9c20a6ac61985a7c18d846d172745/config/Egern.yaml',
    'https://raw.githubusercontent.com/zmqcherish/proxy-script/1d9f51bc9a0077d81998bb503ee6158ca83faa73/weibo.sgmodule',
    YT_URL,
    'https://github.com/BiliUniverse/ADBlock/releases/download/v0.7.5/BiliBili.ADBlock.sgmodule',
    'https://github.com/NSRingo/Maps/releases/download/v4.6.1/iRingo.Maps.sgmodule',
    'https://raw.githubusercontent.com/fmz200/wool_scripts/f6bcc087e4da7ebef3c596be4a3c0fa406661564/Surge/module/blockAds.module',
}


def validate_overhaul_contracts(cfg):
    assert cfg['proxy_latency_test_url'] == 'https://www.gstatic.com/generate_204'
    foreign_doh = cfg['dns']['upstreams']['Foreign-DoH']
    assert all('f3af17' not in u and 'nextdns.io' not in u for u in foreign_doh)
    assert 'iosapps.itunes.apple.com' not in (cfg['dns'].get('hosts') or {})
    fwd = cfg['dns']['forward']
    assert fwd[-1] == {'domain_wildcard': {'match': '*', 'value': 'Domestic-DoH'}}
    fwd_str = str(fwd)
    for host in ('claude.com', 'claudeusercontent.com', 'wabi.ai', 'discord.com', 'notion.com',
                 'release/rule/Surge/Global/Global_All_No_Resolve.list'):
        assert host in fwd_str, f'Missing Foreign-DoH forward: {host}'
    assert any(body(r).get('match', '').endswith('/release/rule/Surge/ChinaMax/ChinaMax_All_No_Resolve.list')
               and body(r).get('value') == 'Domestic-DoH'
               for r in fwd if 'proxy_rule_set' in r)

    auto = body(group(cfg, 'AutoSelect'))
    assert auto['policies'] == ['香港', '台湾', '日本', '新加坡', '美国', '其他']
    assert 'flatten' not in auto and 'filter' not in auto
    assert auto['interval'] == 600 and auto['tolerance'] == 100 and auto['timeout'] == 5
    assert '其他' in body(group(cfg, 'Proxy'))['policies']
    for pool in ('香港', '台湾', '日本', '新加坡', '美国', '其他'):
        pg = body(group(cfg, pool))
        assert pg['interval'] == 600 and pg['tolerance'] == 100 and pg['timeout'] == 5, pool
    assert 'https://9.9.9.9/dns-query' in foreign_doh
    for sample in ('Network 01', 'Twitter 解锁', 'Ukraine 01', '🇬🇧 UK 01'):
        assert re.search(body(group(cfg, '其他'))['filter'], sample), f'Missing from 其他: {sample}'
        assert not re.search(body(group(cfg, '台湾'))['filter'], sample), f'False TW match: {sample}'
    assert not re.search(body(group(cfg, '日本'))['filter'], 'JPanime 01')
    assert re.search(body(group(cfg, '香港'))['filter'], 'HK01')

    rules = cfg['rules']
    for endpoint, kind in (('dns.google', 'domain'), ('cloudflare-dns.com', 'domain'), ('dns.quad9.net', 'domain'),
                           ('1.1.1.1/32', 'ip_cidr'), ('8.8.8.8/32', 'ip_cidr'), ('9.9.9.9/32', 'ip_cidr')):
        assert {kind: {'match': endpoint, 'policy': 'Proxy', **({'no_resolve': True} if kind == 'ip_cidr' else {})}} in rules, endpoint
    assert {'domain_suffix': {'match': 'ts.net', 'policy': 'DIRECT'}} in rules
    assert {'ip_cidr': {'match': '100.64.0.0/10', 'policy': 'DIRECT', 'no_resolve': True}} in rules
    assert domain('dig.bdurl.net', 'REJECT') in rules
    ad_idx = next(i for i, r in enumerate(rules) if body(r).get('name') == 'Advertising')
    for login_guard in (domain('id6.me', 'DIRECT', 'domain_suffix'), domain('cmpassport.com', 'DIRECT', 'domain_suffix')):
        assert login_guard in rules and rules.index(login_guard) < ad_idx, login_guard
    udp_idx = next(i for i, r in enumerate(rules) if body(r).get('name') == '国内 UDP 前置直连 (微信 VOIP 保护)')
    bhdns_idx = next(i for i, r in enumerate(rules) if body(r).get('name') == 'BlockHttpDNS')
    assert udp_idx > bhdns_idx
    assert rules[udp_idx]['and']['match'][1]['geoip']['no_resolve'] is True
    for bad in ('branch.io', 'segment.com', 'segment.io', 'googletagmanager.com'):
        assert not any(body(r).get('match') == bad for r in rules), f'Removed REJECT returned: {bad}'
    rsets = {body(r)['name']: body(r) for r in rules if 'rule_set' in r}
    for name, rs in rsets.items():
        assert '/master/' not in rs['match'], f'bm7 ruleset {name} still on master'
    assert rsets['Advertising']['match'].endswith('/Advertising_All_No_Resolve.list')
    assert rsets['Apple']['match'].endswith('/Apple_All_No_Resolve.list')
    assert rsets['ChinaMax']['match'].endswith('/ChinaMax_All_No_Resolve.list')
    assert 'Claude' in rsets and rsets['Claude']['policy'] == 'AI'
    assert 'Global' in rsets and rsets['Global']['match'].endswith('/Global_All_No_Resolve.list') and rsets['Global']['policy'] == 'Proxy'
    rule_names = [body(r).get('name') for r in rules]
    assert rule_names.index('Global') < rule_names.index('ChinaMax')
    for expected_rule in (
        domain('claude.com', 'AI', 'domain_suffix'),
        domain('claudeusercontent.com', 'AI', 'domain_suffix'),
        domain('sydney.bing.com', 'AI'),
        domain('edgeservices.bing.com', 'AI'),
        domain('wabi.ai', 'AI', 'domain_suffix'),
        domain('threads.com', 'Instagram', 'domain_suffix'),
        domain('meta.com', 'Proxy', 'domain_suffix'),
        domain('facebook.net', 'Proxy', 'domain_suffix'),
        domain('discordapp.net', 'Proxy', 'domain_suffix'),
        domain('notion.com', 'Proxy', 'domain_suffix'),
        domain('bing.com', 'Proxy', 'domain_suffix'),
    ):
        assert expected_rule in rules, f'Missing synced rule: {expected_rule}'

    hosts = cfg['mitm']['hostnames']
    assert '*.amap.com' not in hosts['includes']
    assert 'm5.amap.com' in hosts['includes'] and 'amap-aos-info-nogw.amap.com' in hosts['includes']
    excludes = set(hosts['excludes'])
    assert len(excludes) >= 185
    for spot in ('12306.cn', '*.12306.cn', '*.95508.com', 'weixin110.qq.com', 'security.wechat.com', 'sso.ifanr.com', '*.ts.net', '119.29.29.*'):
        assert spot in excludes, spot

    mods = cfg['modules']
    assert not any('egerndaddy' in m['url'] for m in mods)
    enabled_urls = {m['url'] for m in mods if m.get('enabled', True)}
    assert PINNED_MODULES <= enabled_urls, f'Unpinned core module(s): {sorted(PINNED_MODULES - enabled_urls)}'
    for m in mods:
        if any(tag in m['url'] for tag in ('chavyleung/scripts', 'ddgksf2013', 'kelee.one', 'Google_Rewrite', '%E5%B0%8F%E7%BA%A2%E4%B9%A6')):
            assert m.get('enabled', True) is False, f'Module should be disabled: {m["url"]}'


def matches(rule, host='', proto='https', country='', url='', ip=''):
    """Only semantics needed by fixtures. No remote-rule or native-engine emulation."""
    kind, data = next(iter(rule.items()))
    if data.get('disabled'):
        return False
    value = data.get('match')
    if kind == 'and':
        return all(matches(r, host, proto, country, url, ip) for r in value)
    if kind == 'or':
        return any(matches(r, host, proto, country, url, ip) for r in value)
    if kind == 'not':
        return not matches(value, host, proto, country, url, ip)
    if kind == 'domain':
        return host == value
    if kind == 'domain_suffix':
        return host == value or host.endswith('.' + value)
    if kind == 'domain_keyword':
        return value in host
    if kind == 'domain_wildcard':
        return fnmatch.fnmatchcase(host, value)
    if kind == 'domain_regex':
        return bool(re.search(value, host))
    if kind == 'protocol':
        return value in ({'udp', 'quic'} if proto == 'quic' else {'tcp', proto} if proto in ('http', 'https') else {proto})
    if kind == 'geoip':
        return country == value
    if kind in ('ip_cidr', 'ip_cidr6'):
        return bool(ip) and ipaddress.ip_address(ip) in ipaddress.ip_network(value)
    if kind == 'url_regex':
        return bool(url) and bool(re.search(value, url))
    if kind == 'rule_set':
        return False  # Fixture routes must resolve locally before remote lists.
    if kind == 'default':
        return True
    raise AssertionError(f'Fixture interpreter does not support {kind}')


def route(config, **request):
    for rule in config['rules']:
        if matches(rule, **request):
            return body(rule)['policy']
    raise AssertionError('No route')


class Audit(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = CONFIG.read_text(encoding='utf-8')
        cls.config = load(cls.text)
        cls.original = load(subprocess.check_output(['git', '-C', str(ROOT), 'show',
            BASE + ':proxy-configs/Egern_Pro_V26.00.yml'], encoding='utf-8'))

    def test_complete_change_scope(self):
        self.assertNotIn('f3af17', self.text)
        validate_overhaul_contracts(self.config)

    def test_duplicate_yaml_rejected(self):
        with self.assertRaises(ValueError):
            load('a: true\na: false\n')

    def test_groups_and_references(self):
        groups = [body(g) for g in self.config['policy_groups']]
        names = [g['name'] for g in groups]
        self.assertEqual(len(names), len(set(names)))
        valid = set(names) | {'DIRECT', 'REJECT', 'REJECT-DROP'}
        for g in groups:
            for p in g.get('policies', []):
                self.assertIn(p, valid)
        for r in self.config['rules']:
            self.assertIn(body(r)['policy'], valid)
        for gone in ('YT-Auto', 'StableSelect', '美国稳定', '日本稳定', '新加坡稳定', 'StableFallback'):
            self.assertNotIn(gone, names)
        self.assertEqual(body(group(self.config, 'YouTube'))['policies'][0], '美国')
        self.assertEqual(body(group(self.config, 'Gemini'))['policies'][0], '美国')

    def test_us_filters(self):
        yes = ['US', 'USA', 'us-01', 'US01', 'USA01', '机场-US-01', '美国01', '🇺🇸 01',
               'United States 01', 'America 01', '洛杉矶01', 'SiliconValley']
        no = ['Russia', 'RUS-01', 'Australia', 'AUS-01', 'RUS01', 'AUS01', 'Austria',
              '🇦🇺 Sydney', 'JP 日本', 'HK 香港', 'Business 01', 'Plus 01']
        for name in ('美国',):
            regex = re.compile(body(group(self.config, name))['filter'])
            for sample in yes + no:
                with self.subTest(pool=name, sample=sample):
                    self.assertEqual(bool(regex.search(sample)), sample in yes)

    def test_local_routing(self):
        for h in GEMINI:
            self.assertEqual(route(self.config, host=h), 'Gemini')
        for h in WECHAT:
            self.assertEqual(route(self.config, host=h), 'DIRECT')
        for h in IMAGES:
            self.assertEqual(route(self.config, host=h), 'REJECT')
        for h in ['api.weibo.cn', 'sdkapp.uve.weibo.com', 'bootpreload.uve.weibo.com',
                  'wx1.sinaimg.cn', 'video.weibocdn.com']:
            self.assertEqual(route(self.config, host=h), 'DIRECT')
        for h in ['youtubei.googleapis.com', 'init-stream.maasea.workers.dev', 'rr1.googlevideo.com']:
            self.assertEqual(route(self.config, host=h), 'YouTube')
        for h in ['mp.weixin.qq.com', 'api.zhihu.com', 'youtubei.googleapis.com', 'rr1.googlevideo.com',
                  'guide-acs.m.taobao.com', 'acs.m.goofish.com', 'api.yangkeduo.com', 'dict.youdao.com']:
            self.assertEqual(route(self.config, host=h, proto='quic', country='CN'), 'REJECT')
        self.assertEqual(route(self.config, proto='udp', country='CN'), 'DIRECT')
        self.assertEqual(route(self.config, host='gateway.12306.cn', proto='quic', country='CN'), 'DIRECT')

    def test_url_boundaries(self):
        root = 'https://youtubei.googleapis.com/youtubei/v1/'
        for path in ['player/ad_break', 'player/ad_break?x=1', 'player/ad_break/child']:
            self.assertEqual(route(self.config, host='youtubei.googleapis.com', url=root + path), 'REJECT')
        for path in ['player', 'player?x=1', 'player/ad_breakfast', 'log_event']:
            self.assertEqual(route(self.config, host='youtubei.googleapis.com', url=root + path), 'YouTube')
        self.assertEqual(route(self.config, host='rr1.googlevideo.com',
            url='https://rr1.googlevideo.com/videoplayback?id=regular'), 'YouTube')

    def test_guard_order(self):
        rules = self.config['rules']
        ad = next(i for i, r in enumerate(rules) if body(r).get('name') == 'Advertising')
        httpdns = next(i for i, r in enumerate(rules) if body(r).get('name') == 'BlockHttpDNS')
        for h in WECHAT:
            self.assertLess(rules.index(domain(h, 'DIRECT')), min(ad, httpdns))
        weibo = rules.index(domain('weibo.com', 'DIRECT', 'domain_suffix'))
        for h in IMAGES:
            self.assertLess(rules.index(domain(h, 'REJECT')), weibo)

    def test_security_and_module_owners(self):
        hosts = self.config['mitm']['hostnames']
        self.assertTrue({'12306.cn', '*.12306.cn'} <= set(hosts['excludes']))
        self.assertNotIn('gateway.12306.cn', hosts['includes'])
        self.assertFalse(set(OLD_WEIBO_HOSTS) & set(hosts['includes']))
        self.assertEqual(self.config['mitm']['ca_p12'], self.original['mitm']['ca_p12'])
        self.assertEqual(self.config['mitm']['ca_passphrase'], self.original['mitm']['ca_passphrase'])
        self.assertEqual(self.config['dns']['proxy_nameservers'], self.original['dns']['proxy_nameservers'])
        self.assertNotIn('public_ip_lookup_url', self.config['dns'])
        enabled = [m for m in self.config['modules'] if m.get('enabled', True)]
        youtube = [m for m in enabled if 'youtube' in m['url'].lower()]
        self.assertEqual(len(youtube), 1)
        self.assertEqual(youtube[0]['url'], YT_URL)
        self.assertEqual(youtube[0]['compat_arguments'], YT_ARGS)
        self.assertEqual(len([m for m in enabled if 'weibo.' in m['url']]), 1)
        self.assertEqual(len([m for m in enabled if 'ScriptHub' in m['url'] or 'Script%20Hub' in m['url']]), 0)

    def test_negative_mutations(self):
        cases = []
        c = copy.deepcopy(self.config); del c['mitm']['hostnames']['excludes'][0]; cases.append(c)
        c = copy.deepcopy(self.config); c['dns']['public_ip_lookup_url'] = 'https://ifconfig.me/ip'; cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, '美国'))['filter'] = '(?i)US'; cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, '台湾'))['filter'] = '(?i)TW'; cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'YouTube'))['policies'].pop(0); cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'Instagram'))['policies'][0] = '香港'; cases.append(c)
        c = copy.deepcopy(self.config); c['rules'].remove(domain('dns.weixin.qq.com', 'DIRECT')); cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'Gemini'))['policies'].insert(0, '订阅'); cases.append(c)
        c = copy.deepcopy(self.config); next(m for m in c['modules'] if m['url'] == YT_URL)['compat_arguments']['屏蔽上传按钮'] = 'false'; cases.append(c)
        c = copy.deepcopy(self.config); c['dns']['upstreams']['Foreign-DoH'].insert(0, 'https://dns.nextdns.io/f3af17'); cases.append(c)
        c = copy.deepcopy(self.config); c['dns']['forward'][-1]['domain_wildcard']['value'] = 'Foreign-DoH'; cases.append(c)
        c = copy.deepcopy(self.config); c['dns']['hosts'] = {'iosapps.itunes.apple.com': 'iosapps.itunes.apple.com.download.ks-cdn.com'}; cases.append(c)
        c = copy.deepcopy(self.config); c['mitm']['hostnames']['includes'].append('*.amap.com'); cases.append(c)
        c = copy.deepcopy(self.config); c['mitm']['hostnames']['excludes'].remove('*.95508.com'); cases.append(c)
        c = copy.deepcopy(self.config); next(m for m in c['modules'] if 'kelee.one' in m['url'])['enabled'] = True; cases.append(c)
        c = copy.deepcopy(self.config); c['rules'].insert(0, {'domain_suffix': {'match': 'branch.io', 'policy': 'REJECT'}}); cases.append(c)
        c = copy.deepcopy(self.config); b = next(r for r in c['rules'] if body(r).get('name') == 'Global'); c['rules'].remove(b); cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'AutoSelect'))['interval'] = 900; cases.append(c)
        c = copy.deepcopy(self.config); c['rules'].remove({'ip_cidr': {'match': '9.9.9.9/32', 'policy': 'Proxy', 'no_resolve': True}}); cases.append(c)
        for i, changed in enumerate(cases):
            with self.subTest(mutation=i):
                with self.assertRaises(AssertionError):
                    validate_overhaul_contracts(changed)
                    if 'public_ip_lookup_url' in changed.get('dns', {}):
                        raise AssertionError('public_ip_lookup_url returned')
                    if body(group(changed, '美国'))['filter'] != self.config['policy_groups'][7]['auto_test']['filter']:
                        raise AssertionError('US filter altered')
                    if body(group(changed, 'YouTube'))['policies'][0] != '美国':
                        raise AssertionError('YouTube default altered')
                    if body(group(changed, 'Instagram'))['policies'][0] != '美国':
                        raise AssertionError('Instagram default altered')
                    if domain('dns.weixin.qq.com', 'DIRECT') not in changed['rules']:
                        raise AssertionError('WeChat DNS removed')
                    if body(group(changed, 'Gemini'))['policies'][0] == '订阅':
                        raise AssertionError('Gemini default is 订阅')
                    if next(m for m in changed['modules'] if m['url'] == YT_URL)['compat_arguments']['屏蔽上传按钮'] != 'true':
                        raise AssertionError('YT upload button restored')

    @unittest.skipUnless(args.online, 'Use --online for public dependency/probe checks')
    def test_online_resources(self):
        urls = set()

        def collect(value):
            if isinstance(value, dict):
                if value.get('enabled') is False or value.get('disabled') is True:
                    return
                for key, child in value.items():
                    if key != 'icon':
                        collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)
            elif isinstance(value, str) and value.startswith('https://') and re.search(
                    r'\.(?:list|yaml|yml|sgmodule|module|lpx|js)$', value):
                urls.add(value)

        def fetch(url):
            request = Request(quote(url, safe=':/%?=&'), headers={'User-Agent': 'Egern/2.20.0'})
            with urlopen(request, timeout=30) as response:
                data = response.read()
                if response.status != 200 or not data:
                    raise AssertionError(f'Empty/non-200 resource: {url}')
                text = data.decode('utf-8-sig')
                if re.match(r'\s*(?:<!doctype html|<html)', text, re.I):
                    raise AssertionError(f'HTML instead of config/script: {url}')
                return url, text

        collect(self.config)
        with ThreadPoolExecutor(max_workers=8) as pool:
            downloaded = dict(pool.map(fetch, sorted(urls)))
        module = downloaded[YT_URL]
        hooks = [line for line in module.splitlines() if re.match(r'^youtube\.(response|request\.)', line)]
        self.assertEqual(len(hooks), 3, 'YouTube upstream hook structure changed')
        self.assertTrue(all('binary-body-mode=1' in line for line in hooks))
        for key in YT_ARGS:
            self.assertIn('{{{' + key + '}}}', module)
        script_urls = set(re.findall(r'script-path=(https://[^,\s]+)', '\n'.join(hooks)))
        self.assertEqual(len(script_urls), 2)
        for url in sorted(script_urls):
            _, script = fetch(url)
            check = subprocess.run(['node', '--check'], input=script, text=True,
                encoding='utf-8', capture_output=True, timeout=20)
            self.assertEqual(check.returncode, 0, f'YouTube script syntax error: {check.stderr}')
        with urlopen(Request('https://www.gstatic.com/generate_204',
                headers={'User-Agent': 'Egern/2.20.0'}), timeout=20) as response:
            self.assertEqual(response.status, 204)
        print(f'ONLINE PASS: {len(urls)} direct resources; 3 YouTube hooks; '
              f'{len(script_urls)} upstream JS syntax checks; HTTPS probe 204.', flush=True)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]] + rest, verbosity=2)
