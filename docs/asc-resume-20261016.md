# Notihub iOS 审核准备接续

记录时间：2026-10-17，接续2026-10-16的同一次授权；不是新增发版或再次递增版本。

## 已实际完成

- 官方分页回读：ASC App 6807048407仍为iOS 1.0/PREPARE_FOR_SUBMISSION，reviewSubmissions为空；准备源码为0.2.2（9），上传列表尚无build9，未重复归档或上传。
- 原商店文字入口先只读确认上次超时写入的结果，再补实际缺项；名称、副标题、说明、关键词、版权、分类、隐私及支持URL共8项逐字回读一致；没有改年龄声明、构建关联或审核账号。
- 本产品自身的隐私标签已在ASC网页显示Published：Other User Content，仅用于App Functionality、关联使用者、不用于跟踪；没有复制其他产品的答案。
- 隐私和支持页分别为 https://app-ios-day-deck.tianli.cyou/privacy.html 与 https://app-ios-day-deck.tianli.cyou/support.html；直接匿名HTTPS完整读取均200，正文SHA与此前真实发布原件一致，没有重新发布或更改代理配置。
- 九问按真实测试状态更新，Review Notes为3720字符，官方逐字匹配，SHA256为11179c0c5d57ff983f1e8d8ec5996a19f1331e1ff125ed46ca9271f345402804；ASC专用账号和密码与受保护配置匹配，未写入源码、Notes或日志。
- 原生审核自检增加脱敏登录阶段诊断、真实启动PID一致性与失败原件保全，移除新建隔离设备上的多余终止参数；开机/安装后再次调用共享sim_lane原安静门，繁忙返回75，不把系统启动超时当通过。

隐私类别依据客户端实际写回的自由文本与待办状态；没有上传本机提醒事项、通讯录、搜索或缓存，也没有广告/第三方分析SDK；Apple自身处理与开发者收集分别判断，参见[Apple隐私说明](https://developer.apple.com/app-store/app-privacy-details/)。这些事实不代表额外开放注册或改变公开范围。

## 仍未完成

21:38的真实App设置验收已有54项通过，隔离配置往返不等于Apple跨设备iCloud传输；新增DEBUG诊断之后的固定复核因其他编译返回75，旧通过原件保留。原生审核自检仍有真实的simctl启动60秒超时，尚无当前通过原件；未原样循环。截图固定入口在开机后的CPU空闲仅1%时返回75，未覆盖旧素材；ASC截图集仍为空，不能说截图COMPLETE。

新的普通Debug候选已由sim_lane构建并严格核对59个当前输入文件，源码摘要48dc164957c5790d195cee5d638f28b6e0ba63a2e3881d64c9a9cb9c55fa4d65；它是模拟器候选，不是正式Store归档或已装手机版。本轮没有归档、上传、手机安装或提交审核；只有官方原version/submission出现WAITING_FOR_REVIEW或IN_REVIEW才能记已送审。

## 原入口接续

设置与原生验收已排回原Chapter队列；`chapter jobs --app day-deck-ios --active --json`读取状态，`chapter work --until-idle --app day-deck-ios --json`只接续本产品原单，锁忙75保留next_attempt_at，不另起队列。

商店文字与URL只读回查：`~/Dev/.venv/bin/python scripts/release/store_metadata.py --urls`；Notes只读回查：`~/Dev/.venv/bin/python scripts/release/review_notes.py`。素材继续使用scripts/media/store_shots.py及其候选--reuse-build入口，源码/二进制必须严格匹配，输出不可冒充正式归档验收。

固定检查、真实审核流程和截图COMPLETE闭合后，再按原push-testflight.sh的prepare-only/upload-prepared两阶段执行，复用已准备归档并回读VALID与真实version关联；随后运行Chapter store原提交入口并回读审核状态，不能把排队或上传等同已送审。

账号交接中的开发者许可与Free Apps Agreement已解阻，新的Paid Apps Agreement仍由Chapter原账号任务处理；本轮未观察到它阻断本产品API，未代签或重复要求本人确认。推送预检分页列出全部5个Xcode Cloud产品，无本App；本仓无GitHub workflows或ci_scripts，pre-push仅Git LFS，未启用任何自动触发。

本机原件在build/asc-resume-20261016/，真实验收原件由app_sop保存在perf/acceptance/；发布与送审结果分别记录，未手写delivery-evidence。
