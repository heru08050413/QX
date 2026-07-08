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

## 二、Stash 去广告覆写(Override,可与主配置叠加)

| 文件 | 作用 | 需要 MITM | 导入链接 |
|---|---|---|---|
| 三合一总覆写(推荐) | 网络层拦截 + App 开屏 + 信息流脚本,一个链接全都有 | 层②③需要 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_All_V26.00.stoverride` |
| 网络层拦截 | 全局广告/追踪域名 REJECT,零耗电零腐坏 | 否 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_AdBlock_V26.00.stoverride` |
| App 开屏去广告 | 14+ 国内 App 开屏/弹窗接口 reject | 是 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_AppAdBlock_V26.00.stoverride` |
| 信息流脚本合集 | 知乎/小红书/微博/淘宝/京东等 14 App 信息流去广告 | 是 | `https://raw.githubusercontent.com/heru08050413/QX/main/proxy-configs/Stash_Script_V26.00.stoverride` |

> 导入位置:Stash → 配置 → **Override(覆写)** → 添加。**总覆写与三份分覆写二选一**,不要同时挂(规则重复)。
> 脚本 JS 全部镜像在本仓库 `proxy-configs/scripts/`,`script-providers` 只引本仓库链接——无第三方死链风险。
> 覆写不含任何银行/支付/政务/证件类 App 的 MITM。

## 三、YouTube 功能矩阵(去广告 + 画中画/后台播放)

经逐套审查(2026-07),各套 YouTube 能力与实现链路如下:

| App | 去广告 | 画中画/后台播放 | 实现与取舍 |
|---|---|---|---|
| **Shadowrocket** | ✅ | ✅ | Maasea `youtube.response.js`(youtubei 响应改写)+ UDP 强制 TCP。googlevideo **不**解密(省电取向,极少数服务端拼接广告可能漏) |
| **Egern** | ✅(最完整) | ✅ | Enhance 模块 + googlevideo 广告流拦截 + ad_break/统计信标 reject(v6.3.0)。视频流解密,发热略增 |
| **Loon** | ✅ | ✅ | Maasea `YouTube.Enhance.sgmodule` 插件(V26.00 补齐,此前缺失)+ `block-quic=true` 协同 |
| **Quantumult X** | ❌ | ❌ | 架构限制:Maasea 方案依赖 `binary-body-mode`(protobuf 改写),QX 无此参数、上游无 QX 适配版。不放不可靠的移植 |
| **Stash** | ❌ | ❌ | 架构限制:同上,Stash 脚本层未验证 protobuf 二进制改写。保留分流 + QUIC→TCP |

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
