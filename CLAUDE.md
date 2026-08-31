# CLAUDE.md · day-deck（复盘）

> iOS 客户端。父级形态规则 `~/Apps/ios/CLAUDE.md`，建 app 的通用坑单 `/appios`，
> 全局偏好 `~/.claude/CLAUDE.md`。**服务端与全部业务逻辑在 `~/Apps/cli/notifhub`。**

## 这个 app 回答两个问题

| | 什么时候 | 页 |
|---|---|---|
| 我今天要做什么 | 早上 | 今天（跨天未完成，逾期/今天/没定时间/之后） |
| 今天发生了什么 | 晚上 | 复盘（LLM headline + 几条线 + 时间线，可往回翻） |
| 我怎么想的 | 随时 | 日记（写，落回 Mac 的 `notif.db`） |

## 硬约束（违反其一，这个 app 就变成第二个账本了）

| 约束 | 为什么 |
|---|---|
| **一条业务规则都不在这里** | 合并去噪、时间节点抽取、LLM 总结、幂等键全在 notifhub。这边重写一份 = 两边说不同的话，而且不报错 |
| **不解析 HTML** | day 站那份 HTML 是给人看的，排版随时改。解析它的客户端会在某次纯样式改动后**静默显示错的东西** |
| **不主动打扰** | 继承 notifhub 的红线（2026-08-13 用户钦定「我主要是为了复盘，不用提醒我」）。没有推送、没有本地通知、没有角标 |
| **数据不进 bundle** | 内容是微信原文/诉讼/贷款/联系人。打进包 = 交给 Apple。一律运行时取 |
| **写只下单，不直接改库** | 提醒事项授权、`notif.db`、notifhub 二进制全在 Mac 上。手机 POST 一张单，Mac 领单执行 |
| **陈旧度一直显示** | 离线可读的代价是可能看到旧数据。不显示时间戳的话，飞行模式下看到的昨天会被当成今天 |
| **亮色** | 早晚各看一次，内容全是长文本；深色底在户外强光下更难读 |

## 数据怎么来的

```
Mac: notifhub daemon(kqueue 常驻) → notif.db
     notifhub publish            → HTML + JSON(index/<date>/open.json) --rsync--> /var/www/day
VPS: nginx(authgate 闸) 罩住整站,包括这些 JSON
iOS: 本 app 拿闸密码换会话 → 取 JSON → 落盘缓存 → 渲染
```

**JSON 的 SSOT 是 `~/Apps/cli/notifhub/Sources/notifhub/JSONFeed.swift`**，
`Sources/Models.swift` 是它的读取形状。改字段两边一起改 —— 只改一边会解码失败，
而 `API.decode` 会点名是哪个字段，不会静默容错。

`open.json` **查全库不是发布窗口**：保留窗口之外的旧待办同样得做，
漏了的表现是「app 里那条待办凭空消失」。

## 写回去那条链

```
手机 POST day.tianli.cyou/api/agenda-queue   {kind:"note"|"status"|"push", ...}
  → nginx 转 VPS 本机 Next /api/admin/agenda-queue（写 JSON 队列到 /root）
  → Mac 上 notifhub 每分钟 `queue` 领单 → note / done / drop / push → 回写状态
```

三条不能省的判据（都在 notifhub 侧，`AgendaQueue.swift`，selftest 有反向验证过的用例）：

- **退出码不够用**：`done` 对不存在的 id 打一行「#N 不存在」然后 **rc=0**。
  只看 rc 会把它记成成功，app 上显示已标掉而库里那条还开着。
- **老单没有 `kind` 字段**：当成必填的话，队列里存量单子整批读不出来，
  表现是「排了队却没人跑」。缺省补成 `push`。
- **push 一律带 `force`**：不带的话 notifhub 走「已推过，跳过」分支且 rc=0，
  队列回写 done、界面显示成功，而提醒事项里一条没多。

界面上一律说**「已排队」不说「已完成」**——中间隔着 Mac 醒没醒。

## 跑起来

```bash
bash sim-run.sh              # 模拟器（总部 SSOT 的 shim）
bash install-to-iphone.sh    # 真机（默认走 WiFi）
bash seed-gate.sh            # 把闸密码喂进手机一次（之后存 iOS 钥匙串，不用再喂）
~/Dev/.venv/bin/python make_icon.py   # 重生图标（逐像素可复现）
```

### 验证通道（launch 参数，生产路径上永远是 nil）

```bash
U=$(xcrun simctl list devices booted --json | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print([x["udid"] for v in d.values() for x in v if x["state"]=="Booted"][0])')
xcrun simctl launch $U cyou.tianli.daydeck \
  -gatepw "$(security find-generic-password -s tlz-gate -w)" \   # 模拟器上喂闸密码
  -tab 1                                                          # 0 今天 / 1 复盘 / 2 日记
```

**闸密码源是 macOS 钥匙串，不是 `~/.personal_env`** —— 2026-08-28 实测 `XCBuildData`
会把构建时的完整环境**连值一起**记进中间产物。凭证进环境变量 = 跟着构建产物散出去。

## 结构

| 文件 | 干什么 |
|---|---|
| `Sources/Gate.swift` | authgate 客户端（从 options-desk 移植，只改 Keychain service 标识） |
| `Sources/API.swift` | **取数唯一通路** + `FeedError`（四档，每档带 `whatToDo`）+ 落盘缓存 |
| `Sources/Models.swift` | JSONFeed 的读取形状 |
| `Sources/Store.swift` | 三份数据各自独立刷新 + 逾期/今天/没定时间/之后的分组 |
| `Sources/TodayView.swift` | 今天 + 待办详情（三个动作：完成/不做了/推提醒事项） |
| `Sources/RecapView.swift` | 复盘 + 日期切换 + 时间线 |
| `Sources/DiaryView.swift` | 日记 + `Writer`（三种单的下单口） |
| `Sources/MarkdownView.swift` | 从 blog-reader 逐字移植，**这里不改**（改了两边会漂） |

## 踩出来的坑

**① 撞闸的判据是最终 URL 落在 `/_gate/` 下，不是状态码。**
URLSession 会跟着 302，到手的是登录页的 **200 HTML**，状态码分辨不出来；
嗅 HTML 内容则是给页面文案建第二份判据，改个字就瞎。`FeedError` 为此单列 `.gate` 一档 ——
混进 `.decoding` 会显示成「数据对不上契约」，把人引向服务端去查。

**② 复盘页的上一天/下一天只在有数据的日期之间走。**
按自然日 ±1 会走进一堆 404 空页，而「那天没事」和「那天根本没发布」在界面上必须分得开。

**③ 解码失败不覆盖缓存。** 拿一份坏数据换掉能用的旧数据是净损失。

## 相关

- 服务端 / 全部业务逻辑：`~/Apps/cli/notifhub`（`JSONFeed.swift` `AgendaQueue.swift`）
- 队列端点：`~/Dev/stations/website/app/api/admin/agenda-queue/route.ts`
- vhost：`~/Apps/cli/notifhub/nginx/day.tianli.cyou.conf`
- 姊妹 app：`~/Apps/ios/options-desk`（同一套 Gate + 同一道闸）
