# iOS 代理配置仓库(V26.00)

五套 iOS 代理 App 主配置 + Stash 策略/去广告覆写。目标优先级:**安全 > 稳定 > 去广告 > 低功耗**。
维护准则见 [`proxy-configs/CLAUDE.md`](proxy-configs/CLAUDE.md)。

## 一、主配置导入链接

| App | 导入链接(复制整行) |
|---|---|
| **Shadowrocket** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/shadowrocket_V26.00.lsr` |
| **Quantumult X** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/quantumult_B_V26.00` |
| **Egern** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Egern_Pro_V26.00.yml` |
| **Loon** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Loon_V26.00` |
| **Clash by Hako**(clash.md) | `https://raw.githubusercontent.com/heru08050413/QX/main/Clash_iso/Clash_iso_V26.00.yaml` |

**导入方法**
- **Shadowrocket**:首页 ➕ → 类型选「配置文件」→ 粘贴链接 → 下载后设为当前配置。
- **Quantumult X**:设置 → 配置文件 → 下载配置 → 粘贴链接(会整份替换,注意先备份节点)。
- **Egern**:配置 → 从 URL 导入 → 粘贴链接。
- **Loon**:配置 → 远程配置(或粘贴导入)→ 粘贴链接。
- **Stash**:直接使用机场提供的 Stash/Clash 配置作为当前配置，再按需在 Override(覆写) 添加下方策略或去广告覆写。
- **Clash by Hako**:这个链接作为**规则方案**添加,再用配置中心 ⊕「创建配置」勾选机场订阅 + Custom Nodes、规则选本方案,节点会自动分组;步骤见 [`Clash_iso/README.md`](Clash_iso/README.md)。YouTube 去广告/画中画需在 Modules 页开 HTTPS 解密并添加模块(该 README 第五节)。
- 导入后均需:**填入/确认机场订阅 → 生成并信任 MITM 根证书**(设置 → 通用 → 关于本机 → 证书信任设置)。
- ⚠️ **导入/切换配置前先停掉隧道,导入后再启动**(真机踩坑实录:隧道开着直接热导入,新旧路由/fake-ip 状态叠加,会出现"订阅正常、节点齐全、隧道显示已连,但流量 0 B/s"的假死;停一次重启即恢复)。

## 二、Stash 策略与去广告覆写(Override, 二选一勿同开)

| 文件 | 适用场景 |导入链接(复制整行)|
|---|---|---|
| **Stash Pro V26.00(推荐 · Stash 3.4+)** | 原生单文件全栈：18 个 MRS 二进制规则集 + 6 地区共享 `lazy` 测速 + 11+ App 去开屏/信息流内嵌脚本 + YouTube 增强 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Pro_V26.00.stoverride` |
| **Stash SR 移植版 V26.00(备选)** | 与 `shadowrocket_V26.00.lsr` 同源转换，保留小火箭全部 21 个 bm7 规则集与 18 个外部去广告脚本 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_SR_V26.00.stoverride` |

- 用法：在 Stash 中选中能显示节点的机场配置作为当前配置（先停隧道再导入），然后在 **Override（覆写）** 添加上面**二选一**的链接并开启 MITM 信任证书即可；`Stash Pro` 详细说明见 [`proxy-configs/Stash_Pro_README.md`](proxy-configs/Stash_Pro_README.md)。
- 安全边界：均不含任何银行/支付/政务/证件/网盘/运营商/Tailscale 域的 MITM；YouTube 增强含第三方 Worker 依赖且未在 Stash 真机验证，如播放异常可注释对应 hook 或切换方案。
- 若更新小火箭规则并同步备选移植版，可在 `proxy-configs/` 下运行 `python3 scripts/sr2stash.py`。

## 二-B、Shadowrocket 国内 App 开屏去广告(需手动加模块)

⚠️ **这一步不会自动生效,必须手动操作。** `shadowrocket_V26.00.lsr` 自 V26.00 起
**不再自带**国内 App(小红书/京东/拼多多/美团/网易云/爱奇艺/腾讯视频/芒果TV/12306/滴滴)
的开屏去广告脚本——原依赖的 `ddgksf2013/Scripts` 的 `Filter/` 目录已被上游整库重构删除,
10 条脚本全部 404,故连同对应 MITM hostname 一并移除(留着=无效解密纯耗电)。

这块能力改由下面这个外部模块承担,**你需要在 Shadowrocket 里手动添加**:

```
https://raw.githubusercontent.com/fmz200/wool_scripts/main/Surge/module/blockAds.module
```

**添加步骤**:Shadowrocket → 首页 **配置** → 选中当前配置右侧 **编辑** →
**模块(Modules)** → ➕ 添加 → 粘贴上面链接 → 保存 → 回到首页重新选中该配置生效。
添加后模块自带的 hostname 会自动追加到 MITM 列表,**无需手改配置文件**。

- 覆盖约 730 款 App/小程序(上游自述),含高德在内的国内主流 App;
- 2026-10-22 实测 HTTP 200,模块内 `#!date=2026-09-10`,仍在活跃维护;
- 部分 App 需清缓存或重装才生效(上游说明);
- 该模块与本仓库 Stash 覆写**功能重叠但互不冲突**(分属两个 App)。

> 没加这个模块 = 国内 App 开屏广告完全没拦。配置文件里只能写注释提示,
> 无法替你自动安装,这是 Shadowrocket 的模块机制决定的。

## 三、YouTube 功能矩阵(去广告 + 画中画/后台播放)

经逐套审查(2026-07,googlevideo 一列于 2026-10-22 据配置实况更正),各套 YouTube 能力与实现链路如下:

| App | 去广告 | 画中画/后台播放 | 实现与取舍 |
|---|---|---|---|
| **Shadowrocket** | ✅ | ✅ | Maasea 三钩子闭环(`youtube.response.js` + `youtube.request.js`,锁定 commit `65075cd`)+ UDP 强制 TCP。googlevideo **解密**(`initplayback` 的 path 在 TLS 内,不解密则服务端拼接广告会漏;代价是播放时发热/耗电上升) |
| **Egern** | ✅(最完整) | ✅ | Enhance 模块 + googlevideo 广告流拦截 + ad_break/统计信标 reject(v6.3.0)。视频流解密,发热略增 |
| **Loon** | ✅ | ✅ | Maasea `YouTube.Enhance.sgmodule` 插件(V26.00 补齐,此前缺失)+ `block-quic=true` 协同 |
| **Quantumult X** | ❌ | ❌ | 架构限制:Maasea 方案依赖 `binary-body-mode`(protobuf 改写),QX 无此参数、上游无 QX 适配版。不放不可靠的移植 |
| **Clash by Hako** | ✅(需加模块) | ✅(需加模块) | 新版 App 的 Modules 页支持 HTTPS 解密 + Surge 模块:添加 Maasea `YouTube.Enhance.sgmodule`;配置已拒绝 YouTube QUIC 配合解密。**同时必加** `Clash_iso/MITM_Safe.sgmodule`,详见 [`Clash_iso/README.md`](Clash_iso/README.md) 第五节。未真机验证 |
| **Stash** | ⚠️ 实验性 | ⚠️ 实验性 | `Stash_Pro_V26.00.stoverride` / `Stash_SR_V26.00.stoverride` 均用 Stash 原生 `binary-mode` 接入 Maasea 脚本,未在真机验证;含第三方 Worker 依赖 |

**客户端配套(装了 SR/Egern/Loon 之后)**:YouTube App 内 设置 → 播放 → 开启「画中画」;设置 → 后台播放和下载 → 开启「后台播放」。首次生效建议杀掉 YouTube App 重开。

## 四、连接稳定性(2026-07 专项修复)

针对"代理开着但 YouTube 打不开,需重开 App/手动切节点"的症状:

- **探针同源**:小火箭、Loon 的地区池测速改用 Google 自家 `gstatic/generate_204` 探针,池内节点"能到 Cloudflare 但到不了 Google"时自动换到同地区其他节点。小火箭已按用户要求删除 `YT-Auto` 和三个稳定池(2026-10-29),整个地区都连不上 Google 时,需在 YouTube 组手动换地区;Egern 也已删除 `YT-Auto` 和各稳定组(2026-11-05),其测速地址是全局 Cloudflare,整个地区连不上 Google 时同样需手动换;Loon 也已简化(2026-11-07):删除 YT-Auto 与稳定组,只留自动选择 + 7 个地区池共 8 个测速组。
- **UDP fail-fast**:节点不支持 UDP 时立即失败回落 TCP,不再直连进墙内黑洞挂死。
- 详见 `proxy-configs/CLAUDE.md` 安全基线第 7、8 条。

## 五、巡检

```bash
bash proxy-configs/scripts/url-health-sweep.sh
```
对全部配置内的远程规则/脚本/模块 URL 做 200 存活检查(iOS 代理 App 对死链是静默失败),上游脚本源同时被盯,死链即报警。
