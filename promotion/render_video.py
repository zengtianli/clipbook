"""Render real-time product excerpts with separate, factual caption bands."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent / 'video'
FF = '/opt/homebrew/bin/ffmpeg'
FONT = '/System/Library/Fonts/STHeiti Medium.ttc'

def card(name, title, subtitle, height=130):
    im = Image.new('RGB', (1220, height), '#f5f1fa')
    d = ImageDraw.Draw(im)
    d.text((36, 18), title, font=ImageFont.truetype(FONT, 30), fill='#43265d')
    d.text((36, 68), subtitle, font=ImageFont.truetype(FONT, 20), fill='#51465a')
    p = ROOT / name
    im.save(p)
    return p

scenes = [
    ('clip-demo-raw.mov', 9, 14, '搜索 → 方向键选择 → Shift 扩选', 'Clip · 原生 macOS 剪贴板库｜虚构数据实机演示 · 操作原速'),
    ('clip-keyboard-raw.mov', 2, 8, 'Return：一次复制多条记录', '减少鼠标来回移动，让查找、选择和复制顺手完成'),
    ('clip-edit-raw.mov', 1, 19, '直接修改片段，保存后立即复用', '本地文字编辑｜置顶、分类与收藏｜原始图片完整保留'),
]
parts=[]
for i,(src,start,duration,title,sub) in enumerate(scenes):
    banner=card(f'caption-{i}.png', title, sub)
    out=ROOT/f'scene-{i}.mp4'
    subprocess.run([FF,'-y','-v','error','-ss',str(start),'-t',str(duration),'-i',str(ROOT/src),'-loop','1','-i',str(banner),'-filter_complex','[0:v]scale=1220:642,setsar=1[v];[v][1:v]vstack=inputs=2[out]','-map','[out]','-an','-t',str(duration),'-r','30','-c:v','libx264','-crf','20','-pix_fmt','yuv420p',str(out)],check=True)
    parts.append(out)

im=Image.new('RGB',(1220,772),'#f5f1fa'); d=ImageDraw.Draw(im)
lines=[('Clip · 更轻，是持续实测的产品方向',40),('安装占用：Clip 3.3 MB / Deck 1.4.5 约 60 MB',29),('Clip 图片浏览内存：275.5 → 117.3 MiB（下降约 57%）',29),('上行为 Clip 优化前后；不是与 Deck 的内存对比',23),('适合本地检索与片段编辑；AI / 同步 / 插件暂不替代 Deck',25),('尚未完成同负载速度对比；不宣称全面领先',23),('Apple M4 · 2026-09-08 · build 26 · 详见产品页测量说明',21),('app-mac-clips.tianli.cyou',30)]
y=65
for s,size in lines:
    d.text((48,y),s,font=ImageFont.truetype(FONT,size),fill='#43265d'); y+=82
end=ROOT/'comparison.png'; im.save(end)
out=ROOT/'scene-end.mp4'
subprocess.run([FF,'-y','-v','error','-loop','1','-i',str(end),'-t','10','-r','30','-c:v','libx264','-pix_fmt','yuv420p',str(out)],check=True)
parts.append(out)
lst=ROOT/'concat.txt'; lst.write_text(''.join(f"file '{p.name}'\n" for p in parts))
subprocess.run([FF,'-y','-v','error','-f','concat','-safe','0','-i',str(lst),'-c','copy','-map_metadata','-1','-movflags','+faststart',str(ROOT/'clip-demo.mp4')],check=True)
