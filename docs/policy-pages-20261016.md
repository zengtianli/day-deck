# Notihub 隐私与支持页面发布记录

本轮仅维护以下公开页面，沿 Chapter 转交 Lintel 的原计划、离屏检查、发布器和 HTTPS 回读流程。

- 隐私政策：https://app-ios-day-deck.tianli.cyou/privacy.html
- 支持：https://app-ios-day-deck.tianli.cyou/support.html

Chapter 的产品部署授权闸门已修复，本次执行正常放行；Lintel 的实际产品为 `notifhub-bar-mac`，包含 `day-deck-ios` 附属页面。站点汇总中的其他产品回执未用作本产品证据。

首次检查时两个地址均返回 404。原页面离屏验收随后发现支持页在 390px 窄屏横向溢出，发布在传输前停止。原因是 FAQ 直接显示完整源码地址；共享原生成器已将该项改为指向同一地址的“查看源码与许可”链接，保留原公开范围和全部说明文字。

必要共享修复位于 Apps Portal 的 `render_support`，提交 `24172a93844a25d8825367e34f6c9720dcc9cbb4`；定向测试 16 项与 8 个子测试通过。产品页面沿 `chapter promo build` 重新生成，没有手改产物或降低页面检查要求。

修后页面的构建 SHA256：

| 页面 | SHA256 |
| --- | --- |
| privacy.html | `3fa342d61b85a46f99c8399a08beecf6ad93c5138789f75099bfc7c43a67c0b2` |
| support.html | `1ec484ab94debe77880b69e38ee8d28af23cb27dca874d44527eab63449c567a` |

修后 Lintel 的 6 页桌面/窄屏视觉检查、1 条适用视频播放及警告检查均通过，支持页在 390px 下 `overflow=false`。随后进入原发布器。

2026-10-16 22:33 的匿名 HTTPS GET 回读：

| 页面 | HTTP | 正文 SHA256 |
| --- | --- | --- |
| privacy.html | 200 | `f851529af0f47f520c5a76f320b36b3e56938d3c3ce76f765fcda2d26197f85d` |
| support.html | 200 | `b662bc1a67a65f3b035ea40bbfd47e3df332bbc37df11c526ddf14cc5c4dbf21` |

两次请求均未携带 Cookie 或 Authorization，最终地址保持原 HTTPS URL。标题、隐私数据/删除/联系说明和支持 FAQ/源码链接均与计划一致；源文件与线上字节的唯一差异为 Cloudflare 移除 `email_off` 注释标记，由 Lintel 原比对器核实。

最终原回执已返回：`published=true`、`origin_verified=true`，实际产品为 `notifhub-bar-mac`；隐私页与支持页在 Lintel 自己的 HTTPS 回读中也均通过，SHA 与上述独立匿名请求相同。执行主体为 agent，未登记为本人视觉确认。

整份计划仍为 `verified=false`，命令退出 1，停在 HTTPS 回读：

- `products/mac/notihub/assets/ios/day-deck-ios/03.jpg`：连接中断，curl 在 30 秒内只收到 9565 / 20864 字节。
- `products/mac/notihub/assets/mac/notifhub-bar-mac/demo.mp4`：响应不完整，curl 在 30 秒内只收到 123706 / 268994 字节。

这两项保留为公网传输未完整读取；没有据此认定原素材损坏，也没有重录、修改或重传它们。两份政策页面可匿名读取与整计划未全通过分别报告，不将本次 `ship` 写成整体成功；网络未改变时不再次执行发布。

完整本地原件保存在 `build/release-policy-publish-20261016/`：首次失败与修后执行分别保留，最终原结果为 `fixed-ship-result.json`，匿名响应头、正文和 SHA 记录位于 `anonymous-readback/`。Lintel 当前 CLI 未提供只读、单项续验 HTTPS 的命令，后续由 Lintel 在网络恢复后接续原回读能力，不扩大本轮页面范围。
