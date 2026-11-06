#!/usr/bin/env python3
"""Build safe mirrors of fmz200's blockAds module (Surge) and plugin (Loon).

Why: the upstream bundle carries its own YouTube handling that fights the
pinned Maasea YouTube scripts these configs use:
  - Map Local / reject of every rr*.googlevideo.com/initplayback request
    (normal playback init too, not only ads) -> videos fail to start;
  - Map Local / reject of youtubei.../log_event, which Maasea's
    request.log_event hook needs -> the hook never runs;
  - a second, unpinned Maasea youtube.response.js on the same endpoints.
It also appends ~60 bank/payment/government hosts to the MITM list.

This script drops exactly those lines and keeps everything else verbatim.
Re-run it to refresh the mirrors from upstream:

    python3 scripts/trim_blockads.py
"""
import datetime
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'modules'
SOURCES = {
    'blockAds_safe.module': 'https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/blockAds.module',
    'blockAds_safe.plugin': 'https://raw.githubusercontent.com/fmz200/wool_scripts/main/Loon/plugin/blockAds.plugin',
}

# YouTube lines that conflict with the configs' own pinned Maasea hooks.
YOUTUBE_CONFLICT = re.compile(
    r'googlevideo\\?\.com\\?/initplayback'      # initplayback map-local / reject
    r'|googleapis\.com/\.\+log_event'           # log_event map-local / reject
    r'|youtubei\\?\.googleapis\\?\.com.*youtube\.response\.js'  # duplicate response script
)
SENSITIVE_HOST = re.compile(
    r'bank|alipay|icbc|cmbchina|cmbc|95516|unionpay|ccb\.com|abchina|boc\.cn|gov\.cn|psbc|spdb|'
    r'cebbank|citic|pingan|hxb|cibfintech|tenpay|jsbchina|jlbank|z-bank|cgbank', re.I)


def trim(text, name, url):
    out, dropped, hosts_dropped = [], [], []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith('#') and YOUTUBE_CONFLICT.search(line):
            dropped.append(stripped[:120])
            continue
        m = re.match(r'^(hostname\s*=\s*(?:%APPEND%\s*)?)(.*)$', line)
        if m:
            kept = []
            for h in (x.strip() for x in m.group(2).split(',')):
                if h and SENSITIVE_HOST.search(h):
                    hosts_dropped.append(h)
                elif h:
                    kept.append(h)
            line = m.group(1) + ', '.join(kept)
        out.append(line)
    if not dropped:
        sys.exit(f'{name}: no YouTube conflict lines found; upstream changed, review manually')
    stamp = datetime.date.today().isoformat()
    header = [
        f'# Mirror of {url}',
        f'# Generated {stamp} by proxy-configs/scripts/trim_blockads.py (heru08050413/QX).',
        f'# Dropped {len(dropped)} YouTube lines that break the pinned Maasea scripts',
        f'# (initplayback / log_event rejects, duplicate youtube.response.js) and',
        f'# {len(hosts_dropped)} bank/payment/government MITM hosts. Everything else is verbatim.',
    ]
    return '\n'.join(header + out) + '\n', dropped, hosts_dropped


def main():
    OUT.mkdir(exist_ok=True)
    for name, url in SOURCES.items():
        with urllib.request.urlopen(url, timeout=60) as r:
            text = r.read().decode('utf-8')
        body, dropped, hosts = trim(text, name, url)
        (OUT / name).write_text(body, encoding='utf-8')
        print(f'{name}: dropped {len(dropped)} YouTube lines, {len(hosts)} sensitive hosts')
        for d in dropped:
            print('   -', d)


if __name__ == '__main__':
    main()
