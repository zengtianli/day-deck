# Notihub iOS 推广页缺项交接

本轮仅调查并保存本文，未修改共享配置、Mac 仓、门户或共享引擎，未部署。时间：2026-09-28。当前授权已允许本组件提交、推送和部署；例外是不能改动或部署其他组件服务。本文的阻碍是跨组件责任边界和现有发布接口能力，不能概括成“用户禁止部署”。

## 已核实的责任层

`~/Dev/tools/configs/menus/entities/products.yaml` 把 `day-deck-ios` 的主页登记为 `https://app-mac-notihub.tianli.cyou/#iphone`，正式图标登记为本仓 `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`。本仓 `make_icon.py` 从 Mac 同源图裁出满幅、不透明 iOS 图标；Mac 行登记的是 `~/Apps/notifhub/mac/icon/AppIcon.icns`，存在平台包装差异。

`~/Dev/tools/dev/lib/tools/macapp/product_icons.py` 的 `IconReferences` 不处理 URL fragment。`~/Apps/chapter/engine/app_sop.py` 对产品主页调用它时传 `product_id=None`，于是 `#iphone` 仍会收集整页品牌图标和 favicon，再逐个与 iOS 正式素材比较。Chapter 开工前报告的差值是 21.59/255；本轮核实了错误比较范围的源码，没有把它视为 iOS 图标需要重新设计的证据。

`~/Apps/apps-portal/site/standalone_homepage.py` 的 `companions()` 能识别 `#iphone` 所属的 iOS 组件，但目前渲染 companion section 时只输出截图、文案、功能及获取说明，没有输出它的正式图标或 `perf_block.section(sibling['_perf'])`。父级 Mac 性能卡不能证明 iOS 性能。

最小修复需同时在两处落实：

1. 门户 `standalone_homepage.py` 的 companion section 输出该组件 `_icon` 和 `_perf`，标明 iPhone/iPad 与测量环境，继续保持自用展示、无公开下载。
2. 共享 `product_icons.py` 对带 fragment 的主页只检查目标 section 内的可见组件图标；不存在 section 或可见图标时失败。全页主页继续核对全页品牌/favicon，不能降低像素阈值掩盖错误，也不能用改变 iOS 正式源规避。

这两处均在本组件仓外。模板最小改动可控制在 `companions()` 的输出分支，图标校验最小改动可控制在 `IconReferences` 对 URL fragment 的范围选择；具体补丁由责任方处理，本轮没有改共享源码或跨组件发布。

## 当前发布接口不能限定 iOS 小节

本轮重新读取了 `product_bundles.py` 与 `scripts/deploy_product_bundles.py`，结论仍是没有 section 级发布入口：

- `product_bundles.stage_product_bundle()` 校验整个 `site-manifest.json`，要求 `index.html`，验证文件白名单与哈希后替换整个目标目录；不识别 HTML fragment。
- `deploy_product_bundles.py` 的 `ALLOWED_IDS` 只有 `clipbook`、`folio-mac`、`doc-tools`、`photo-desk`；iOS 与 Notihub Mac 均不在其中。
- `select_rows()` 要求 `category=mac`、公开产品及 `homepage_bundle`；远端根固定为 `/var/www/apps-products/mac`。`validate_assets()` 还强制安装包下载，与当前自用、仅展示的 iOS 页政策不符。
- `scripts_for()` 为整个选定产品目录生成备份、`rsync --delete`、哈希检查和目录回滚；不存在“只部署 `#iphone` 且 Mac 其余字节不变”的参数。

仅将 Notihub 加进白名单不足以解决问题。要扩展单组件可回滚入口，至少需处理自用无下载政策、iOS 数据归属、section 精确定位、发布前远端基线哈希校验、只替换该 section 与其资产、失败回滚及验收范围。即使保留其他 HTML 字节不变，发布对象仍是 Mac 组件的 `index.html`。这超出快速补小缺项的范围，本轮不新增发布器、不借用全门户部署。

受阻责任：`owner=notifhub-bar-mac`——iOS 指向其主页 `#iphone`，任何线上小节替换都写该组件网页；门户生成/发布接口归 `~/Apps/apps-portal/site`（本地项目名 `apps-site`）。共享校验器归 `~/Dev/tools/dev/lib/tools/macapp/product_icons.py`。此处只记录依赖，没有向其他产品创建 decision，也没有修改 `agents.json` 或 owner 授权。

## 性能事实（上一轮记录）

本节保留上一轮性能事实；本轮新增的固定 CLI、产物摘要与复用限制见 [性能证据接手说明](performance-followup.md)。现在可运行 `~/Dev/.venv/bin/python scripts/measure-simulator.py --run`，它先检查空闲门，再构建并测量独立模拟器；尚未产生本轮有效数字。

`perf/simulator.json` 是 2026-09-27 的 `0.1 (1)` Release 模拟器记录：空闲 27 MiB（28.3 MB）、0% CPU、首屏 458.2 ms；其 ZIP 不是 App Store IPA。此文件保留来源哈希和原始测量路径。当前生产源码已改变，不能直接将这些数值标为本轮有效结果。

上一轮主 agent 确认空闲门失败（负载 95.6，要求低于 10），当时跳过重新采样。页面展示的安装包/安装后占用也应继续由当前 `perf/lightweight.json` 及测量管线派生，不能手填本文中的历史数字。

## 在本仓 CLI 接手

先执行安全的状态复核；`--check-only` 必须保留。`app_sop.py run` 的真实帮助说明其默认可能自动修复、推送和部署；本组件虽然有部署授权，其当前推广 URL 却指向 Mac 主页，自动部署不能保证符合单组件边界。

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --check-only --json
```

用户从本仓 CLI 接手的下一步是读取已核实的发布接口及责任文件，将“只处理 iOS section，Mac 其余内容和其他产品不变”交给 `notifhub-bar-mac` / 门户责任方确认范围。以下均为只读，不会生成发布计划或连接服务器：

```bash
python3 ~/Dev/tools/cc-home/tools/harness/claims.py list
~/Dev/.venv/bin/python ~/Apps/apps-portal/site/scripts/deploy_product_bundles.py --help
rg -n 'ALLOWED_IDS|REMOTE =|def select_rows|def validate_assets|def scripts_for' ~/Apps/apps-portal/site/scripts/deploy_product_bundles.py
rg -n 'for anchor, sibling|_icon|_perf' ~/Apps/apps-portal/site/standalone_homepage.py
```

责任方明确允许修改其页面后，再为共享文件声明 claim 并实现上述补丁；claim 本身不授予跨组件发布权限。当前没有一条已存在、可安全复制执行的“只部署 Notihub iOS 小节”命令，不能伪造这一入口。

性能重新采样使用本仓固定入口，不必再手工适配旧 UUID/import。目前仍未登记 `sop.measure`，`run --stage perf` 只用于新原件落盘后的检查，不能自动补测：

```bash
~/Dev/.venv/bin/python scripts/measure-simulator.py --run
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --stage perf --check-only --json
```

第一条命令有已授权的模拟器构建、安装与采样动作，先过空闲门；忙时退出 75，不等待或重试。它复用既有首屏探针及共享内存/CPU 工具，绑定实际构建、安装副本、Runtime 和源码摘要，成功后原子替换证据；失败保留旧记录。本轮没有执行长采样，不把固定入口或模拟测试算作实际性能通过。

全门户 `deploy.sh` 会同步整个门户并处理 nginx，不属于本组件部署入口，本轮不执行也不把它列为建议接手命令。责任方完成受限发布后，从本仓再次运行上面的 `app_sop.py run --app day-deck-ios --check-only --json`，由现有引擎回读真实线上图片和页面数字。本文不是图标、页面、性能或播放通过证据，不手写 `perf/delivery-evidence.json`。
