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

此时原发布流程的最终回执仍待收取，尚未据此宣告整体发布完成。完整本地原件保存在 `build/release-policy-publish-20261016/`，首次失败与修后执行分别保留，匿名响应头、正文和 SHA 记录位于其中 `anonymous-readback/`。
