# Quantumult X v5.2.0：单客户端修复与验收

日期：2026-09-19。基线：`4cbd5a0dd4dcf2bb528263495bf72757c4e82e64`，包含上一轮尚未成功推送的 Loon 提交。
本轮目标为公开版 Quantumult X 1.7.0；实际手机版本未知。官方 sample.conf 文件头仍写 v1.5.5 build 914，版本名称与示例覆盖范围不应混为一谈。

本轮只修改 `quantumult_B_V26.00`，附加本客户端测试和说明。Shadowrocket、Egern、Loon、Stash 及公共脚本不改。QX 与 Loon 保持独立提交；是否一并发布以用户授权及远端核对结果为准。

## 已实施

| 项目 | 修复 | 影响与限制 |
|---|---|---|
| 探测 | 全局 Cloudflare 探针改 HTTPS，总超时 3000→5000ms | 纳入 TLS 可达性，给握手更多时间；所有使用全局探针的组受影响。节点自带 server_check_url 仍可覆盖，不能代替吞吐或 YouTube 服务测试 |
| UDP 回退 | `fallback_udp_policy=direct` 改显式 reject | 官方说明此项只接受支持 UDP 的节点名，否则采用默认 reject；原 direct 不是有效的微信直连保护。主要消除配置歧义，不声称改变后必然改善通话 |
| YouTube | 新增纯节点 `YT-自动选择`，活跃时 120s、300ms 容差、闲置不主动轮询；置为 YouTube 首选 | 将 YouTube 从普通 Google 的 600s 地区选点中独立出来，保留全部原手动备选。跨地区选点可能改变出口，低延迟不证明高吞吐；CF 可达但 Google 不可达的盲点仍在 |
| 稳定地区组 | 美国、日本、狮城从延迟竞速改原生 available | 使用首个可用候选，活跃且结果不可用时检测；不添加该类型未证实的间隔/容差参数。不是无缝连接迁移，也不保证首节点吞吐最好 |
| 美国筛选 | 两个 US/USA 缩写匹配加字母边界，补常见美国名称 | 排除 Russia/Australia/RUS/AUS 等；支持 US01/USA01。其他地区的宽松名称筛选未凭空重写，仍须核对真实订阅 |
| Gemini | 新建独立组默认美国，远程 Gemini 表改绑该组，补五个接口的本地路由 | ChatGPT/Claude 与普通 Google 的默认地区不改；名字不证明真实出口地区、账号资格或可用性 |
| 微信 | 两个 DNS 主机及登录 PCDN 主机本地精确直连 | 在远程广告/HTTPDNS 表之前保护，不放开整个 qq.com。QX 当前导入的是规则表，不是 Loon 的带 Rewrite 插件，因此没有照搬“整包关闭” |
| 微博与广告 | 三个精确图片广告主机在宽泛直连前拒绝；广告远程表显式 force-policy=reject | 不整域拒绝业务 SDK；原宽泛微博直连继续保护正文。这些不是信息流脚本，不能承诺移除所有微博广告 |
| YouTube 本地分流 | API/备用 API、youtube.com、googlevideo.com、ytimg.com 指向 YouTube | 远程列表下载异常时仍保护核心路径；不是所有 YouTube Music 等依赖的离线完整替代 |

DNS 生效行、UDP 白名单范围、现有 MITM/证书、订阅占位符、原重写与交互任务、禁用 cron、FINAL 均保留。仅修改主配置，不批量更新其他客户端。

## 纠正旧判断：能力不等于已完成适配

1. 当前官方样例包含 per-domain DoH/DoQ，说明 placeholder IP 与 resolve-on-remote。旧注释“QX 没有按域名加密 DNS、没有占位映射”不能继续作为依据。本轮仅纠正说明，未盲目换 DNS 上游；国内 DoH 仍可能接收用于分流或直连的查询，不宣称零泄露。
2. 官方提供 `$response.bodyBytes` / `$done({bodyBytes: ...})` 示例；Maasea 固定提交 `65075cdb388fc5e3094afd7e7314c67b243f3525` 也存在 QuanX 适配。因此“没有 binary-body-mode 参数，所以不可能处理 YouTube”不成立。
3. 但上游 README 仅保证 Surge 测试；请求脚本 init 分支仍直接返回嵌套 `response` 和 URL 重定向，绕过部分平台转换。响应适配存在不等于这两个请求分支能在 QX 正常工作。上游根目录没有提供原生 QX YouTube 配置入口。
4. **本轮不启用该实验移植。因此 QX 本配置仍未提供 YouTube 脚本级去广告、隐藏上传按钮或 PiP 解锁。** 不以只接响应钩子代替完整链路，也不将尚未验证的请求钩子直接发布。

如后续批准实验移植，先单独形成原生请求/响应适配及参数方案，再用无缓存、有缓存、缓存不匹配的 initplayback、log_event、protobuf 正常/畸形/空响应做离线合同测试；最后进行真机 A/B，满足不中断、广告、隐藏上传、PiP 的验收再默认启用。客户端具有二进制能力不是跳过上述验证的理由。

## 自动验证

```powershell
pwsh -NoProfile -File proxy-configs/scripts/test-quantumult-audit.ps1
pwsh -NoProfile -File proxy-configs/scripts/test-quantumult-audit.ps1 -Online
```

- 全部允许的生效行变更从固定基线重建，白名单以外的生效行必须保持相同。
- 静态检查分段、策略组/规则引用、首选项、可用性组参数、保护规则、证书与任务开关。
- 48 个美国名称正反样本通过；12 项内存负向变异被独立语义检查检出。
- 在线：32 个启用的规则/重写/交互任务入口均 HTTP 200、非空、非 HTML；4 个重写资源中提取的 8 个直接脚本依赖可下载；共 13 份 JavaScript 通过 Node 语法检查；Cloudflare HTTPS HEAD 探针返回 204。
- 未执行任何下载的第三方 JavaScript。未检查图标、地理定位 HTTP API、资源解析器、真实订阅，也未递归遍历脚本运行时的全部依赖。

这些不是 QX 原生导入测试、完整远程合并规则仿真或真实节点测试。HTTP 200 不证明规则内容永远正确，JS 语法通过不证明手机 API 兼容。

## 保留风险与手机验收

- 发布后再刷新原 `quantumult_B_V26.00`，核对文件头 `v5.2.0 / 2026-09-19`；同时更新远程规则/重写资源。发布尚未确认时不要把本地完成当作手机已收到。
- 刷新前备份手机配置；仓库订阅是占位符，确认本机真实订阅/证书仍在，不重新生成 CA。旧手动选组可能保留，需要手动选择 YouTube → YT-自动选择、Gemini → 已验证美国出口。
- 检查新组非空、名称匹配正确；YouTube 连播、Wi-Fi/蜂窝切换、节点异常后的恢复时间需记录，不把 120s 当恢复保证。新池复用既有全订阅筛选：地区与线路资格并未通过真实节点核验，必要时手选原地区备选。
- 微信冷启动、消息图片、语音视频；微博/知乎正文、图片、登录；Gemini/ChatGPT 10 轮流式回复及附件。记录发生时间、策略、节点、DNS/连接错误、服务端状态；不要提交 token、Cookie 或私钥。
- UDP 白名单对直连也生效，不在列表中的其他 UDP 业务仍可能失败；本轮未无证据恢复 UDP443 或替换成静默丢弃 QUIC。`prefer-doh3` 保持原值，是否与当前网络或白名单交互需设备日志。
- HTTPDNS 表其他拦截仍在，额外安装的重写/规则也可能误伤；遇到问题先查实际命中，不继续增加整域豁免。
- `geo_location_checker` 的 HTTP ip-api 查询和浮动上游依赖保留，是既有隐私/供应链风险；没有在未验证脚本响应协议的情况下换提供商。
- QX 的 YouTube/微博信息流去广告缺口仍未解决。若需求是“本轮必须完整去广告”，应先完成上方独立移植验收，不将本提交当成需求全部达成。

回退时只 revert 本轮 QX 提交，不能把上轮 Loon 或更早 Egern/小火箭一起回退。

## 来源

- [Quantumult X App Store：1.7.0](https://apps.apple.com/us/app/quantumult-x/id1443988620)
- [官方配置样例：探针、UDP、DNS、available、策略组](https://raw.githubusercontent.com/crossutility/Quantumult-X/master/sample.conf)
- [官方二进制响应示例](https://raw.githubusercontent.com/crossutility/Quantumult-X/master/sample-bytes-rewrite.js)
- [Maasea 平台支持声明](https://raw.githubusercontent.com/Maasea/sgmodule/65075cdb388fc5e3094afd7e7314c67b243f3525/README.md)
- [核对的请求脚本固定版本](https://raw.githubusercontent.com/Maasea/sgmodule/65075cdb388fc5e3094afd7e7314c67b243f3525/Script/Youtube/youtube.request.js)
