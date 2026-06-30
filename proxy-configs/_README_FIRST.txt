本压缩包用途:交给 Claude Code 做四份 iOS 代理配置的差异化优化。

⚠️ 安全说明(重要)
- Loon 与 Quantumult X 配置中的 3 个机场订阅 token 已被替换为占位符
  (YOUR_AIRPORT* / __REDACTED__),以便安全地 git init / 交给工具。
- 这些是脱敏副本,不能直接导入 App 使用。要真正使用时,在各 App 内
  重新填入你自己的订阅链接(且建议先去机场面板"重置订阅"作废旧 token)。
- Egern 中的 NextDNS profile ID (f3af17) 保留原样:它不暴露节点、风险低。
  如需一并脱敏,可手动把它也换成占位符。

使用步骤
1. 解压到一个文件夹。
2. (可选但建议)git init —— 因 token 已脱敏,可安全提交。
3. 在该目录运行 claude,首句:"读 CLAUDE.md,先只读审查、出改动清单,先别改。"

文件清单
- CLAUDE.md                  项目规则(安全基线 / 各 App 分工 / 禁止项)
- shadowrocket_v2_6_11.lsr   Shadowrocket(原文件,无 token)
- quantumult_B_v5_1.6        Quantumult X(token 已脱敏)
- Egern_Pro_v6_5_0.yml       Egern(NextDNS ID 保留)
- Loon_v2.2                  Loon(token 已脱敏)
