#!/usr/bin/env python3
"""Convert shadowrocket_V26.00.lsr into a Stash override (Stash_SR_V26.00.stoverride).

Usage: python3 scripts/sr2stash.py            (run from proxy-configs/)
Re-run after every Shadowrocket change so the Stash port stays in sync.

Porting decisions (see the generated file's header for the user-facing summary):
- Every url-test / fallback group gets lazy: true. Stash then skips a group's
  automatic latency test once it has gone unused for a while, so the YouTube
  pools only probe while YouTube traffic flows. Benchmark results are shared
  per node across groups, so lazy must be on every group or idle groups keep
  probing the same nodes.
- Filters avoid regex lookaround (not verified for Stash; Stash_Pro avoids it).
  Junk-name exclusion filters are dropped: info pseudo-nodes fail the probe and
  are skipped by url-test / fallback anyway.
- PROTOCOL,UDP -> NETWORK,udp + DST-PORT,443 (Stash_Pro's verified form).
- REJECT-200 is not used as a rule policy: MITM'd hosts get DIRECT + a
  url-rewrite reject-200 (what Shadowrocket actually returns for them); other
  REJECT-200 hosts are plain HTTPS without MITM, where it behaves as REJECT.
- TAILSCALE rules are dropped (Shadowrocket-only built-in tunnel).
- [Host] is not ported: under Stash fake-ip, DIRECT domains resolve via the
  profile's domestic DoH and proxied domains resolve on the node.
- MITM "-host" exclusions are dropped: Stash only decrypts listed hosts.
"""
import re
import sys
from pathlib import Path

SRC = Path('shadowrocket_V26.00.lsr')
OUT = Path('Stash_SR_V26.00.stoverride')
BM7 = 'https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Clash'

YT_AUTO_INTERVAL = 60   # YT-Auto only probes while YouTube is in use (lazy)

# Shadowrocket list name -> [(provider name, bm7 Clash file, behavior, no-resolve)]
RULESETS = {
    'Advertising': [('Advertising', 'Advertising/Advertising.yaml', 'classical', False)],
    'Advertising_Domain': [('Advertising_Domain', 'Advertising/Advertising_Domain.yaml', 'domain', False)],
    'Privacy': [('Privacy', 'Privacy/Privacy.yaml', 'classical', False)],
    'Privacy_Domain': [('Privacy_Domain', 'Privacy/Privacy_Domain.yaml', 'domain', False)],
    'Hijacking': [('Hijacking', 'Hijacking/Hijacking.yaml', 'classical', False)],
    'OpenAI': [('OpenAI', 'OpenAI/OpenAI.yaml', 'classical', False)],
    'YouTube': [('YouTube', 'YouTube/YouTube.yaml', 'classical', False)],
    'Netflix': [('Netflix', 'Netflix/Netflix_Classical.yaml', 'classical', False)],
    'Apple': [('Apple', 'Apple/Apple.yaml', 'classical', False)],
    'Apple_Domain': [('Apple_Domain', 'Apple/Apple_Domain.yaml', 'domain', False)],
    'Spotify': [('Spotify', 'Spotify/Spotify.yaml', 'classical', False)],
    'TikTok': [('TikTok', 'TikTok/TikTok.yaml', 'classical', False)],
    'Telegram': [('Telegram', 'Telegram/Telegram.yaml', 'classical', False)],
    'Google': [('Google', 'Google/Google.yaml', 'classical', False)],
    'Microsoft': [('Microsoft', 'Microsoft/Microsoft.yaml', 'classical', False)],
    'BiliBili': [('BiliBili', 'BiliBili/BiliBili.yaml', 'classical', False)],
    'ChinaMax': [('ChinaMax_Domain', 'ChinaMax/ChinaMax_Domain.yaml', 'domain', False),
                 ('ChinaMax_IP', 'ChinaMax/ChinaMax_IP.yaml', 'ipcidr', True)],
    'ChinaIPs': [('ChinaIPs', 'ChinaIPs/ChinaIPs_IP.yaml', 'ipcidr', True)],
}
QURE = 'https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/'
# Shadowrocket groups carry no img-url, so Stash would show generic icons.
# Service groups get the app's icon; region pools (incl. YT-* / *稳定) get the flag.
ICONS = {
    'Proxy': 'Proxy', 'AI': 'ChatGPT', 'Meta': 'Facebook', 'YouTube': 'YouTube',
    'Netflix': 'Netflix', 'Spotify': 'Spotify', 'TikTok': 'TikTok', 'Telegram': 'Telegram',
    'Instagram': 'Instagram', 'Twitter': 'Twitter', '苹果服务': 'Apple', '谷歌服务': 'Google_Search',
    '微软服务': 'Microsoft', '哔哩哔哩': 'bilibili', 'AutoSelect': 'Auto', 'YT-Auto': 'Speedtest',
    'StableSelect': 'Available', 'Fallback': 'Available_1', 'Final': 'Final',
}
REGION_ICONS = {'香港': 'Hong_Kong', '台湾': 'Taiwan', '日本': 'Japan', '新加坡': 'Singapore', '美国': 'United_States'}
EXTRA_ICONS = {'Gemini': 'https://raw.githubusercontent.com/fmz200/wool_scripts/main/icons/apps/Gemini_01.png'}


def icon_for(name):
    if name in EXTRA_ICONS:
        return EXTRA_ICONS[name]
    if name in ICONS:
        return QURE + ICONS[name] + '.png'
    for k, v in REGION_ICONS.items():
        if k in name:
            return QURE + v + '.png'
    return None


SCRIPT_KEYS = ('type', 'pattern', 'requires-body', 'max-size', 'binary-body-mode',
               'script-path', 'argument', 'engine', 'timeout', 'script-update-interval')


def sections(text):
    out, cur = {}, None
    for line in text.splitlines():
        m = re.match(r'^\[(.+)\]\s*$', line)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur is not None:
            out[cur].append(line)
    return out


def active(lines):
    return [l.strip() for l in lines if l.strip() and not l.lstrip().startswith(('#', ';', '//'))]


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def de_lookaround(rx):
    # (?=$|[^A-Za-z]) -> (?:$|[^A-Za-z]): same truth value for a "name contains" test.
    return rx.replace('(?=$|[^A-Za-z])', '(?:$|[^A-Za-z])')


def parse_group(line):
    name, rest = line.split(' = ', 1)
    parts = [p.strip() for p in rest.split(', ')]
    gtype, members, opts = parts[0], [], {}
    i = 1
    while i < len(parts):
        p = parts[i]
        if p.startswith('policy-regex-filter='):
            opts['filter'] = ', '.join(parts[i:])[len('policy-regex-filter='):]
            break
        if re.match(r'^[a-z-]+=', p):
            k, v = p.split('=', 1)
            opts[k] = v
        else:
            members.append(p)
        i += 1
    return name.strip(), gtype, members, opts


def convert_groups(lines):
    out, names = [], []
    for line in active(lines):
        if ' = ' not in line:
            continue
        name, gtype, members, opts = parse_group(line)
        names.append(name)
        g = [f'  - name: {q(name)}', f'    type: {gtype}']
        icon = opts.get('img-url') or icon_for(name)
        if icon:
            g.append(f'    icon: {q(icon)}')
        if gtype in ('url-test', 'fallback'):
            if members:
                g.append('    proxies: [' + ', '.join(q(m) for m in members) + ']')
            else:
                g.append('    include-all: true')
                flt = opts.get('filter', '')
                if flt and '(?!' not in flt:
                    g.append(f'    filter: {q(de_lookaround(flt))}')
            if opts.get('url'):
                g.append(f"    url: {q(opts['url'])}")
            interval = int(opts.get('interval', 600))
            if name == 'YT-Auto':
                interval = YT_AUTO_INTERVAL
            g.append(f'    interval: {interval}')
            if gtype == 'url-test' and opts.get('tolerance'):
                g.append(f"    tolerance: {opts['tolerance']}")
            g.append('    lazy: true')
        else:
            g.append('    proxies: [' + ', '.join(q(m) for m in members) + ']')
        out.append('\n'.join(g))
    return out, names


def convert_rules(lines, mitm_hosts):
    rules, providers, dropped, rewrites = [], {}, [], []
    for line in active(lines):
        if line.startswith(('RULE-SET,', 'DOMAIN-SET,')):
            kind, url, policy = line.split(',', 2)
            base = url.rsplit('/', 1)[-1].rsplit('.', 1)[0]
            for pname, path, behavior, nores in RULESETS[base]:
                providers[pname] = (path, behavior)
                rules.append(f'RULE-SET,{pname},{policy}' + (',no-resolve' if nores else ''))
            continue
        m = re.match(r'^AND,\(\((.+)\),\(PROTOCOL,UDP\)\),(\w+)$', line)
        if m:
            rules.append(f'AND,(({m.group(1)}),(NETWORK,udp),(DST-PORT,443)),{m.group(2)}')
            continue
        if line.startswith('FINAL,'):
            rules.append('MATCH,' + line.split(',', 1)[1])
            continue
        if ',TAILSCALE' in line:
            dropped.append(line)
            continue
        if line.endswith(',REJECT-200'):
            rtype, host = line.split(',')[:2]
            if rtype == 'DOMAIN' and host in mitm_hosts:
                rules.append(f'DOMAIN,{host},DIRECT')
                rewrites.append(f"^https?:\\/\\/{re.escape(host)}\\/ - reject-200")
            else:
                rules.append(line[:-len('REJECT-200')] + 'REJECT')
            continue
        rules.append(line)
    return rules, providers, dropped, rewrites


def split_script(rest):
    keys = '|'.join(re.escape(k) for k in SCRIPT_KEYS)
    parts = re.split(rf',\s*(?=(?:{keys})=)', rest)
    return dict(p.split('=', 1) for p in parts)


def convert_scripts(lines):
    hooks, providers = [], {}
    for line in active(lines):
        if ' = type=' not in line:
            continue
        name, rest = line.split(' = ', 1)
        o = split_script(rest)
        path = o['script-path']
        pname = Path(path).stem
        if pname in providers and providers[pname] != path:
            pname = f'{pname}-{len(providers)}'
        providers[pname] = path
        binary = o.get('binary-body-mode') in ('1', 'true')
        h = [f'    # {name}',
             f'    - name: {q(pname)}',
             f"      match: {q(o['pattern'])}",
             f"      type: {'request' if o['type'] == 'http-request' else 'response'}"]
        if o.get('requires-body') in ('1', 'true'):
            h.append('      require-body: true')
        if binary:
            h.append('      binary-mode: true')
        h.append(f'      max-size: {5242880 if binary else 2097152}')
        h.append('      timeout: 10')
        if o.get('argument'):
            h.append(f"      argument: {q(o['argument'])}")
        hooks.append('\n'.join(h))
    return hooks, providers


def convert_rewrites(lines):
    out = []
    for line in active(lines):
        pat, target, kind = line.rsplit(' ', 2) if line.count(' ') >= 2 else (line, '-', 'reject')
        kind = {'header': 'transparent'}.get(kind, kind)
        out.append(f'{pat} {target} {kind}')
    return out


def main():
    sec = sections(SRC.read_text(encoding='utf-8'))
    mitm_line = next(l for l in active(sec['MITM']) if l.startswith('hostname'))
    mitm = [h.strip() for h in mitm_line.split('=', 1)[1].split(',') if h.strip() and not h.strip().startswith('-')]
    groups, gnames = convert_groups(sec['Proxy Group'])
    rules, rproviders, dropped, rw_extra = convert_rules(sec['Rule'], set(mitm))
    hooks, sproviders = convert_scripts(sec['Script'])
    rewrites = convert_rewrites(sec['URL Rewrite']) + rw_extra

    L = ['name: "Stash SR 移植版 V26.00"',
         'desc: "由 shadowrocket_V26.00.lsr 自动转换(scripts/sr2stash.py)。策略组/分流/去广告脚本/MITM 与小火箭一致; '
         '所有测速组 lazy: 组闲置时不测速, YouTube 测速只在看 YouTube 时进行。叠加在能显示节点的机场或主配置上使用; '
         '需开 MITM 并信任自己的 CA。YouTube 脚本含第三方 Worker 依赖, 未在 Stash 真机验证。"',
         '# 自动生成, 请勿手改: 改 shadowrocket_V26.00.lsr 后在 proxy-configs/ 下运行 python3 scripts/sr2stash.py。',
         '# 未移植(Stash 无对应或无法核实): [Host] 按域名 DNS(fake-ip 下已等效)、内置 Tailscale、',
         '#   bypass-tun(含 APNs 绕过)、MITM 排除项(Stash 只解密列出的主机)。',
         '# 已丢弃的 Tailscale 规则: ' + ' | '.join(dropped),
         '',
         'proxy-groups: #!replace']
    L += groups
    L += ['', 'rule-providers: #!replace']
    for pname, (path, behavior) in rproviders.items():
        L += [f'  {pname}:', f'    behavior: {behavior}', '    format: yaml',
              f'    url: {BM7}/{path}', f'    path: ./rules/stash-sr-{pname.lower()}.yaml', '    interval: 86400']
    L += ['', 'rules: #!replace'] + [f'  - {q(r)}' for r in rules]
    L += ['', 'http:', '  mitm:'] + [f'    - {q(h)}' for h in mitm]
    L += ['  url-rewrite:'] + [f'    - {q(r)}' for r in rewrites]
    L += ['  script:'] + hooks
    L += ['', 'script-providers:']
    for pname, url in sproviders.items():
        L += [f'  {q(pname)}:', f'    url: {url}', '    interval: 86400']
    OUT.write_text('\n'.join(L) + '\n', encoding='utf-8')
    print(f'groups={len(groups)} rules={len(rules)} rule-providers={len(rproviders)} '
          f'mitm={len(mitm)} url-rewrite={len(rewrites)} scripts={len(hooks)} '
          f'script-providers={len(sproviders)} dropped={len(dropped)}', file=sys.stderr)


if __name__ == '__main__':
    main()
