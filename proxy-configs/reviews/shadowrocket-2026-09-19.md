# Shadowrocket v2.6.17：第一批单客户端修复

基线：`8860378`（v2.6.16）。仅修改 `shadowrocket_V26.00.lsr`，附加本客户端测试和说明；不修改 QX、Loon、Egern、Stash 或公共脚本。用户已授权检查通过后发布到 main。

## 本批改动与边界

1. 微信：在广告表前增加 `dns.weixin.qq.com` 精确直连。旧 `.com.cn` 和 `teg` 保护不变，不把整个 `qq.com` 或 `weixin.qq.com` 前置放行。本次获取的广告域名表未发现 `dns.weixin.qq.com`，所以这是防御性补全，不宣称它就是手机转圈的已证实根因。
2. 微博：三个图片广告主机 `fastimage.uve.weibo.com`、`adimg.uve.weibo.com`、`adimg.vue.weibo.com` 均被现用 Advertising_Domain.list 收录，现改为保护区前的精确主机拒绝。来源收录不能替代真机无误伤测试；如普通图片异常，优先回滚这三条。删除五条原本被 weibo.com 直连遮蔽的旧拒绝；其中 biz/bootpreload/sdkapp 不激活整域拦截。保留 sdkapp/wbapp 直连供开屏响应脚本处理。
3. YouTube：六个现有 gstatic 探针改为 HTTPS；保留地区、顺序、120/60 秒间隔、容差、5 秒超时和嵌套结构。增加 TLS 握手验证/开销，但不测媒体吞吐，也不能保证播放无中断。三钩子仍固定 `65075cdb`，PiP/后台能力所用脚本、隐藏上传参数、Worker 路由、MITM 和 QUIC 规则逐行保持不变。未宣称修复了手机端残留广告。
4. IG/Twitter：三个“稳定地区池”从 url-test 改 fallback，300 秒检测、5 秒超时、HTTPS Cloudflare 探针。按订阅优先级选择可用节点，不再根据延迟排名选优；可能选到较慢节点，也可能在优先节点恢复后回切。检测更频繁，功耗需实测。其他通用地区池不变。
5. OneID/设备识别：保留 v2.6.16 兼容例外，但纠正“已证实必要依赖”的注释。是否删除要以 A/B 结果决定；本批未扩大放行。

## 验证

```powershell
pwsh -NoProfile -File proxy-configs/scripts/test-shadowrocket-known-fixes.ps1
pwsh -NoProfile -File proxy-configs/scripts/test-shadowrocket-audit-mutations.ps1
git diff --check
```

- 静态测试：72 个美国节点正则样本、既有 Gemini/AI/兼容规则、10 个微博域名路由样本、微信保护顺序、6 个 HTTPS 探针、3 个稳定池、YouTube 三钩子参数。
- 对不可变历史版本重建完整允许变更，确保其他有效配置行（包括 DNS、AI、YouTube 脚本、MITM、FINAL）未被悄悄修改。
- 10 个内存负向变异测试：探针、隐藏上传、微信、微博、稳定池、AI、DNS、MITM、脚本锁版本和 SDK 拒绝。
- 发布前在线检查：本配置有效行中 23 个唯一 GitHub raw 资源全部 HTTP 200 且非空；Google/Cloudflare 两个 HTTPS 探针均返回 204。测试来自本机网络，不代表手机节点已验证。
- 本地测试不是 Shadowrocket 原生配置解析器，不证明 iPhone 已下载/启用配置，也不验证节点可用性、真实地区、账号限制或广告清除效果。

## 手机验收与后续

1. 更新当前远程配置，查看文本头应为 `v2.6.17`；如 GitHub raw 缓存仍旧，稍后重新更新。不要删除订阅或重新安装 CA。
2. 确认启用的是此文件，路由模式为配置规则；检查外加模块没有重复接管 YouTube/微博。记录模块列表，不盲目删除。
3. 确认 YouTube 选择 `YT-Auto`，五个地区池实际有节点。客户端可能保留旧的手动选择，更新文件不保证重置选组。
4. 分开测试前贴/中插广告、PiP、后台播放、上传按钮；至少 30 个视频及 3 次 60 分钟连续播放。记录广告对应请求、脚本错误及版本，不把 MITM 标志当作去广告成功。
5. 微信/微博/知乎冷启动、消息、图片、视频和网络切换；IG/Twitter 检查较慢首选节点及恢复回切是否影响使用。
6. 所有节点失效、TLS 失败但 HTTP 可达、仅视频 CDN 异常分别测试。记录切换/恢复时间，不能用探针绿灯替代业务验收。
7. 若本批引入回归，在 GitHub 对本批提交执行 revert，再刷新配置；不要 hard reset。回滚基线为 `8860378`，不得覆盖后续无关提交。

未完成项：手机端 YouTube 广告/中断原因、AI 业务级健康检测与地区验证、兼容例外 A/B、安全资源预算与异常放行适配、客户端合并后模块审计。需证据后继续小火箭下一批；本批不声称整套需求已全部解决。其他客户端维持原样，待单独处理。

## 依据

- 广告表：https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/release/rule/Shadowrocket/Advertising/Advertising_Domain.list
- 微博脚本作者模块（SDK 接口应交给脚本）：https://raw.githubusercontent.com/zmqcherish/proxy-script/main/weibo.sgmodule
- YouTube 作者模块（三钩子与 MITM 依赖）：https://raw.githubusercontent.com/Maasea/sgmodule/master/YouTube.Enhance.sgmodule

这些来源可变；本批保留 YouTube 的既有提交锁定，不在缺乏兼容性测试时追随 master。
