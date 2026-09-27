# Notihub · iPhone / iPad 开发

`day.tianli.cyou` 的随身版。早上看今天要做什么，晚上看今天发生了什么，随手写日记。
**离线可读**（上次取到的那份一直在），**不主动打扰**（没有推送、没有通知、没有角标）。

四个 tab：**今天**（待办状态直接保存云端）· **通知**（按日摘要和完整时间线）·
**随手记**（直接保存云端，未提交草稿保留）· **连接**（访问闸登录，凭证存钥匙串）。

客户端通过 HTTPS `/api/index`、`/api/open`、`/api/day/{date}` 读取服务。
日记 POST `/api/notes` 使用幂等键；待办 PATCH `/api/agenda/{id}` 验证回执后显示成功。
只有导出 Apple 提醒事项仍交给桌面端队列。离线显示上次成功内容、时间和错误。
单日页面缓存 60 秒，切换日期只请求当天；强制刷新淘汰旧请求，长正文按需展开。

`swift test` 验证实际生产核心的云端契约、缓存、请求竞争和时区；
`bash build-platforms.sh --only iphone,ipad --release` 只构建 iPhone、iPad，不安装；Mac 由 Notihub Mac 独立承担。交付还须在获准的设备环境验证界面和云端读写。

## 固定验收

从本仓库运行，三个脚本均调用实际生产 API、Store、Writer、Gate，在合成网络响应和独立临时缓存下执行；不访问真实服务或钥匙串，不安装、不打开界面。它们证明本机生产核心集成行为，不代表 iOS 界面、真实设备或线上全链通过。

```bash
~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app day-deck-ios --check functionality --check recovery --check privacy --json
xcrun swift test -j 2
python3 -m unittest test_check_markdown_drift
bash check-markdown-drift.sh
```

Chapter 的 `sop.accept` 分别登记 `bash scripts/accept/functionality.sh`、`bash scripts/accept/recovery.sh`、`bash scripts/accept/privacy.sh`。`perf/delivery-evidence.json` 由 Chapter 生成，不能手填。没有 Chapter 时可以直接执行三个脚本；零测试匹配会返回失败。

DEBUG `-demo 1` 只读合成内容，API 和登录入口拒绝联网，写入会显示「演示模式只读」。Release 不包含该开关或演示数据。使用步骤见 [教程](docs/usage-guide.md)，录制前置条件见 [录制说明](docs/demo-recording.md)。

## 装机入口

以下操作会安装或操作设备，只在另行获准后执行：

```bash
bash sim-run.sh              # 模拟器
bash install-to-iphone.sh    # 真机（WiFi）
bash seed-gate.sh            # 闸密码喂一次
```
