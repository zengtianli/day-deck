# Notihub iOS · TestFlight 外部测试 · 2026-10-18

Chapter task `755ffd6eb22d4f908508c471cff5f506`；原 claims 身份 PID `35999` / session `chapter-task:755ffd6eb22d4f908508c471cff5f506`。本轮沿该身份逐次 check，不另开或释放声明。

授权范围：按 [Mac 批次 SOP 第 3–7 步](/Users/tianli/Apps/keyscope/handoffs/2026-10-18-app-review/testflight-mac-batch.md) 为本 App 的已有 iOS 包配置独立外部测试。仅写本 handoff 与 [同名证据目录](testflight-external-20261018/)，不改产品源码、正式商店审核对象或其他会话的改动、暂存、后台。

共享资源为本 App 的 ASC TestFlight 对象与本地 Git 索引；不构建、不上传、不装机、不占模拟器或测量资源。执行机为 Mini。完成条件为现有最新 VALID / 未过期 IOS build、独立外部组、三位指定测试员、Beta 联系资料、What to Test、自动通知及 Beta submission 均经官方 API 回读，正式审核对象前后一致，并完成限定路径本地提交。

## 固定对象与基线

- App：`6807048407`，`Notihub · 通知复盘`，bundle ID `cyou.tianli.daydeck`。
- 平台与包：`IOS`，`0.2.2 (9)`，build `72f350f5-d7c4-4427-9283-34ac9054a0b0`。
- 现有正式版本：`9cef653d-f6ed-4163-b70e-ec08130c8599`，`PREPARE_FOR_SUBMISSION`，正式 review submissions 为空。
- 开始时源码 HEAD：`9cc4ad78395144cdfb74bfe8af341ee9e91dc2bf`。包的归档来源与既有源码对应证明沿用 [上一轮回读](../docs/testflight-20261017.md)；本轮没有重新声明产品功能或性能验收通过。
- 官方 API 完整分页查询现有 IOS build，数值比较 build 号并核过期日期，选中 9；不重传。详见 [plan.json](testflight-external-20261018/plan.json)。

## 第 3–7 步回执

所有请求、写入意图、SDK 成功响应、逐次 GET 回读与 UTC 时间见 [receipts.json](testflight-external-20261018/receipts.json)。唯一 SDK 为 `/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/asc.py`，解释器为 `/Users/tianli/Dev/.venv/bin/python`，沿原凭据加载；[本轮脚本](testflight-external-20261018/asc_external.py) 的写接口白名单仅包含 TestFlight 资源。

1. **独立外部组（第 3 步）**：创建 `Notihub iOS External Beta`，ID `b0381543-cf63-4380-b2e9-b4689844fd55`，`isInternalGroup=false`、公开链接关闭。原 `family` 为内部组，不改其成员、权限或构建。逐邮箱查询同时限定 `filter[apps]=6807048407`，复用本 App tester 或通过组关系创建；只加入 `zengtianli1@126.com`、`zengtianli2@126.com`、`zengtianli3@126.com`，未新增 ASC 团队角色。
2. **Beta 资料（第 4 步）**：正式审核详情 ID `7cf6be46-35ef-4076-a83e-6b98e9c3a0ca` 的四项联系人字段逐字复制至 Beta 详情 `6807048407`，PATCH 返回 200，并立即 GET 验证。该 App 的 `demoAccountRequired=true`，沿用已有隔离合成数据演示账号与原 Review Notes，一并精确回读；没有照搬 Mac 无账号产品的 false。凭据、Notes 和联系电话原文不写入本地回执，只留长度、SHA256 与一致性断言。中文 Beta 描述和隐私链接取自现有正式资料，反馈邮箱沿用正式联系人。
3. **What to Test（第 4 步）**：写入 `betaBuildLocalizations.whatsNew`，locale `zh-Hans`，ID `b6f54a43-e047-40ba-a571-910bfec869b5`。内容覆盖连接、今天待办搜索/详情/状态/本机提醒事项、通知日期与长正文、随手记保存回读、离线草稿与恢复、iPad 布局、配置同步及适用手表摘要；请反馈无法完成的操作、错误和易用性问题，并提供设备与复现步骤。完整原文保存在回执和最终回读。
4. **构建与 Beta 提交（第 5 步）**：`autoNotifyEnabled=true` 原本已开启，保留并逐字回读，没有多余 PATCH。组的构建关系 POST 返回 204，GET 确认含 build 9。提交前再次查询该 build 的 `betaAppReviewSubmissions` 仍为空，才创建一次；Beta submission ID `72f350f5-d7c4-4427-9283-34ac9054a0b0`，上海时间 **2026-10-18 14:47:41** 提交。最终 `betaReviewState=WAITING_FOR_REVIEW`、`externalBuildState=WAITING_FOR_BETA_REVIEW`，并非已批准。
5. **邀请与可用性（第 6 步）**：三位 tester 均已通过该组 GET 回读，状态见下表。邮箱 1 的 `INSTALLED` 是本 App 已有测试者记录，不证明本轮安装或已安装 build 9；邮箱 2、3 为 `NOT_INVITED`，未声称邀请已发送、邮件已送达或已安装。外部包等待 Beta 审核，自动通知已开启；本轮没有对不可安装条件反复发送邀请。
6. **最终核验（第 7 步）**：14:48:15（上海时间）完整回读通过，见 [final.json](testflight-external-20261018/final.json)。[正式对象前](testflight-external-20261018/formal-before.json)与[正式对象后](testflight-external-20261018/formal-after.json)完全一致，覆盖正式 versions、review submissions、build 关系、审核详情和正式本地化。仅 Beta 对象变化，没有正式送审、重提或回复。

| 邮箱 | 本 App tester ID | 回读状态 |
| --- | --- | --- |
| zengtianli1@126.com | `d5d6f520-53cf-4152-8dd2-22b24c6d3415` | INSTALLED（既有记录） |
| zengtianli2@126.com | `37b59ba1-1de2-4445-a683-6bdcc9b0f300` | NOT_INVITED |
| zengtianli3@126.com | `7c729e0d-576a-44a4-8cf8-ce2448cdd43e` | NOT_INVITED |

随后以另一段只读代码重新查询 build、IOS release、外部组、组内构建、三位成员、自动通知、Beta submission、正式/Beta 联系资料及 What to Test，见 [独立回读](testflight-external-20261018/verification.json)。同时核验回执不含演示账号、密码和联系电话原文。证据文件 SHA256 见 [manifest.json](testflight-external-20261018/manifest.json)。

## 接续与提交边界

本轮不调用任何正式 submit / resubmit / review reply 接口，不上传、不升号，不重做全量 SOP 或本地产品测试。本任务只有 ASC 元数据操作，没有装机声明。

仅本地提交，不执行 git push。提交时使用原 post-commit 工具支持的 `GIT_FOLLOW_LOCAL_ONLY=1`，保留凭据扫描和其他原 hooks，同时阻止双机 follower 间接推送。`handoffs/` 原被 `.gitignore` 排除；按本轮明确的提交授权，只对上述交接与证据文件执行精确路径 `git add -f`，不修改忽略规则。

Chapter 在本轮结束后负责按仓库可见性与授权处理推送；推送前必须运行 `chapter xcode-cloud status --repo . --json` 并检查 `push_allowed`、原 pre-push hook，推后核 ls-remote 与 `git rev-list '@{u}..HEAD'`。本轮没有推送动作，因此未推送不记 blocked。

本轮完成谓词已满足，等待 Apple Beta 审核记为后续状态，不记任务 blocked。下一次只读接续可在本仓执行：`/Users/tianli/Dev/.venv/bin/python /Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/asc.py builds cyou.tianli.daydeck --platform ios`；精确 Beta 状态沿原 SDK `asc.get('/betaAppReviewSubmissions', {'filter[build]': '72f350f5-d7c4-4427-9283-34ac9054a0b0'})`。批准后先查该组三位 tester 状态，仅补仍缺失的通知，不重复创建 submission、不重传。

Apple 的[外部测试说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)说明了外部 Beta 审核与自动通知的接续；上传 VALID、组成员关系和外部批准分别记录。
