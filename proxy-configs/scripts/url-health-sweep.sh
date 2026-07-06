#!/usr/bin/env bash
# =====================================================================
# url-health-sweep.sh — 远程 URL 死链巡检 (V26.00 起, CLAUDE.md §六-2)
# ---------------------------------------------------------------------
# 背景: 四轮审查累计查实 17+ 处静默死链(上游脚本/规则集被删或重构,
#   iOS 代理 App 对 404 是【静默失败】—— 去广告悄悄失效, 无任何报错).
#   本脚本把"每次大改顺手做 200 巡检"固化为可重复动作.
#
# 用法:   bash scripts/url-health-sweep.sh
# 退出码: 0 = 全部存活; 1 = 存在疑似死链(见 ✗ 行)
#
# 注意(实事求是):
#   • 纯 IP 的 DoH 端点(https://1.1.1.1/...)、github.com 主域 raw 跳转、
#     个人自托管域(kelee.one/ddgksf2013.top)、jsDelivr、releases/latest,
#     在某些网络出口会返回非 200 却仍可用 → 脚本对这些【降级为 WARN】,
#     不计入失败, 需人工核实.
#   • 真正的死链判定以 raw.githubusercontent.com 域上的 404 为准.
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

FILES=(shadowrocket_V26.00.lsr quantumult_B_V26.00 Egern_Pro_V26.00.yml Loon_V26.00 Stash_V26.00.yaml Stash_AdBlock_V26.00.stoverride)

# 外部维护的去广告模块/脚本(被 Loon/Egern/SR 引用, 或供 Stash 用户参考),
# 生效行里, 故显式列出让本脚本一并盯着 —— 这正是"去广告模块静默失效"的看门狗)
EXTRA_URLS=(
  "https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/blockAds.module"
  "https://raw.githubusercontent.com/zmqcherish/proxy-script/main/weibo.sgmodule"
  "https://raw.githubusercontent.com/Maasea/sgmodule/master/YouTube.Enhance.sgmodule"
  "https://github.com/BiliUniverse/ADBlock/releases/latest/download/BiliBili.ADBlock.sgmodule"
  "https://raw.githubusercontent.com/Script-Hub-Org/Script-Hub/main/modules/script-hub.stash.stoverride"
  "https://raw.githubusercontent.com/Script-Hub-Org/Script-Hub/main/Rewrite-Parser.js"
)
TIMEOUT=20
fail=0; warn=0; ok=0

# 提取生效行(去注释)上的 http(s) URL, 去装饰性资源.
# 关键: 只保留【可拉取的资源 URL】(以资源扩展名结尾, 或含 /rule/ 路径),
#   借此排除 [Rule]/rewrite 里的正则 pattern 片段与改写目标(如
#   https://youtubei... / .../artist/), 避免误报. 字符类含 () 以捕获
#   QingRex 那类含括号的编码 URL.
mapfile -t URLS < <(
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    grep -vE '^\s*[#;]' "$f" | grep -ohE 'https?://[A-Za-z0-9./_%@:()~-]+' | sed 's/[",;]*$//'
  done | grep -vE 'IconSet|/icons?/|/Color/|/Alpha/|/flag/|/mini/|Qure|Orz-3|iconlibrary|profile_img|Twoandz9' \
       | grep -vE 'YOUR_AIRPORT|YOUR_SERVICE|example|localhost|127\.0\.0\.1' \
       | grep -iE '\.(list|js|sgmodule|plugin|conf|module|lpx|snippet|mmdb|scripts|yaml|json)(\?[^ ]*)?$|/rule/|/dns-query$|^quic://' \
       | sort -u
)

URLS+=("${EXTRA_URLS[@]}")
echo "巡检 ${#URLS[@]} 个 URL (含 ${#EXTRA_URLS[@]} 个外部去广告模块; 超时 ${TIMEOUT}s)…"
for u in "${URLS[@]}"; do
  code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$u" 2>/dev/null)
  case "$u" in
    */dns-query|quic://*|*gist.githubusercontent.com*|*/releases/latest/*|*jsdelivr*|*clashios.app*|*kelee.one*|*ddgksf2013.top*|https://github.com/*/raw/*)
      if [ "$code" = "200" ]; then ok=$((ok+1)); else echo "⚠  $code  $u  (自托管/跳转/IP端点, 人工核实)"; warn=$((warn+1)); fi ;;
    *)
      if [ "$code" = "200" ]; then ok=$((ok+1)); else echo "✗  $code  $u"; fail=$((fail+1)); fi ;;
  esac
done

echo "──────────────────────────────────────────"
echo "OK=$ok  WARN=$warn(人工核实)  FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "无确定死链 ✓"; exit 0; } || { echo "存在疑似死链, 请处理上面 ✗ 行"; exit 1; }
