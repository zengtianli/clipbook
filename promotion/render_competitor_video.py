"""Combine real synthetic-image captures and explicitly scoped measurements."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent / 'video'
FF = '/opt/homebrew/bin/ffmpeg'
FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
def font(size): return ImageFont.truetype(FONT, size)
parts = []
for name, title, subtitle in [
    ('clip', 'Clip · 图片网格 95.5 MiB', '同一批 20 张 2048×2048 PNG · 浏览后关窗 94.7 MiB'),
    ('pastepal', 'PastePal 2.21.1 · 图片网格 271.9 MiB', '同一批生成图片 · 浏览后收起主窗口和侧栏 260.1 MiB'),
    ('maccy', 'Maccy 2.7.1 · 图片预览 409.8 MiB', '同一批生成图片 · 切换预览后收起面板 444.1 MiB'),
]:
    banner = Image.new('RGB', (1220, 130), '#f5f1fa')
    d = ImageDraw.Draw(banner)
    d.text((30, 15), title, font=font(30), fill='#43265d')
    d.text((30, 66), subtitle, font=font(22), fill='#51465a')
    p = ROOT / f'{name}-bench-banner.png'; banner.save(p)
    out = ROOT / f'{name}-bench-scene.mp4'
    subprocess.run([FF, '-y', '-v', 'error', '-i', str(ROOT/f'{name}-images-raw.mov'),
        '-loop', '1', '-i', str(p), '-filter_complex',
        '[0:v]scale=1220:642:force_original_aspect_ratio=decrease,pad=1220:642:(ow-iw)/2:(oh-ih)/2:color=white,setsar=1[v];[v][1:v]vstack=inputs=2[out]',
        '-map', '[out]', '-an', '-t', '8', '-r', '30', '-c:v', 'libx264', '-threads', '2',
        '-crf', '22', '-pix_fmt', 'yuv420p', str(out)], check=True)
    parts.append(out)
im = Image.new('RGB', (1220, 772), '#f5f1fa'); d = ImageDraw.Draw(im)
lines = [
    ('更轻的图片预览，来自有边界的内存使用', 36),
    ('20 张 2048×2048 图片｜主进程 physical footprint', 25),
    ('                         图片界面           关窗后', 26),
    ('Clip                    95.5 MiB           94.7 MiB', 30),
    ('PastePal              271.9 MiB          260.1 MiB', 30),
    ('Maccy                 409.8 MiB          444.1 MiB', 30),
    ('Apple M4 · macOS 27.0 · 2026-09-08 · 每阶段观察 30 秒', 21),
    ('单轮观察，窗口大小与 UI 形态不同；不代表全面性能排序。', 22),
    ('没有同负载速度结论；更多数据和条件见 GitHub 产品页。', 22),
    ('github.com/zengtianli/clip-macos', 26),
]
y = 30
for text, size in lines:
    d.text((36, y), text, font=font(size), fill='#43265d'); y += 71
p = ROOT/'competitor-results.png'; im.save(p)
out = ROOT/'competitor-results-scene.mp4'
subprocess.run([FF,'-y','-v','error','-loop','1','-i',str(p),'-t','12','-r','30',
                '-c:v','libx264','-threads','2','-pix_fmt','yuv420p',str(out)],check=True)
parts.append(out)
lst = ROOT/'competitor-concat.txt';lst.write_text(''.join(f"file '{p.name}'\n" for p in parts))
subprocess.run([FF,'-y','-v','error','-f','concat','-safe','0','-i',str(lst),'-c','copy',
                '-map_metadata','-1','-movflags','+faststart',str(ROOT/'clip-competitors.mp4')],check=True)
