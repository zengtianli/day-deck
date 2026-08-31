# day-deck · 复盘

`day.tianli.cyou` 的随身版。早上看今天要做什么，晚上看今天发生了什么，随手写日记。
**离线可读**（上次取到的那份一直在），**不主动打扰**（没有推送、没有通知、没有角标）。

三个 tab：**今天**（跨天未完成，逾期/今天/没定时间/之后，可标完成、可推进提醒事项）·
**复盘**（当天 LLM 一句话 + 几条线 + 完整时间线，可按天往回翻）· **日记**（写，落回 Mac 的 `notif.db`）。

内容与全部业务逻辑在 `~/Apps/cli/notifhub`，这里只是它的一个视图。约束与坑单见 `CLAUDE.md`。

```bash
bash sim-run.sh              # 模拟器
bash install-to-iphone.sh    # 真机（WiFi）
bash seed-gate.sh            # 闸密码喂一次
```
