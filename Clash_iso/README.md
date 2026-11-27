# Clash_iso · Clash by Hako(clash.md)iPhone 配置

V26.00 · 2026-11-27。一份可以直接导入的完整配置：机场订阅 + 自建节点 + 自动分组 + 安全分流 DoH + Sniffer 域名嗅探 + Tailscale 家庭组网支持 + 域名级/HTTPDNS 去广告；YouTube 去广告 / 画中画 / 后台播放通过 App 的 Modules（HTTPS 解密）实现，见第五节。

链接（用作**规则方案**）：

```
https://raw.githubusercontent.com/heru08050413/QX/main/Clash_iso/Clash_iso_V26.00.yaml
```

> 和 `proxy-configs/Clash_Hako_V26.00.js` 的区别：那份是**覆写脚本**，要套在机场给的完整 Clash 配置上。本文件是规则方案 + 分组，配合 App 的「创建配置」使用。两者二选一，不要叠加。

## 一、怎么用（推荐：创建配置）

Hako 把内容分成三个库：**配置**（Profiles）、**节点**（Nodes）、**规则**（Rules）。你在 Nodes 里手动添加的 Custom Nodes **不会自动进入导入的配置文件**，要用「创建配置」把"节点源 + 规则方案"合成一份配置。合成时，本方案里写了 `include-all` 的分组会自动收入你选中的全部节点和订阅，按名字分进各地区组。

（依据：Hako 客户端源码 `ConfigurationComposer.swift`——带 `include-all` 的组被改写为收入全部选中节点源的节点与订阅集合；规则方案自己的 `proxies` / `proxy-providers` 不参与合成，所以文件里的订阅占位符在这条路径下不会生效，也不用改。）

**先停掉 VPN**，然后：

1. **加机场订阅**：配置中心 → Profiles → 添加配置（Add Profile）→ 粘贴**机场订阅链接**。它会成为一个节点源（订阅链接只存在手机上，不进仓库）。
2. **加规则方案**：在 Rules 页用 ⊕ 从链接添加上面的地址；如果 Rules 页没有链接入口，就先在 Profiles 用这个链接添加配置，再点它的 ⓘ → 最下面「存成规则方案」。
3. **创建配置**：配置中心右上角 ⊕ →「创建配置（Create Profile）」：
   - 第一步「节点」：勾选**机场订阅**和 **Custom Nodes**（你的 10 个自建节点）；
   - 第二步「规则」：选 **Clash_iso**（刚添加的规则方案）；
   - 完成后切换到这份新配置，连接。
4. 等 24 个规则集下载完（首次几十秒），到「代理」页检查各地区组里有没有节点。

以后机场节点变动，更新订阅即可；本仓库的规则更新会跟随规则方案的链接，不会覆盖你的订阅和自建节点。

按你现有的自建节点名，分组结果是：`US-DMIT-LA-HY2`、`US-DMIT-LA-TCP`、`US-SV-Hysteria2`、`US-SV-VLESS-TLS`、`US-InstaBox-XHTTP`、`US-InstaBox-Stream`、`US-InstaBox-Packet` → 美国节点；`Home-JP` → 日本节点；`Home-KR` → 其他节点。

### 备用：直接导入为完整配置

不想用「创建配置」，也可以把上面的链接作为普通配置导入，然后在配置页「编辑源码」：把 `proxy-providers → 机场订阅 → url` 换成机场链接，自建节点按示例写进 `proxies:`。这样 Custom Nodes 库里的节点仍然用不上，而且开着自动更新时，从 GitHub 重新拉取会覆盖你填的内容。

## 二、自动分组

所有节点（订阅里的 + 你手写的自建节点）都会自动入组，依据是**节点名字里的地区词**：

| 节点名里有 | 进入 |
|---|---|
| 美国 / US / USA / 🇺🇸 / 洛杉矶 / Los Angeles … | 美国节点 |
| 香港 / HK / Hong Kong / 🇭🇰 | 香港节点 |
| 台湾 / TW / Taiwan / 🇹🇼 | 台湾节点 |
| 日本 / JP / Japan / 东京 / 🇯🇵 | 日本节点 |
| 新加坡 / SG / 狮城 / 🇸🇬 | 新加坡节点 |
| 都没有（韩国、德国、没写地区的自建节点…） | 其他节点 |
| 剩余流量 / 到期 / 官网 / 套餐 … | 不入组（是机场的信息条，不是节点） |

另外，「自动选择」和「全部节点」收所有可用节点。"US" 只按独立单词匹配，Russia / Australia / AUS 不会被误分进美国。

想让自建节点进某个地区池，就在名字里写上地区，例如 `🇺🇸 自建-洛杉矶`。

## 三、策略组

| 组 | 默认 | 说明 |
|---|---|---|
| 节点选择 | 美国节点 | 总出口，可切自动选择/各地区/全部节点 |
| YouTube | 美国节点 | 未装 YouTube 模块时，美国出口有官方免费画中画（非音乐视频）；装了模块后任意地区均可 |
| AI | 美国节点 | ChatGPT / Gemini / Claude 等；不含香港（OpenAI 不服务香港） |
| 谷歌服务 / Telegram / 社交媒体 / 流媒体 | 各自默认 | 可单独切地区 |
| 苹果服务 / 微软服务 | DIRECT | 国内有节点，直连更快 |
| 广告拦截 | REJECT | 某个 App 打不开时临时切 PASS 排查 |
| 漏网之鱼 | 节点选择 | 没命中任何规则的流量 |

**某个地区池为空时**（例如机场没有台湾节点），这个池会显示为空，选它的流量会失败。YouTube 和 AI 默认用美国节点：**如果你没有美国节点，请把这两个组手动切到有节点的地区**。手动选择会被记住。

## 四、Tailscale 家庭组网、稳定、省电、快

- **Tailscale 访问家里设备**：
  - `fake-ip-filter` 覆盖 `+.ts.net`、`+.tailscale.com`、`+.tailscale.io`、`+.lan`、`+.home.arpa` 及常见家用路由器 / NAS 域名，避免控制面与家庭设备域名被分配 `198.18.x.x` Fake-IP。
  - `nameserver-policy` 将家用内网及路由器域名走 `system` DNS，不泄露给公共 DoH；**未写死** `"+.ts.net": "100.100.100.100"`（因为 iOS 同一时间只能开一个系统级 VPN，开 Hako 时官方 Tailscale App 断开，写死 `100.100.100.100` 会导致 `*.ts.net` 解析超时）。待真机确认 Hako 是否支持 Mihomo 原生 `type: tailscale` 出站与 `ts://tailscale` DNS 后可再接入。
  - 规则层放行 `100.64.0.0/10`、`fd7a:115c:a1e0::/48` 及 `tailscale.com` / `tailscale.io`（`DIRECT`），保证 DERP 与 P2P 打洞直连。若家里开启了 **Tailscale Subnet Router** 且子网段不在常规 `10/8`、`172.16/12`、`192.168/16` 内，可在 `Clash_iso_V26.00.yaml` 的 `rules` 顶部按注释示例追加对应 `IP-CIDR,...,DIRECT,no-resolve`。
- **安全第一加密分流 DNS + 纯 IP 嗅探**：
  - `fake-ip` 秒回应用解析请求，开启 `respect-rules: true`（不开启 `prefer-h3`）实现严格隔离：海外域名真实解析经代理隧道发往 Cloudflare / Google DoH（**国内 DNS 零感知**）；机场节点域名（`proxy-server-nameserver`）与国内直连（`direct-nameserver` + `rule-set:国内,私网`）走国内加密 IP-DoH（`https://223.5.5.5/dns-query`、`https://1.12.12.12/dns-query`），防蜂窝/公共 Wi-Fi 运营商明文劫持。
  - 开启 Mihomo `sniffer:`（`force-dns-mapping` + `parse-pure-ip` + `override-destination: false`，跳过 Apple Push / `+.ts.net` / 米家），即使 App 缓存旧 IP 直连也能从 TLS SNI / HTTP Host 还原域名执行去广告与分流。
- **只在用到时测速 + 快速切网恢复**：所有 `url-test` 测速组全部启用 `lazy: true`（无流量不测速）、间隔 300 秒、容差 100ms，统一使用 Google `gstatic/generate_204` 探针；TCP 保活收紧至 `keep-alive-idle: 120` / `keep-alive-interval: 15`，进出电梯或蜂窝切网时更快清理僵尸连接。订阅本身不做健康检查。
- **YouTube 与国内开屏 API 强制 TCP & Google 登录隔离**：拒绝 YouTube 及缩略图以及微博/知乎/小红书/手淘/闲鱼/京东/高德/拼多多/B 站/有道等核心接口的 UDP 443（QUIC），防止 `Alt-Svc` 升级 HTTP/3 后绕过 Hako 模块解密（不影响 Hysteria2/TUIC 节点自身）；并将 Google 登录与 FCM 固定走「谷歌服务」，与 AI / YouTube 组隔离。
- **HTTPDNS 封堵与省电熔断**：内置 `HTTPDNS` 规则集 + 22 段硬编码 HTTPDNS IPv4/IPv6 段阻断（置于微信 `dns.weixin.qq.com` 保护之后），切断国内 App 缓存纯广告 IP 绕过规则的通道；12 条高频遥测域采用 `REJECT-DROP` 静默丢包防止 SDK 死循环重连耗电。
- **规则用 MRS 二进制格式**：体积小、加载快，iOS 网络扩展内存占用低，每天更新一次；关闭 IPv6（多数机场不支持，避免超时）、日志级别 `warning`、`tcp-concurrent` 并发握手、`微软服务` 扩充至含地区池可选。

## 五、去广告与 YouTube 画中画（新版 App 已支持 HTTPS 解密）

新版 Hako 在 **Modules（模块）** 页加入了 HTTPS Decryption 和模块，支持 Surge 格式的模块链接（`.sgmodule` / `.module`）。分两层：

**第一层：本配置自带**，域名级去广告（[217heidai/adblockfilters](https://github.com/217heidai/adblockfilters)），不需要证书；前置放行微信（含 TEG/`qq.com.cn`/`wx.qq.com`）、微博主域/图床与 SDK 启动域、知乎、支付宝/个推探测、Apple 推送与三大运营商本机号一键登录，避免误拦转圈。

**第二层：Modules 页手动添加**。配置文件管不到模块，需要你在 App 里加：

1. Modules 页打开 **HTTPS Decryption**，在 Certificate 里生成证书并安装、信任（设置 → 通用 → 关于本机 → 证书信任设置）。
2. 在 Module Link 里**务必先添加第一项（MITM 安全排除）**，再按需添加其余已锁定 commit 的模块：

| 模块 | 作用 | 链接 |
|---|---|---|
| **MITM 安全排除**（必加·第一步） | 不解密 Tailscale（`*.ts.net`）/Apple/12306/银行/支付/券商/保险/加密资产/航司/运营商/网盘/政务/登录与安全域（187 项） | `https://raw.githubusercontent.com/heru08050413/QX/main/Clash_iso/MITM_Safe.sgmodule` |
| Youtube (Music) Enhance | YouTube 去视频广告 + 画中画 + 后台播放 | `https://raw.githubusercontent.com/Maasea/sgmodule/65075cdb388fc5e3094afd7e7314c67b243f3525/YouTube.Enhance.sgmodule` |
| 广告拦截&净化合集 | 约 730 款国内 App 开屏/弹窗广告（如不想开大合集可不装） | `https://raw.githubusercontent.com/fmz200/wool_scripts/f6bcc087e4da7ebef3c596be4a3c0fa406661564/Surge/module/blockAds.module` |
| Spotify（可选） | 去广告、部分解锁（灰色功能） | `https://raw.githubusercontent.com/app2smile/rules/df6366a7024e0b3f0aa3510c5b791eea6f3cba89/module/spotify.module` |

**为什么必须先加「MITM 安全排除」**：核对「广告拦截&净化合集」的源文件，它会把大量银行、支付、券商、安全与政务域名加进解密列表（工行、农行、建行、中行、邮储、招行、交行、浦发、平安、广发、财付通、拉卡拉、合利宝、雪球、微信安全中心、医保局等），且开启 HTTPS 解密时也可能误伤 Tailscale 内网设备（`*.ts.net`）。如果忘记安装 `MITM_Safe.sgmodule` 就直接开大合集，这些敏感主机将被默认解密；排除模块用 `-域名` 写法将其挡在解密之外（共 187 项），代价是银行等 App 的开屏广告不再被去掉。
⚠️ `-域名` 排除是 Surge 的模块语法，Hako 是否同样支持**未经真机实测验证**。验证方法：开着模块打开一个银行 App 或家庭 `*.ts.net` HTTPS 服务，在 Hako 的请求记录里看该域名是否标为已解密；如果被解密了，说明排除不生效，请关掉「广告拦截&净化合集」。

**配置和模块的配合**：
- 本配置拒绝 YouTube 及缩略图的 UDP 443（QUIC），App 只能走 TCP，模块才能解密并改写，这是 YouTube 模块生效的前提；并已补充 Maasea 模块所需 `init-stream.maasea.workers.dev` 走 `YouTube` 组。
- `217heidai/adblockmihomo.mrs` 偏激进，若遇正常 App 误杀，可在策略组中临时将「广告拦截」切到 `PASS`（继续走后续分流，而非全盘直连）排查。
- 装了 YouTube 模块后画中画不再依赖美国节点；YouTube 组默认仍是美国节点，切别的地区也可以。
- 首次生效：杀掉 YouTube 重开；YouTube 设置里打开「画中画」。
- 解密会增加耗电：YouTube 模块要解密视频流（`*.googlevideo.com`），播放时发热会比不解密时高一些；大合集模块解密的主机越多，后台耗电越大。

**Spotify 显示 Update failed**：点它右边的 ⓘ 看链接。上游删库导致的 404 就换成上表的链接；如果链接正常，开着 VPN 再点 Update All（GitHub 在国内直连常失败）。Spotify 解锁属灰色功能，可能导致账号风险。

## 六、安全

- 配置里没有订阅 token；不关闭证书校验；不开局域网共享（`allow-lan: false`）。
- 规则集从 GitHub Raw 下载，经「节点选择」出口；备用完整配置模式下 `proxy-providers` 使用 `proxy: DIRECT` 拉取机场订阅，若机场订阅域被墙导致更新失败，请临时切换更新方式。

## 七、已验证 / 待真机验收

已做（本机离线与 HTTP 状态验证）：通过 [test-clash-configs.py](../proxy-configs/scripts/test-clash-configs.py) 自动化测试、[check-mitm-exclusions.py](../proxy-configs/scripts/check-mitm-exclusions.py)（含 `--online` 审计 970 个上游主机 0 遗漏）与 [test-clash-hako.cjs](../proxy-configs/scripts/test-clash-hako.cjs) 34 项离线 + 在线 MRS 校验：严格 YAML 解析（禁止重复键）；19 个分组、24 个 MRS 规则集与全量规则之间引用完整且无循环（全部 `IP-CIDR`/`IP-CIDR6` 与 IP 规则集均有 `no-resolve`）；安全分流 DoH（`respect-rules: true`）+ `sniffer` + HTTPDNS 阻断 + 国内开屏 API QUIC 阻断校验通过；6 地区池分区与机场信息条排除正则边界测试通过；`url-test` 探针统一为 `gstatic/generate_204`（300s / 100ms）且全部 `lazy`；第三方模块链接已全部锁定最新审计 commit SHA 并返回 HTTP 200。

**未做**：没有在 iPhone 上导入实测；本环境未运行 mihomo 内核做 `-t` 语法检查，也未对家庭 Tailscale 设备做真机端到端抓包。请导入后确认：无报错、规则集全部加载、分组里有节点；再实测是否支持 `type: tailscale`、YouTube 去广告与画中画、ChatGPT/Gemini/Claude、微信/微博，以及银行 App 与 `*.ts.net` 是否未被解密（见第五节）。
