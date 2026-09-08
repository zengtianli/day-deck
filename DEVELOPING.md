# day-deck · 复盘

`day.tianli.cyou` 的随身版。早上看今天要做什么，晚上看今天发生了什么，随手写日记。
**离线可读**（上次取到的那份一直在），**不主动打扰**（没有推送、没有通知、没有角标）。

四个 tab：**今天**（待办状态直接保存云端）· **复盘**（按日摘要和完整时间线）·
**日记**（直接保存云端，未提交草稿保留）· **连接**（访问闸登录，凭证存钥匙串）。

客户端通过 HTTPS `/api/index`、`/api/open`、`/api/day/{date}` 读取服务。
日记 POST `/api/notes` 使用幂等键；待办 PATCH `/api/agenda/{id}` 验证回执后显示成功。
只有导出 Apple 提醒事项仍交给桌面端队列。离线显示上次成功内容、时间和错误。
单日页面缓存 60 秒，切换日期只请求当天；强制刷新淘汰旧请求，长正文按需展开。

`swift test` 验证实际生产核心的云端契约、缓存、请求竞争和时区；
`bash build-platforms.sh` 构建 iPhone、iPad、Mac。交付还须实际打开各平台，验证读取、保存回读和失败恢复。

```bash
bash sim-run.sh              # 模拟器
bash install-to-iphone.sh    # 真机（WiFi）
bash seed-gate.sh            # 闸密码喂一次
```
