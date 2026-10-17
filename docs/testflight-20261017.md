# Notihub iOS · TestFlight 回读 · 2026-10-17

本轮按“仅 TestFlight，已有当前源码的 VALID 构建就结束”执行。结果：复用现有 0.2.2（9），无需升号、归档或上传。

- ASC App：6807048407，bundle ID：cyou.tianli.daydeck，平台：IOS。
- 精确 build：72f350f5-d7c4-4427-9283-34ac9054a0b0；官方构建列表及 Chapter 均回读 VALID、未过期。
- 归档来源：ba105a6e5e5ff168d231c765e986a475f20d267f；回读时 HEAD：041584e5774263a89970c5f08dbb9314d4d61b6c。
- 当前56个受版本管理的编译输入与归档源码清单、原隔离源码 SHA 逐项一致；两个 XcodeGen 生成 Info.plist 也一致。
- 额外 Resources/icon-src.png 未被原生成工程引用；HEAD 相比归档提交只多发行文档及发行事实记录，不改变安装包源码。
- 商店版本仍 PREPARE_FOR_SUBMISSION，submission=null；本轮未提交审核、未装机、未改商店材料、未推送。

回执完成时间：2026-10-17 21:59:58 +08:00。本轮只读原件保留在仓内忽略目录 build/testflight-20261017-eeeb0673/，不改写 app_sop 固定验收证据：

| 原件 | SHA256 |
| --- | --- |
| chapter-store-status.stdout.json | 51964297c5cd9b8f3645d06075b2e9cfef6a5905433e4d4424a1503705ef7a56 |
| asc-builds.json | 3b475f008c196fee7b26f32efad1762fe82c84df93ee800c36b46cd7ad9d0187 |
| asc-exact-build.json | c9a6cb8637cea771f5dc37cbdfa06816609cfe598ac57e1fbc08eb8e580c633e |
| source-readback.json | e759508470c56f7484495ce8ace98702bca89547fcccfe5af3577deb96642232 |

本轮不扩大到手机装机、商店审核或其他产品缺项；当前 TestFlight 目标已完成。
