# Clash_iso · Clash by Hako(clash.md)iPhone 配置

V26.00 · 2026-11-01。一份可以直接导入的完整配置：机场订阅 + 自建节点 + 自动分组 + 域名级去广告；YouTube 去广告 / 画中画 / 后台播放通过 App 的 Modules（HTTPS 解密）实现，见第五节。

导入链接：

```
https://raw.githubusercontent.com/heru08050413/QX/main/Clash_iso/Clash_iso_V26.00.yaml
```

> 和 `proxy-configs/Clash_Hako_V26.00.js` 的区别：那份是**覆写脚本**，要套在机场给的完整 Clash 配置上，且不支持只有订阅链接（proxy-providers）的情况。本文件是**独立完整配置**，订阅链接和自建节点都写在这一份里。两者二选一，不要叠加。

## 一、怎么用

1. **先停掉 VPN**，再导入或切换配置（隧道开着热导入可能出现"已连接但没流量"）。
2. 用上面的链接导入后，**在 App 里编辑这份配置**（订阅链接不要提交到 GitHub）：
   - `proxy-providers → 机场订阅 → url`：换成你的机场订阅链接。
   - 有第二个机场：把 `机场订阅2` 那段的 `#` 去掉并填写。
   - 自建节点：在 `proxies:` 下按示例填写（去掉 `#`）。
3. 启动后等规则集下载完（共 22 个，首次需要几十秒），再检查分组里有没有节点。

> ⚠️ 如果用"URL 导入"并开启了自动更新，App 从 GitHub 重新拉取时会覆盖你填的订阅链接。建议导入一次后关闭这份配置的自动更新，或者把文件下载到本地再导入。

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

## 四、稳定、省电、快

- **只在用到时测速**：所有测速组都开了 `lazy`，没有流量经过的组不测速；间隔 900 秒。订阅本身不做健康检查。夜里不看 YouTube 就不会为 YouTube 测速。
- **探针同源**：地区池用 Google 的 `gstatic/generate_204` 测速，能到 Cloudflare 但到不了 Google 的节点会被换掉，减少"代理开着但 YouTube 打不开"。
- **YouTube 强制 TCP**：只拒绝 YouTube 的 UDP 443（QUIC），App 立即改走 TCP，起播和拖动更稳。不影响 Hysteria2/TUIC 节点本身。
- **规则用 MRS 二进制格式**：体积小、加载快，iOS 网络扩展的内存占用低；每天更新一次。
- **其他**：fake-ip DNS（国内 DoH）、关闭 IPv6（多数机场不支持，避免超时）、日志级别 warning、`tcp-concurrent` 并发握手。

## 五、去广告与 YouTube 画中画（新版 App 已支持 HTTPS 解密）

新版 Hako 在 **Modules（模块）** 页加入了 HTTPS Decryption 和模块，支持 Surge 格式的模块链接（`.sgmodule` / `.module`）。分两层：

**第一层：本配置自带**，域名级去广告（[217heidai/adblockfilters](https://github.com/217heidai/adblockfilters)），不需要证书。

**第二层：Modules 页手动添加**。配置文件管不到模块，需要你在 App 里加：

1. Modules 页打开 **HTTPS Decryption**，在 Certificate 里生成证书并安装、信任（设置 → 通用 → 关于本机 → 证书信任设置）。
2. 在 Module Link 里依次粘贴：

| 模块 | 作用 | 链接 |
|---|---|---|
| **MITM 安全排除**（必加） | 不解密银行/支付/政务/iCloud | `https://raw.githubusercontent.com/heru08050413/QX/main/Clash_iso/MITM_Safe.sgmodule` |
| Youtube (Music) Enhance | YouTube 去视频广告 + 画中画 + 后台播放 | `https://raw.githubusercontent.com/Maasea/sgmodule/master/YouTube.Enhance.sgmodule` |
| 广告拦截&净化合集 | 约 730 款国内 App 开屏/弹窗广告 | `https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/blockAds.module` |
| Spotify（可选） | 去广告、部分解锁（灰色功能） | `https://raw.githubusercontent.com/app2smile/rules/master/module/spotify.module` |

**为什么必须加「MITM 安全排除」**：核对「广告拦截&净化合集」的源文件，它会把约 60 个银行、支付、政务域名加进解密列表（工行、农行、建行、中行、邮储、招行、交行、浦发、平安、财付通、医保局等）。排除模块用 `-域名` 写法把它们挡在解密之外，代价是这些银行 App 的开屏广告不再被去掉。
⚠️ `-域名` 排除是 Surge 的模块语法，Hako 是否同样支持**未经验证**（官网文档在本环境打不开）。验证方法：开着模块打开一个银行 App，在 Hako 的请求记录里看该银行域名是否标为已解密；如果被解密了，说明排除不生效，请关掉「广告拦截&净化合集」。

**配置和模块的配合**：
- 本配置拒绝 YouTube 的 UDP 443（QUIC），App 只能走 TCP，模块才能解密并改写，这是 YouTube 模块生效的前提。
- 装了 YouTube 模块后画中画不再依赖美国节点；YouTube 组默认仍是美国节点，切别的地区也可以。
- 首次生效：杀掉 YouTube 重开；YouTube 设置里打开「画中画」。
- 解密会增加耗电：YouTube 模块要解密视频流（`*.googlevideo.com`），播放时发热会比不解密时高一些；大合集模块解密的主机越多，后台耗电越大。

**Spotify 显示 Update failed**：点它右边的 ⓘ 看链接。上游删库导致的 404 就换成上表的链接；如果链接正常，开着 VPN 再点 Update All（GitHub 在国内直连常失败）。Spotify 解锁属灰色功能，可能导致账号风险。

## 六、安全

- 配置里没有订阅 token；不关闭证书校验；不开局域网共享（`allow-lan: false`）。
- 规则集从 GitHub Raw 下载，经「节点选择」出口（GitHub 在国内直连不稳定）。

## 七、已验证 / 待真机验收

已做：YAML 解析；19 个分组、79 条规则、22 个规则集之间的引用全部能对上，无循环引用；所有测速组都是 lazy；用 27 个节点名样例测试分组正则（每个节点恰好进一个地区池或「其他节点」，信息条被排除，Russia/Australia/BUSINESS 不误判为美国）；22 个规则集链接和图标链接都返回 200；核对了「广告拦截&净化合集」源文件中的全部 939 个解密主机，其中银行/支付/政务主机全部被 `MITM_Safe.sgmodule` 的排除项覆盖。

**未做**：没有在 iPhone 上导入实测；本环境不能运行 mihomo 内核做 `-t` 语法检查。请导入后确认：无报错、规则集全部加载、分组里有节点；再测 YouTube 去广告与画中画、ChatGPT、微信，以及银行 App 是否未被解密（见第五节）。
