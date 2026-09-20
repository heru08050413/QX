# Clash by Hako 单客户端交付审查

日期：2026-09-20。原仓库基线：`e7e2324579a2d1003dde6e1020b81fd1305e2523`。
用户确认 iPhone 客户端 1.0.9，并授权检查通过后发布 main。

## 范围与选择

仅新增 Hako 配置生成器、使用说明、测试和本记录四个文件；不修改 Shadowrocket、Egern、Loon、Stash、QX 配置。
采用保留 DNS/TUN 的 V3 式结构，而非替用户覆盖未知网络环境。脚本独立编写，未复制/嵌入第三方 Runestone 的完整代码。

标准完整机场 Profile 的 `proxies` 是唯一节点输入；运行时 Provider 明确拒绝，不假设远端节点已经合并。自建/复杂链路不是这版交付目标。节点之间的无环 `dialer-proxy` 可保留，但引用被删除旧策略组的链路直接拒绝。

节点重复、空输入、保留名占用、无效 server/port、超过 2000 节点、旧 DNS/TUN 依赖失效会中止；禁止默默生成直连兜底。该防护不是全部 mihomo 字段的通用校验器，原始配置仍须先通过客户端校验。

## 接口和兼容性依据

- [官方 ScriptEngine.swift](https://github.com/TokenPLS/Hako-Client/blob/b05832246fcac69d13ff16df871a8d53fd394c10/apple/HakoClient/Sources/ConfigUI/ScriptEngine.swift)：JavaScriptCore 同步调用 `main(config, profileName)`，返回配置对象；5 秒执行限制。
- [ScriptLibrary.swift](https://github.com/TokenPLS/Hako-Client/blob/b05832246fcac69d13ff16df871a8d53fd394c10/apple/HakoClient/Sources/ConfigUI/ScriptLibrary.swift)：URL 导入保存脚本文本；Test Run 使用内置示例，不测速真实机场。
- [ProfileActivationCoordinator.swift](https://github.com/TokenPLS/Hako-Client/blob/b05832246fcac69d13ff16df871a8d53fd394c10/apple/HakoClient/Sources/ConfigStore/ProfileActivationCoordinator.swift)：Profile Script → 全局覆写 → 合并后脚本 → 全局脚本 → 客户端转换；文档提醒只使用一套生成器。
- [官方代理组](https://clash.md/zh/guide/config/proxy-groups)：url-test/fallback、expected-status、lazy、interval 秒/timeout 毫秒。
- [官方 MRS 最佳实践](https://clash.md/zh/guide/config/best-practice)：iOS 优先二进制规则，避免大量重复文本集合。
- [Hako v1.19.30-hako.2 路由源码](https://github.com/TokenPLS/Hako/blob/v1.19.30-hako.2/tunnel/tunnel.go)：策略组解包后遇到 PASS，继续下一条规则；广告暂停不是 DIRECT。
- [Hako MRS reader](https://github.com/TokenPLS/Hako/blob/v1.19.30-hako.2/rules/provider/mrs_reader.go)：zstd → MRS v1 标识 → behavior → count → extra → body；domain=0，ipcidr=1。

公开客户端 main 的核对提交为 `b05832246fcac69d13ff16df871a8d53fd394c10`，核心参照标签 `v1.19.30-hako.2`。客户端没有可将 iOS 1.0.9 与某个源码提交一一对应的公开版本标签；project.yml 还有不同平台版本声明。因此不能宣称“官方 1.0.9 二进制源码精确匹配”或“真机导入已成功”。

## 本轮已执行检查

1. `node --check` JavaScript 语法通过。
2. 28 项隔离回归通过：输入不变性、幂等性、单节点、多地区、未知地区、机场更换、AI 无候选保护、名称边界、重复名、TLS 校验、链循环、DNS/TUN 悬空依赖、规则引用、策略组无环、1000 节点执行等。
3. 10 个远程 MRS 均 HTTP 200，zstd 解压成功，magic、behavior、非空计数与集合版本均正确。随后用官方 mihomo `convert-ruleset` 对全部 10 份文件完整解码成功；不是只验证扩展名或状态码。
4. 使用实际解码规则进行 10 个关键域名的本地路由夹具检查：Gemini、ChatGPT、Claude、YouTube、Googlevideo、YouTube API、微博、知乎、微信、百度，均符合预期。评估器只实现本生成器的相关规则子集，不是真实隧道流量。
5. Cloudflare 和 Google HTTPS `generate_204` 在审查电脑上均返回 204。没有验证手机节点到这些探针的通路。
6. 官方 **mihomo 1.19.31 Windows amd64** 对多地区、单节点、未知节点、1000 节点四份生成配置执行 `-t` 成功。为避免虚构节点被用于下载，测试时只将规则 Provider 从 HTTP 改成已下载的本地 file；组、规则、DNS/TUN 和节点结构不变。

官方校验工具来自 MetaCubeX/mihomo 发布页，ZIP SHA-256 与 GitHub Release API 的资产 digest 一致：

`d89c9bd746e8aacff89b2edf674813e25e8bd2dc565f4e12dc3b4526dd2b3177`

工具只用于 `-t` 与格式转换，不启动系统代理。下载工具和生成的虚构节点测试样本放在仓库外，不提交。

## 远程资源快照

规则集合在 2026-09-20 检查时共约 2.59 MB 压缩数据、4.83 MB 解压数据；**不等于 iOS 实际常驻内存**。上游更新后条目数可能变化。

| 规则 | 条目数 | 用途 |
| --- | ---: | --- |
| 217heidai/adblockmihomo | 211112 | 合并去重广告域名 |
| MetaCubeX cn 域名 | 111021 | 国内域名直连 |
| MetaCubeX cn IP | 9741 | 国内 IP 兜底 |
| YouTube | 178 | 视频业务 |
| OpenAI | 22 | ChatGPT / OpenAI |
| google-gemini | 41 | Gemini |
| anthropic | 8 | Claude |
| Google | 1071 | 其余 Google 服务 |
| Telegram 域名 | 21 | Telegram |
| Telegram IP | 12 | Telegram IP |

广告清单只接入一份，不叠加测试初期较小的 category-ads-all。保留微信、微博、知乎、APNs 的指定保护域，避免重现历史连通性故障。保护范围内的广告也会放行；这是已记录的取舍。

## 风险与验收边界

- 这是一份网络层分流/去广告配置，不是 YouTube protobuf/HTTP 改写模块，不能交付“视频广告彻底消失”、PiP 或上传按钮隐藏。
- 不改变 DNS/TUN，不代表已修复机场原有 DNS 或安全问题；外部控制器和共享设置仍应由用户关闭。脚本关闭 allow-lan、恢复节点证书校验，但不是完整的原配置安全清洗器。
- 名称识别地区不验证真实出口位置。AI 的 204 检测也不验证账号权限、地区限制、验证码或实际服务状态。
- 自动切换只影响新连接；既有 TCP/视频连接不能跨节点迁移。全节点坏、限速/丢包、Wi-Fi/蜂窝变化仍会影响播放。
- 首次远程规则下载、App 1.0.9 原生校验、真实机场、DNS 路径、内存/耗电、实际广告效果和持续播放仍需用户真机验收。

结论：仓库内可执行检查通过，可按授权发布供手机测试；不能把该结论扩展为真机运行与去广告效果已验证。

## 2026-09-21 发布前复检

用户要求继续后，重新运行全部 28 项离线测试、10 个远程规则下载/原生解码、10 个实际规则数据夹具、2 个 HTTPS 探针及 4 类内核语法检查，全部通过。广告清单已更新为 211208 条，说明其确为可变的上游订阅；上表保留 9 月 20 日快照。远程 main 仍为上述基线，发布范围仍只有本客户端四个新增文件。
