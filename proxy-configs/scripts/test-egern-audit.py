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
YT_URL = 'https://raw.githubusercontent.com/Maasea/sgmodule/master/YouTube.Enhance.sgmodule'
YT_ARGS = {'屏蔽上传按钮': 'true', '屏蔽选段按钮': 'true', '屏蔽Shorts按钮': 'false',
           '字幕翻译语言': 'off', '启用调试模式': 'false'}
NEW_WEIBO_HOSTS = ['api.weibo.cn', 'mapi.weibo.cn', 'api.weibo.com', 'mapi.weibo.com',
                   'sdkapp.uve.weibo.com', 'wbapp.uve.weibo.com']
OLD_WEIBO_HOSTS = ['*.weibo.cn', '*.weibo.com', '*.weibo.com.cn', '*.weibocdn.com',
                   '*.sina.cn', '*.sina.com.cn', '*.sinajs.cn']


def expected_delta(original):
    """Explicit semantic allowlist against immutable pre-Egern-change revision."""
    expected = copy.deepcopy(original)
    del expected['dns']['public_ip_lookup_url']
    for name in ('美国', '美国稳定'):
        g = body(group(expected, name))
        g['filter'] = g['filter'].replace('|US|USA|', '|(?:^|[^A-Za-z])(?:US|USA)(?=$|[^A-Za-z])|')
    g = body(group(expected, 'Gemini'))
    g['policies'].remove('订阅')
    g['policies'].append('订阅')
    yt = group(expected, 'YouTube')
    expected['policy_groups'].insert(expected['policy_groups'].index(yt), {'smart': {
        'name': 'YT-Auto', 'policies': ['香港', '台湾', '日本', '新加坡', '美国'],
        'flatten': True, 'latency_test_url': 'https://www.gstatic.com/generate_204', 'hidden': False}})
    body(yt)['policies'].insert(0, 'YT-Auto')
    rules = expected['rules']
    udp = next(r for r in rules if body(r).get('name') == '国内 UDP 前置直连 (微信 VOIP 保护)')
    rules.remove(udp)
    obsolete = next(r for r in rules if body(r).get('name') == '12306 禁 QUIC')
    rules.remove(obsolete)
    api = domain('youtubei.googleapis.com', 'YouTube')
    rules.remove(api)
    anchor = next(r for r in rules if body(r).get('name') == 'YT 广告视频流')
    rules.insert(rules.index(anchor), udp)
    ad_break = next(r for r in rules if body(r).get('name') == 'YT 广告插入点')
    body(ad_break)['match'] += '(?:[/?]|$)'
    anchor = next(r for r in rules if body(r).get('name') == 'YT 广告质量上报')
    additions = [api, domain('init-stream.maasea.workers.dev', 'YouTube'),
                 domain('googlevideo.com', 'YouTube', 'domain_suffix')]
    additions += [domain(h, 'DIRECT') for h in WECHAT]
    additions += [domain(h, 'REJECT') for h in IMAGES]
    i = rules.index(anchor) + 1
    rules[i:i] = additions
    retired = [('domain_suffix', 'biz.weibo.com'), ('domain', 'bootpreload.uve.weibo.com'),
               ('domain_suffix', 'fastimage.uve.weibo.com'), ('domain_suffix', 'adimg.vue.weibo.com'),
               ('domain_suffix', 'sdkapp.uve.weibo.com')]
    for kind, host in retired:
        rules.remove(domain(host, 'REJECT', kind))
    i = rules.index(domain('gemini.google.com', 'Gemini', 'domain_suffix'))
    rules[i:i] = [domain(h, 'Gemini') for h in GEMINI]
    hosts = expected['mitm']['hostnames']
    hosts['excludes'][0:0] = ['12306.cn', '*.12306.cn']
    i = hosts['includes'].index(OLD_WEIBO_HOSTS[0])
    assert hosts['includes'][i:i + len(OLD_WEIBO_HOSTS)] == OLD_WEIBO_HOSTS
    hosts['includes'][i:i + len(OLD_WEIBO_HOSTS)] = NEW_WEIBO_HOSTS
    hosts['includes'].remove('gateway.12306.cn')
    for module in expected['modules']:
        url = module['url']
        if (('QingRex/' in url and ('Youtube%20' in url or 'Script%20Hub' in url)) or
                url == 'https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/weibo.module'):
            module['enabled'] = False
        if url == YT_URL:
            module['compat_arguments'] = YT_ARGS.copy()
    return expected


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
        cls.expected = expected_delta(cls.original)

    def test_complete_change_scope(self):
        self.assertEqual(self.config, self.expected)

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
        yt = group(self.config, 'YT-Auto')
        self.assertEqual(list(yt), ['smart'])
        self.assertTrue(body(yt)['flatten'])
        self.assertTrue(body(yt)['latency_test_url'].startswith('https://'))
        self.assertEqual(body(group(self.config, 'YouTube'))['policies'][0], 'YT-Auto')
        self.assertEqual(body(group(self.config, 'Gemini'))['policies'][0], '美国')

    def test_us_filters(self):
        yes = ['US', 'USA', 'us-01', 'US01', 'USA01', '机场-US-01', '美国01', '🇺🇸 01',
               'United States 01', 'America 01', '洛杉矶01', 'SiliconValley']
        no = ['Russia', 'RUS-01', 'Australia', 'AUS-01', 'RUS01', 'AUS01', 'Austria',
              '🇦🇺 Sydney', 'JP 日本', 'HK 香港', 'Business 01', 'Plus 01']
        for name in ('美国', '美国稳定'):
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
        for h in ['mp.weixin.qq.com', 'api.zhihu.com', 'youtubei.googleapis.com', 'rr1.googlevideo.com']:
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
        self.assertEqual(len([m for m in enabled if 'ScriptHub' in m['url'] or 'Script%20Hub' in m['url']]), 1)

    def test_negative_mutations(self):
        cases = []
        c = copy.deepcopy(self.config); del c['mitm']['hostnames']['excludes'][0]; cases.append(c)
        c = copy.deepcopy(self.config); c['dns']['public_ip_lookup_url'] = 'https://ifconfig.me/ip'; cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, '美国'))['filter'] = '(?i)US'; cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'YouTube'))['policies'].pop(0); cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'YT-Auto'))['latency_test_url'] = 'http://www.gstatic.com/generate_204'; cases.append(c)
        c = copy.deepcopy(self.config); c['rules'].remove(domain('dns.weixin.qq.com', 'DIRECT')); cases.append(c)
        c = copy.deepcopy(self.config); c['rules'].insert(0, c['rules'].pop(c['rules'].index(domain('youtubei.googleapis.com', 'YouTube')))); cases.append(c)
        c = copy.deepcopy(self.config); body(group(c, 'Gemini'))['policies'].insert(0, '订阅'); cases.append(c)
        c = copy.deepcopy(self.config); next(m for m in c['modules'] if m['url'] == YT_URL)['compat_arguments']['屏蔽上传按钮'] = 'false'; cases.append(c)
        c = copy.deepcopy(self.config); next(m for m in c['modules'] if 'Youtube%20' in m['url'])['enabled'] = True; cases.append(c)
        for i, changed in enumerate(cases):
            with self.subTest(mutation=i):
                with self.assertRaises(AssertionError):
                    assert changed == self.expected, 'Unauthorized semantic delta'

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
