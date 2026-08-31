#!/usr/bin/env python3
"""生成 app 图标：一张翻开的日程页 —— 左边一列时刻刻度，右边三条事，最上面一条打了勾。
画的就是这个 app 是什么：一天的事按时间摊开，做掉的划掉。亮底深字，与 app 内主题一致。
不用外部素材、不联网，重跑结果逐像素一致。

⚠ 直接写进 Assets.xcassets/AppIcon.appiconset/ —— 那才是 actool 真正读的位置。
写到 Resources/icon-1024.png 而 catalog 里那份没换，表现是「图标脚本跑绿了、桌面还是旧图」。
"""
from PIL import Image, ImageDraw
import pathlib

S = 1024
BG    = (247, 247, 249)   # 浅底（与 iOS Form 背景同族）
CARD  = (255, 255, 255)
EDGE  = (206, 210, 219)
RULE  = (223, 227, 234)   # 时刻刻度线
INK   = (10, 122, 255)    # systemBlue：今天这条
DONE  = (52, 199, 89)     # 已完成的那个勾
BAR   = (198, 204, 214)

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)

# 主体卡片
d.rounded_rectangle((150, 168, 874, 856), radius=76, fill=CARD, outline=EDGE, width=7)

# 顶部一条深色栏 —— 日历的「表头」，让它一眼不是备忘录
d.rounded_rectangle((150, 168, 874, 300), radius=76, fill=(238, 241, 246))
d.rectangle((150, 250, 874, 300), fill=(238, 241, 246))
for x in (330, 512, 694):                       # 装订环
    d.rounded_rectangle((x - 16, 130, x + 16, 232), radius=16, fill=(176, 183, 196))

# 左侧时刻刻度
for i in range(4):
    y = 380 + i * 120
    d.line([(214, y), (250, y)], fill=RULE, width=8)

# 三条「事」：第一条打勾（做掉了），后两条是待办
rows = [(380, DONE, True), (500, INK, False), (620, BAR, False)]
for y, color, done in rows:
    d.rounded_rectangle((300, y - 22, 800 if not done else 740, y + 22), radius=22,
                        fill=(235, 238, 243) if not done else (233, 246, 236))
    if done:
        # 勾
        d.line([(322, y + 2), (344, y + 22), (386, y - 22)], fill=DONE, width=17,
               joint="curve")
    else:
        d.ellipse((316, y - 18, 352, y + 18), outline=color, width=9)

# 最下面一条短的：还没写完的日记
d.rounded_rectangle((300, 718, 620, 762), radius=22, fill=(235, 238, 243))

out = pathlib.Path("Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
out.parent.mkdir(parents=True, exist_ok=True)
img.save(out)
print(f"✅ {out} {img.size[0]}x{img.size[1]}")
