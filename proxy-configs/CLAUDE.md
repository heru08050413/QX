# 项目:iOS 代理配置维护(四 App 差异化)

本仓库维护四份 iOS 代理 App 配置。目标优先级:**安全 > 稳定性 > 去广告 > 低功耗**。
策略不是合并成一套,而是**安全层求同、能力层存异**——每个 App 发挥自身独有架构能力。

文件:
- `shadowrocket_v2_6_11.lsr` — Shadowrocket
- `quantumult_B_v5_1.6` — Quantumult X
- `Egern_Pro_v6_5_0.yml` — Egern(YAML)
- `Loon_v2.2` — Loon

---

## 一、安全基线(四套必须逐字一致,改任何一个都要对齐另外三个)

1. **MITM 排除清单**:银行/支付/登录/账户子域必须全部排除(`*.alipay.com`、`*.unionpay.com`、`*.cmbchina.com`、`*.icbc.com.cn`、`passport.*`、`account.*`、`pay.*`、`*.icloud.com` 等)。少一个 = 一个高敏感解密缺口。
2. **保护区顺序**:微博/新浪、微信(`*.qq.com.cn`、`teg.tencent-cloud.net`)、字节系的 `DIRECT` 规则必须排在广告 `REJECT` 段**之前**。
3. **熔断**:高频重试源用 `REJECT-DROP`(静默丢包),不是 `REJECT`。
4. **配置文件绝不内嵌订阅 token**(见禁止项)。
5. **Final 默认 `DIRECT`**。

> 改动前后都跑一遍这 5 条。这一层不参与差异化。

---

## 二、各 App 定制方向(放大独特能力,不要互相抄)

### Shadowrocket —— 低功耗 + 极致稳定的日用机
- **发挥**:`[Host]` 段 per-domain DNS 解析器路由(`域名 = server:DoH`);最省电、最成熟。
- **做**:坚持降耗(MITM 最小化、测速 interval 900s、`googlevideo` 移出 MITM);去广告保持"网络层 REJECT + 少量脚本"的中等强度。
- **别勉强**:不支持 Fake-IP(架构限制),DNS 是全局单池;不要往重脚本/最大化去广告方向推。

### Quantumult X —— 自动化 / 脚本 / 任务中枢
- **发挥**:`[task_local]` 的 **cron 定时任务**(四个里唯一强项);rewrite 引擎 + BoxJS。
- **做**:把签到/周期检查/Cookie 捕获/复杂 rewrite 集中到这里。**当前 `[task_local]` 全是手动触发的 `event-interaction`,没用上 cron——这是该补的地方。**
- **别勉强**:策略组 failover 模型弱(`static` 是手动选择不是自动故障转移),关键 failover 别压这里;无 Fake-IP,未显式钉境外 DoH 的长尾境外站会泄露给国内 DNS。

### Egern —— 精密路由 / 规则引擎的权威源
- **发挥**:逻辑 `and/or/not` 规则、`url_regex`、用 `proxy_rule_set` 当 DNS 分流条件、YAML 可 diff。
- **做**:在这里**编写和验证最精细的路由逻辑**,验证通过再把简化版移植到其他三个;去广告模块**去重**(保 `blockAds` + B站 `BiliUniverse` + 微博 `zmqcherish`,关掉重叠的 `Daily`/`NobyDa` 冗余)。
- **别勉强**:v6.5 的 **TUN + 境外 NextDNS 不是默认选项**——它把 DNS 稳定性绑定到节点稳定性、且更耗电(配置自己标注了)。"放大 Egern" 指放大它的规则/DNS 引擎,**不等于必须开 TUN**。若稳定性优先,可在非 TUN 模式跑它更强的规则引擎。

### Loon —— Fake-IP 防泄漏的干净 DNS 日用机
- **发挥**:**Fake-IP**(SR 做不到)、`hijack-dns`、原生 `fallback`。
- **做**:国内域名走国内 DoH(就近 CDN),境外走 Fake-IP→代理节点出口解析(天然防污染、零泄露、不等 1.1.1.1);维护好 `real-ip` 排除表(部分游戏/直连 IP 服务需要)。
- **注意**:正因为有 Fake-IP,Loon 的"国内 DoH 优先"是合理的,不属于泄露问题。
- **别勉强**:`[Host]` 只能做 IP 映射,**不能**复刻 SR 的 per-domain DNS 路由写法。

---

## 三、禁止项(硬约束,任何改动不得违反)

- ❌ **不得在任何配置文件写入真实订阅 token**。已有的(Loon `[Remote Proxy]`、QX `[server_remote]`)用占位符替代,如 `https://YOUR_AIRPORT/subscribe?token=__REDACTED__`。
- ❌ **不得把含 token 的文件提交到 git 或推到任何远程**。`git init` 之前先 scrub;token 会进 git 历史,删了也留痕。
- ❌ **不得降低证书校验**:`skip-cert-verify` / `skip_validating_cert` 保持 `false`(Loon 节点上的 `skip-cert-verify=true` 待修)。
- ❌ **不要尝试改 MITM CA 口令或重新生成证书**——只能在各 App 内手动操作,配置文件无法自动化。Egern 的 `ca_passphrase: egern` 是默认弱口令,在说明里提示用户去 App 改,但不要在文件里硬写新口令。
- ✅ 改远程规则源时,bm7 系把 URL 里 `/master/` 改 `/release/`(人工发布,降静默失效)。
- ✅ 每次改动走 git commit,保证可回滚、可 diff review。

---

## 四、Claude Code 在本任务里**做不到**的事(交还给用户)

- 真机测试、观察 iPhone 上的实际去广告/连通效果。
- 重新生成或安装 MITM 根证书。
- 验证机场节点本身是否可用(token 已脱敏,且需真实订阅)。
- 离线环境下验证远程规则集 URL 是否仍返回 200。

这些请在结论里明确标注为"需用户手动验证",不要假装已完成。

---

## 五、工作方式

- 先**只读审查 + 出改动清单**,等确认后再逐文件修改。一次改一个 App,不要四个一起动。
- Egern 是 YAML,可做语法校验(`yq`/`python -c 'import yaml'`)后再保存。
- 每个改动在说明里写清:动了什么、为什么、影响哪三维(安全/稳定/功耗)、是否需要用户手动跟进。
