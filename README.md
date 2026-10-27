# iOS 代理配置仓库(V26.00)

五套 iOS 代理 App 配置 + Stash 去广告覆写。目标优先级:**安全 > 稳定 > 去广告 > 低功耗**。
维护准则见 [`proxy-configs/CLAUDE.md`](proxy-configs/CLAUDE.md)。

## 一、主配置导入链接

| App | 导入链接(复制整行) |
|---|---|
| **Shadowrocket** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/shadowrocket_V26.00.lsr` |
| **Quantumult X** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/quantumult_B_V26.00` |
| **Egern** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Egern_Pro_V26.00.yml` |
| **Loon** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Loon_V26.00` |
| **Stash** | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_V26.00.yaml` |

**导入方法**
- **Shadowrocket**:首页 ➕ → 类型选「配置文件」→ 粘贴链接 → 下载后设为当前配置。
- **Quantumult X**:设置 → 配置文件 → 下载配置 → 粘贴链接(会整份替换,注意先备份节点)。
- **Egern**:配置 → 从 URL 导入 → 粘贴链接。
- **Loon**:配置 → 远程配置(或粘贴导入)→ 粘贴链接。
- **Stash**:配置 → 新建 → 从 URL 下载 → 粘贴链接,然后把 `proxy-providers` 里的订阅占位符换成你的机场订阅。
- 导入后均需:**填入/确认机场订阅 → 生成并信任 MITM 根证书**(设置 → 通用 → 关于本机 → 证书信任设置)。
- ⚠️ **导入/切换配置前先停掉隧道,导入后再启动**(真机踩坑实录:隧道开着直接热导入,新旧路由/fake-ip 状态叠加,会出现"订阅正常、节点齐全、隧道显示已连,但流量 0 B/s"的假死;停一次重启即恢复)。

## 二、Stash 去广告覆写(Override,可与主配置叠加)

| 文件 | 作用 | 需要 MITM | 导入链接 |
|---|---|---|---|
| 三合一总覆写(推荐) | 网络层拦截 + App 开屏 + 信息流脚本,一个链接全都有 | 层②③需要 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_All_V26.00.stoverride` |
| 网络层拦截 | 全局广告/追踪域名 REJECT,零耗电零腐坏 | 否 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_AdBlock_V26.00.stoverride` |
| App 开屏去广告 | 14+ 国内 App 开屏/弹窗接口 reject | 是 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_AppAdBlock_V26.00.stoverride` |
| 信息流脚本合集 | 知乎/小红书/微博/淘宝/京东等 14 App 信息流去广告 | 是 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Script_V26.00.stoverride` |

> 导入位置:Stash → 配置 → **Override(覆写)** → 添加。**总覆写与三份分覆写二选一**,不要同时挂(规则重复)。
> ⚠️ 仓库内另有 `Stash_Pro_YouTube_V26.00.stoverride`,属 **实验性·未经真机验证**,未列入上表。它与第三节 Stash 一行的 ❌ 并不矛盾:❌ 指"尚未验证可用",该文件是针对 Stash 原生 `binary-mode` 的适配尝试(脚本与 SR/Loon 同源并锁定 commit `65075cd`),但从未在真机证实去广告/PiP 生效,且含第三方 Worker 转发依赖。默认不建议启用;要试请先读 `proxy-configs/Stash_Pro_README.md` 的风险说明。
> 脚本 JS 全部镜像在本仓库 `proxy-configs/scripts/`,`script-providers` 只引本仓库链接——无第三方死链风险。
> 覆写不含任何银行/支付/政务/证件类 App 的 MITM。

## 二-A、Stash 小火箭移植版(打开 YouTube 才测速)

`Stash_SR_V26.00.stoverride` 由小火箭配置自动转换而来(`proxy-configs/scripts/sr2stash.py`),策略组、分流规则、去广告脚本、MITM 与小火箭一致。**所有测速组都开了 `lazy`**:策略组闲置时 Stash 跳过它的自动测速,所以 YouTube 相关的测速只在你看 YouTube 时进行,夜里不会整夜测速耗电。

```
https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_SR_V26.00.stoverride
```

- 用法:当前配置选能显示节点的 Stash 主配置(如 `Stash_V26.00.yaml` 填好订阅),Override 里添加上面的链接。它会整体替换策略组和规则,DNS 和节点沿用主配置。
- **启用它时请关掉其他 Stash 覆写**(`Stash_All`、`Stash_AdBlock`、`Stash_AppAdBlock`、`Stash_Script`、`Stash_Pro_*`),否则规则和脚本会重复。
- 需开 MITM 并信任自己的 CA。YouTube 脚本含第三方 Worker 依赖,且未在 Stash 真机验证;Spotify 解锁属灰色功能。
- 未移植:按域名 DNS(fake-ip 下已等效)、内置 Tailscale、推送绕过隧道、MITM 排除项。
- 小火箭改动后,在 `proxy-configs/` 下运行 `python3 scripts/sr2stash.py` 重新生成。

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
| **Stash** | ⚠️ 实验性 | ⚠️ 实验性 | `Stash_SR` / `Stash_Pro_YouTube` 用 Stash 原生 `binary-mode` 接入 Maasea 脚本,未在真机验证;含第三方 Worker 依赖 |

**客户端配套(装了 SR/Egern/Loon 之后)**:YouTube App 内 设置 → 播放 → 开启「画中画」;设置 → 后台播放和下载 → 开启「后台播放」。首次生效建议杀掉 YouTube App 重开。

## 四、连接稳定性(2026-07 专项修复)

针对"代理开着但 YouTube 打不开,需重开 App/手动切节点"的症状:

- **探针同源**:SR/Loon/Stash 新增 `YT-Auto` 自愈组,用 Google 自家 `gstatic/generate_204` 探针——节点"能到 Cloudflare 但到不了 Google"时自动切换,不再需要手动干预。**YouTube 组请保持选中 `YT-Auto`**。
- **UDP fail-fast**:节点不支持 UDP 时立即失败回落 TCP,不再直连进墙内黑洞挂死。
- 详见 `proxy-configs/CLAUDE.md` 安全基线第 7、8 条。

## 五、巡检

```bash
bash proxy-configs/scripts/url-health-sweep.sh
```
对全部配置内的远程规则/脚本/模块 URL 做 200 存活检查(iOS 代理 App 对死链是静默失败),上游脚本源同时被盯,死链即报警。
