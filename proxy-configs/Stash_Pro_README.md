# Stash Pro V26.00（单文件全栈覆写）

面向 **Stash 3.4+** 的原生单文件覆写：[Stash_Pro_V26.00.stoverride](Stash_Pro_V26.00.stoverride)。桌面静态与隔离脚本测试不等于 iPhone 真机验收。

## 文件与安装（与 `Stash_SR_V26.00.stoverride` 二选一，勿同开）

导入地址：

```text
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_V26.00.stoverride
```

1. 在 Stash 中选中**已经单独导入成功、能够看到节点的机场配置**作为当前配置，先停掉 VPN。
2. 在 **Override（覆写）** 中停用并移除其他所有 Stash 覆写，仅导入并启用上方的 `Stash_Pro_V26.00.stoverride`。
3. 开启 MITM：在 Stash 内生成或选用自己的根证书，并在「设置 → 通用 → 关于本机 → 证书信任设置」中完全信任。公共文件不包含 CA、口令或真实订阅。
4. 更新机场配置，确认 `美国节点`、`日本节点`、`新加坡节点`、`台湾节点`、`香港节点`、`稳定切换`、`手动节点` 已列出预期节点后启动连接。**不要同时启用 `Stash_SR_V26.00.stoverride`。**

## 核心设计（发挥 Stash 原生能力）

- **单文件全包、零机场锁定**：使用 `mode: rule`、`tcp-concurrent: true` 与 `#!replace` 接管 `proxy-groups` / `rule-providers` / `rules`，保留机场原有节点、DNS 与隧道参数，切换机场无需改写任何配置文件。
- **18 个 MRS 二进制纯索引规则集**：全面采用 Stash 3.1.0+ 支持的 `format: mrs`（0 个 `classical` 大文本集），覆盖 `217heidai/adblockmihomo.mrs`（合并去重广告域）及 `MetaCubeX/meta-rules-dat` 各业务/国内/私有规则集；加载快、内存占用低，全部 IP 规则与 `GEOIP,CN` 均加 `no-resolve`。
- **20 组策略与 6 地区共享 `lazy` 测速**：补全美/日/新/台/港/其他 + `稳定切换` + `手动节点`；全部 7 个 `url-test` 组统一使用 Google `gstatic/generate_204`、`interval: 900`、`tolerance: 200`、`lazy: true`（利用 Stash 同节点跨组共享测速结果省电），并采用无前瞻 C7 词边界与机场信息条排除规则；`AI` 组严格不含 `香港节点` 与 `DIRECT`。
- **防漏网、省电与连通保护**：保留「国内白名单 + `MATCH,兜底流量`」防漏；前置保护微信（含 `dns.weixin.qq.com`/`teg.tencent-cloud.net`）、微博启动域（`sdkapp/wbapp.uve.weibo.com`）、支付宝、个推、Apple 推送、三大运营商本机号一键登录及 Tailscale（`ts.net`、`tailscale.com/.io`、`100.64.0.0/10`、`fd7a:115c:a1e0::/48`）；新增 12 条高频遥测 `REJECT-DROP` 静默丢包防 SDK 死循环耗电；ChatGPT 监控域 `browser-intake-datadoghq.com` 走 `AI`；Hark、Wabi、Cue、Muse、Today、Grok、Claude、Cursor、Manus、Discord、Notion、Meta、Podcasts 显式规则均已对齐。
- **三段式全量去开屏 + 信息流 + YouTube**：
  1. **0-MITM 网络层**：`217heidai` MRS + `REJECT-DROP` + 小红书/知乎/闲鱼明确广告域。
  2. **原生零 JS `url-rewrite`（67 条）**：静态处理京东、淘宝、小红书（含水印去除）、知乎（含开屏与 `link.zhihu.com` 302 直跳）、乐播投屏、高德地图（含 `amap-aos-info-nogw` 新开屏接口）、汽车之家、网易有道词典、拼多多、闲鱼、猿辅导。
  3. **内嵌 `payload` JS（零外部下载）**：`stash-pro-ads` 内嵌于覆写文件内，覆盖微博 `sdkad.php`/`wbpullad.lua`/时间线、知乎推荐、小红书开屏/信息流、淘宝视频与图片开屏/Poplayer、京东 `functionId=start` 开屏（不触碰交易/订单/个人中心路径），异常或非 200 一律 `$done({})` 原样放行。
  4. **MITM 安全与 QUIC 控流**：严格仅解密 39 个内容/开屏白名单主机（**0 银行/支付/政务/12306/网盘/运营商/Apple/Tailscale/登录域**），并为对应 MITM 域配置精确 UDP 443（QUIC）拦截强制走 TCP（不影响全局 UDP 与 HY2/TUIC 隧道）。

## YouTube 增强边界与回退

- 文件末尾集成锁定 Maasea 提交 `65075cdb388fc5e3094afd7e7314c67b243f3525` 的 YouTube 三钩子（原生 `binary-mode: true`、`max-size: 5242880`、`timeout: 10`）。
- **第三方转发边界**：命中特定条件时，`youtube.request.js` 会将播放目标参数转交第三方 Worker `init-stream.maasea.workers.dev`（已将其规则归入 `YouTube` 组），未经 iPhone Stash 真机验证；**若真机播放卡顿或异常，可在覆写内临时注释 `yt-response` / `yt-request` 3 条 hook 与 YouTube 2 个 MITM 域，或切回备用覆写 [Stash_SR_V26.00.stoverride](Stash_SR_V26.00.stoverride)**。

## 验收与维护检查

1. 启用后核对 6 个地区池与 `稳定切换` / `手动节点` 非空（美国池至少两条可用），18 个 MRS 规则集下载无报错。
2. 实测微信收发、微博/知乎/小红书/淘宝/京东/高德开屏、Hark/Wabi/Cue/Muse/Today/Grok/Claude/Gemini/ChatGPT、Discord 与 Notion 连通性。
3. 桌面自动化校验（含 18 个 MRS 实时下载与 Zstd 头检查 + 2 个 Maasea 脚本 `node --check` + Node 沙盒隔离执行）：

```text
python proxy-configs/scripts/test-stash-pro.py --online
```
