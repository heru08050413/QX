"""Stash Pro static/fixture audit, NOT the closed-source Stash runtime.

Requires PyYAML. --online checks public resources only, never airport URLs.
No configuration or subscription is modified. TLS verification stays enabled.
"""
import argparse
import copy
import fnmatch
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


CONFIG = read('Stash_Pro_V26.00.yaml')
AIRPORT = read('Stash_Pro_Airport.example.stoverride')
APP = read('Stash_Pro_AppAds_V26.00.stoverride')
YT = read('Stash_Pro_YouTube_V26.00.stoverride')


def merge(a, b):
    """Documented Stash merge for these files (no #!replace used here)."""
    if isinstance(a, dict) and isinstance(b, dict):
        result = copy.deepcopy(a)
        for key, val in b.items():
            result[key] = merge(result[key], val) if key in result else copy.deepcopy(val)
        return result
    if isinstance(a, list) and isinstance(b, list):
        return copy.deepcopy(b + a)
    return copy.deepcopy(b)


def validate(c):
    assert c['mode'] == 'rule'
    assert c['dns']['follow-rule'] is False
    assert '*' not in c['dns']['fake-ip-filter']
    assert 'proxy-server-nameserver' not in c['dns'], 'requires 3.6+'
    groups = {g['name']: g for g in c['proxy-groups']}
    assert len(groups) == len(c['proxy-groups'])
    builtins = {'DIRECT', 'REJECT', 'REJECT-DROP'}
    def walk(name, stack):
        assert name not in stack, 'policy cycle'
        for dest in groups[name].get('proxies', []):
            assert dest in groups or dest in builtins, 'unknown policy'
            if dest in groups:
                walk(dest, stack | {name})
    for name, g in groups.items():
        walk(name, set())
        assert 'filter' not in g, 'avoid filtered empty groups'
        assert 'url' not in g and 'benchmark-url' not in g, 'node benchmark is shared'
        assert g.get('proxies') or g.get('use')
        for provider in g.get('use', []):
            assert provider in c['proxy-providers']
    assert groups['稳定切换']['type'] == 'fallback'
    assert 60 <= groups['稳定切换']['interval'] <= 180
    assert groups['稳定切换']['lazy'] is False
    assert groups['Google']['proxies'][0] == 'AI'
    assert groups['默认代理']['proxies'][0] == 'REJECT'
    assert groups['YouTube']['proxies'][0] == 'REJECT'
    assert c['proxy-providers']['Airport']['benchmark-url'] == 'https://www.gstatic.com/generate_204'
    assert c['rules'][-1] == 'MATCH,兜底流量'
    refs = set()
    for rule in c['rules']:
        parts = rule.split(',')
        target = parts[-2] if parts[-1] == 'no-resolve' else parts[-1]
        assert target in groups or target in builtins, f'unknown rule policy: {rule}'
        if parts[0] == 'RULE-SET':
            assert parts[1] in c['rule-providers']
            refs.add(parts[1])
        if parts[0] in {'GEOIP', 'IP-CIDR', 'IP-CIDR6'} or parts[:2] == ['RULE-SET', 'ChinaIPs']:
            assert parts[-1] == 'no-resolve'
    assert refs == set(c['rule-providers'])
    rules = c['rules']
    assert rules.index('DOMAIN,api.weibo.cn,DIRECT') < rules.index('RULE-SET,Ads,广告过滤')
    assert rules.index('DOMAIN,api.zhihu.com,DIRECT') < rules.index('RULE-SET,Ads,广告过滤')
    assert rules.index('DOMAIN,gemini.google.com,AI') < rules.index('DOMAIN-SUFFIX,google.com,Google')
    assert rules.index('DOMAIN,copilot.microsoft.com,AI') < rules.index('DOMAIN-SUFFIX,microsoft.com,Microsoft')
    assert rules.index('DOMAIN,init-stream.maasea.workers.dev,YouTube') < rules.index('RULE-SET,ChinaDomains,DIRECT')
    for host in ['googlevideo.com', 'youtubei.googleapis.com']:
        assert any(r.startswith('AND,') and host in r and '(NETWORK,udp),(DST-PORT,443)' in r for r in rules)
    http = c.get('http', {})
    allowed = {'youtubei.googleapis.com', '*.googlevideo.com', 'api.weibo.cn', 'sub.weibo.cn',
               'we.weibo.cn', 'api.zhihu.com', 'edith.xiaohongshu.com'}
    assert set(http.get('mitm', [])) <= allowed
    assert 'ca' not in http and 'ca-passphrase' not in http
    for hook in http.get('script', []):
        assert hook['name'] in c['script-providers']
        assert hook['require-body'] is True
        assert 0 < hook['max-size'] <= 5242880
        assert 0 < hook['timeout'] <= 10
        re.compile(hook['match'])
        if hook['name'].startswith('yt-'):
            assert hook['binary-mode'] is True
    for p in c.get('script-providers', {}).values():
        if 'url' in p:
            assert '/65075cdb388fc5e3094afd7e7314c67b243f3525/' in p['url']
    encoded = json.dumps(c)
    assert 'skip-cert-verify' not in encoded
    assert 'external-controller' not in c


def route(host, network='tcp', port=443, sets=None, config=CONFIG):
    """Small test model of rules used here, not a Stash parser/runtime."""
    sets = sets or {}
    def suffix(pattern):
        return host == pattern or host.endswith('.' + pattern)
    for line in config['rules']:
        p = line.split(',')
        kind = p[0]
        target = p[-2] if p[-1] == 'no-resolve' else p[-1]
        if kind == 'MATCH':
            return target
        if kind == 'DOMAIN' and host == p[1] or kind == 'DOMAIN-SUFFIX' and suffix(p[1]):
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
    payload = {'app': APP, 'yt': YT, 'remote': remote or {}}
    result = subprocess.run(['node', str(BASE / 'scripts/test-stash-pro-runtime.cjs')],
                            input=json.dumps(payload), text=True, encoding='utf-8',
                            capture_output=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip(), flush=True)


class Audit(unittest.TestCase):
    def test_config_and_combined_overrides(self):
        validate(CONFIG)
        validate(merge(merge(merge(CONFIG, AIRPORT), APP), YT))

    def test_duplicate_keys_rejected(self):
        with self.assertRaises(ValueError):
            load('dns: 1\ndns: 2\n')

    def test_airport_swap_preserves_rules_and_groups(self):
        original = copy.deepcopy(CONFIG)
        for i in range(1, 4):
            private = copy.deepcopy(AIRPORT)
            provider = private['proxy-providers']['Airport']
            provider['url'] = f'https://airport-{i}.invalid/private-fixture'
            provider['path'] = f'./providers/private-v{i}.yaml'
            result = merge(original, private)
            self.assertEqual(result['rules'], CONFIG['rules'])
            self.assertEqual(result['proxy-groups'], CONFIG['proxy-groups'])
            self.assertEqual(result['proxy-providers']['Airport']['url'], provider['url'])
            self.assertEqual(result['proxy-providers']['Airport']['interval'], 21600)
            original = result

    def test_routing_fixtures(self):
        tests = {
            'dns.weixin.qq.com.cn': 'DIRECT', 'api.weibo.cn': 'DIRECT', 'api.zhihu.com': 'DIRECT',
            'weixin.qq.com': 'DIRECT', 'teg.tencent-cloud.net': 'DIRECT', '192.168.3.1': 'DIRECT',
            'gemini.google.com': 'AI', 'generativelanguage.googleapis.com': 'AI', 'chatgpt.com': 'AI',
            'cdn.oaistatic.com': 'AI', 'copilot.microsoft.com': 'AI', 'accounts.google.com': 'Google',
            'www.youtube.com': 'YouTube', 'rr1.googlevideo.com': 'YouTube',
            'youtubei.googleapis.com': 'YouTube', 'init-stream.maasea.workers.dev': 'YouTube',
            'raw.githubusercontent.com': '默认代理', 'www.netflix.com': '国际媒体',
            'unknown.example': '兜底流量', 'www.apple.com': 'Apple', 't.me': 'Telegram',
        }
        for host, expected in tests.items():
            with self.subTest(host=host):
                self.assertEqual(route(host), expected)
        # Simulate a future bad ad-list entry: protected API must still open.
        sets = {'Ads': {'api.zhihu.com', 'api.weibo.cn', 'dns.weixin.qq.com.cn', 'ads.example'}}
        for host in ['api.zhihu.com', 'api.weibo.cn', 'dns.weixin.qq.com.cn']:
            self.assertEqual(route(host, sets=sets), 'DIRECT')
        self.assertEqual(route('ads.example', sets=sets), '广告过滤')
        self.assertEqual(route('rr1.googlevideo.com', 'udp'), 'REJECT')
        self.assertEqual(route('rr1.googlevideo.com', 'udp', 53), 'YouTube')
        self.assertEqual(route('node.example', 'udp'), '兜底流量')
        self.assertEqual(route('weixin.qq.com', 'udp'), 'DIRECT')
        combined = merge(CONFIG, APP)
        self.assertEqual(route('api.zhihu.com', 'udp', config=combined), 'REJECT')
        self.assertEqual(route('api.zhihu.com', 'tcp', config=combined), 'DIRECT')

    def test_negative_mutations(self):
        def alter(path, val):
            c = copy.deepcopy(merge(CONFIG, YT))
            o = c
            for k in path[:-1]:
                o = o[k]
            o[path[-1]] = val
            return c
        mutations = [
            alter(['dns', 'fake-ip-filter'], ['*']),
            alter(['dns', 'follow-rule'], True),
            alter(['proxy-groups', 0, 'proxies'], ['missing']),
            alter(['proxy-groups', 0, 'proxies'], ['默认代理']),
            alter(['proxy-groups', 1, 'use'], ['missing']),
            alter(['proxy-groups', 1, 'filter'], 'US'),
            alter(['proxy-groups', 1, 'interval'], 3600),
            alter(['proxy-groups', 1, 'url'], 'https://example.com'),
            alter(['rules', -1], 'MATCH,DIRECT'),
            alter(['http', 'mitm'], ['*']),
            alter(['http', 'script', 0, 'binary-mode'], False),
            alter(['http', 'script', 0, 'max-size'], -1),
        ]
        for i, c in enumerate(mutations):
            with self.subTest(mutation=i), self.assertRaises(AssertionError):
                validate(c)

    def test_embedded_script(self):
        node_fixtures()

    @unittest.skipUnless(args.online, 'use --online for public resource GETs')
    def test_remote_resources(self):
        tasks = [('rule', name, p) for name, p in CONFIG['rule-providers'].items()]
        tasks += [('script', name, p) for name, p in YT['script-providers'].items()]
        def fetch(task):
            kind, name, p = task
            request = Request(p['url'], headers={'User-Agent': 'Stash-Pro-Audit/1.0'})
            with urlopen(request, timeout=40) as response:
                self.assertEqual(response.status, 200)
                data = response.read(16000000)
            text = data.decode('utf-8-sig')
            if kind == 'rule':
                parsed = load(text)
                self.assertIsInstance(parsed['payload'], list)
                self.assertTrue(parsed['payload'])
                for item in parsed['payload']:
                    self.assertIsInstance(item, str)
                    if p['behavior'] == 'ipcidr':
                        ipaddress.ip_network(item)
                    else:
                        self.assertNotIn(',', item)
                        self.assertNotIn('://', item)
                count = len(parsed['payload'])
            else:
                self.assertNotIn('<!DOCTYPE html', text)
                syntax = subprocess.run(['node', '--check'], input=text, text=True, encoding='utf-8', capture_output=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                count = len(data)
            print(f'PASS {kind} {name}: {count}; sha256={hashlib.sha256(data).hexdigest()}', flush=True)
            return kind, name, text
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(fetch, tasks))
        # Check actual current remote lists against protected and critical service routes.
        critical = {
            'dns.weixin.qq.com.cn': 'DIRECT', 'api.weibo.cn': 'DIRECT', 'api.zhihu.com': 'DIRECT',
            'chatgpt.com': 'AI', 'auth.openai.com': 'AI', 'gemini.google.com': 'AI',
            'generativelanguage.googleapis.com': 'AI', 'accounts.google.com': 'Google',
            'youtubei.googleapis.com': 'YouTube', 'rr1.googlevideo.com': 'YouTube',
            'init-stream.maasea.workers.dev': 'YouTube', 'raw.githubusercontent.com': '默认代理',
            'www.gstatic.com': 'Google', 'googleads.g.doubleclick.net': '广告过滤',
        }
        memberships = {}
        for kind, name, text in results:
            if kind != 'rule' or CONFIG['rule-providers'][name]['behavior'] != 'domain':
                continue
            patterns = load(text)['payload']
            def matches(host, pattern):
                if pattern.startswith('+.'):
                    return host == pattern[2:] or host.endswith('.' + pattern[2:])
                if pattern.startswith('.'):
                    return host.endswith(pattern)
                return fnmatch.fnmatchcase(host, pattern)
            memberships[name] = {host for host in critical if any(matches(host, p) for p in patterns)}
        for host, policy in critical.items():
            self.assertEqual(route(host, sets=memberships), policy, host)
        print(f'PASS {len(critical)} routes against current remote domain lists', flush=True)
        node_fixtures({name: text for kind, name, text in results if kind == 'script'})


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]] + rest, verbosity=2)
