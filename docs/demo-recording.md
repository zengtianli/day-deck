# Notihub iOS 公开演示录制交接

状态：本轮未录制视频。现场没有开机模拟器，空闲门未通过（负载 95.6 ≥ 10）；本轮亦禁止装机、部署和干扰用户输入。以下是本人接手后的命令与分段脚本，不是已完成的视频证据。

## 录制边界

公开演示只使用 `Debug` 构建的 `-demo 1` 合成数据，且必须在新建专用模拟器中进行，避免现有草稿、钥匙串或缓存入镜。Release 不包含演示数据。使用教程见 [使用教程](usage-guide.md)。

本轮已补齐 `-demo 1` 的 API 和登录拦截：保存笔记、标完成、推提醒返回「演示模式只读」，连接按钮拒绝联网；固定 privacy 脚本验证了请求数为零。公开录制仍只展示只读界面、搜索和详情，不输入真实密码。昨天虽列入演示日期索引，尚未提供演示日内容，本版不要把切换昨天作为演示片段。保存和恢复闭环由固定核心验收证明，不能把只读演示说成保存实录。

## 本人接手：先准备专用模拟器

以下命令将新建模拟器并安装本地 Debug 包，仅在本人决定恢复录制后执行；本轮未执行。先等待机器空闲，再从仓库目录运行。`sim-run.sh --shutdown` 复用共享构建与安装入口，完成后自动关机，不打开 Simulator 窗口。

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use iphonesimulator
DEMO_SIM_NAME="Notihub Public Demo iPhone $(date +%Y%m%d-%H%M%S)"
DEMO_SIM_UDID="$(xcrun simctl create "$DEMO_SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)"
SIM_NAME="$DEMO_SIM_NAME" SIM_LAUNCH_ARGS='-demo 1 -tab 0' bash sim-run.sh --shutdown
xcrun simctl boot "$DEMO_SIM_UDID"
python3 - "$DEMO_SIM_UDID" <<'PY'
import subprocess, sys
try:
    subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], check=True, timeout=60)
except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
    subprocess.run(['xcrun', 'simctl', 'shutdown', sys.argv[1]])
    raise SystemExit('模拟器启动失败，已请求关机；检查 runtime，不原样重试。')
PY
xcrun simctl launch --terminate-running-process "$DEMO_SIM_UDID" cyou.tianli.daydeck -demo 1 -tab 0
```

若任一步失败就停下，先读该步错误。不要接着运行录制。上述变量在同一个终端会话内使用。当前工具接口已核对 `simctl help create/launch`、`simctl io help` 及共享 `sim-run.sh` 源码。

## 每个功能一小段

| 原片名 | 内容与建议时长 | 应看到的结果 |
|---|---|---|
| `01-today.mov` | 今天分组与一条待办详情，8–12 秒 | 合成标题、分组、来源佐证；不点状态或导出动作 |
| `02-recap.mov` | 通知摘要与时间线，10–15 秒 | 摘要正确排版，合成来源与正文清楚可读 |
| `03-search.mov` | 搜索「房东」，6–10 秒 | 当天匹配结果；清空搜索后恢复摘要 |
| `04-notes.mov` | 随手记页，6–10 秒 | 合成已记下内容、空白草稿；不点「记下来」 |

真实点击、滚动与搜索编辑由本人操作，或后续具备输入隔离的 Computer Use 完成。CLI 可直接落到各页，但不会生成点击/滚动，更不能将静态截图拼接称为实录。各段启动参数分别为 `-tab 0`、`-tab 1`、`-tab 1 -search 房东`、`-tab 2`；每次重启都带 `-demo 1`，无搜索段显式加 `-search ''`。

先在终端设置输出目录，再录一段。录制命令出现 `Recording started` 后才开始相应操作，结束按此终端的 Ctrl-C，等待录像封装完成。换文件名分别录下一段，不覆盖原片。

```bash
VIDEO_ROOT='../02-审核/当前版本/02-视频'
mkdir -p "$VIDEO_ROOT/原片" "$VIDEO_ROOT/clips" "$VIDEO_ROOT/成片"
xcrun simctl io "$DEMO_SIM_UDID" recordVideo --codec=h264 "$VIDEO_ROOT/原片/01-today.mov"
```

每段完成后核查时长与完整解码，再观看首、中、尾和动作前后的关键画面：

```bash
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height -of json "$VIDEO_ROOT/原片/01-today.mov"
ffmpeg -v error -i "$VIDEO_ROOT/原片/01-today.mov" -f null -
```

原片保留，剪辑写 `clips/`，按上述顺序合并到 `成片/`。各段在同一设备、构建、合成数据条件下录制，跨段加章节说明；不要制造连续操作的假象。材料索引记录实际 `.dd-sim/Build/Products/Debug-iphonesimulator/DayDeck.app/Info.plist` 的版本/build、设备/runtime、日期、各段时长与覆盖缺口，不从源码版本猜录制版本。

用完专用模拟器立即关机，不留下后台负载：

```bash
xcrun simctl shutdown "$DEMO_SIM_UDID"
```

确认录像无私人内容后，再由获授权的发布任务登记素材和运行 Chapter 固定媒体验收。文件存在或 ffprobe 成功只证明媒体文件结构，不代表画面审阅、网页播放或发布已通过。本轮不写媒体通过记录、不上传原片、不部署产品页。
