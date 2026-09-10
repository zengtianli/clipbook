#!/usr/bin/env python3
"""Caption and crop reviewed real Clip recordings; never recreate the product UI.

Run with /opt/homebrew/bin/python3 (Pillow). Original clips are preserved.
The caption bands are outside the real frame. Local crops and removed waits are
explicitly labelled, and all retained action footage plays at its original speed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "build/homepage-recording/raw"
WORK = ROOT / "build/homepage-recording/edit"
OUT = ROOT / "docs/demo"
FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"
FULL = (23, 16, 1380, 844)
WIDTH, VIEW_HEIGHT, HEADER_HEIGHT, FOOTER_HEIGHT = 1280, 792, 64, 168

# start / end are seconds in the untouched raw clip. Crops are raw-frame pixels.
SCENES = {
    "search": {
        "chapter": "01 / 搜索记录", "poster": 8.0,
        "segments": [
            (0.8, 2.8, FULL, "先找到需要的记录", "13 条虚构记录 · 搜索正文、标题和来源"),
            (3.5, 6.0, (225, 510, 630, 350), "搜索框输入“会议”", "结果缩小为 2 条 · 搜索区局部放大"),
            (8.7, 11.0, (232, 68, 610, 376), "点选“会议安排”", "选中后，右侧显示这条记录的内容"),
            (11.0, 14.0, (855, 65, 546, 338), "会议安排，直接看清楚", "正文区域局部放大 · 保留实际渲染与操作原速"),
        ],
        "independent_result": "录制主线程确认关键词“会议”返回2条，会议安排被选中。",
    },
    "edit": {
        "chapter": "02 / 编辑并保存", "poster": 10.5,
        "segments": [
            (0.8, 2.3, FULL, "选中“会议纪要模板”", "右侧正文可以直接修改，不用先导出"),
            (4.4, 7.6, (855, 65, 546, 338), "添加“4. 周五复盘”", "正文编辑区局部放大 · 修改尚未保存"),
            (11.5, 14.5, (805, 487, 596, 372), "点底部“保存”", "操作区局部放大 · 保存后“有未保存的修改”消失"),
            (14.5, 16.0, FULL, "列表卡片与正文同步更新", "已独立读取本地数据库，确认修改持久化"),
            (16.0, 18.0, (855, 65, 546, 338), "下次复用，已经是新版本", "保存结果局部放大 · 没有新增重复条目"),
        ],
        "independent_result": "录制主线程通过SQL读取生产保存结果，确认正文已持久化且原条目已更新。",
    },
    "organize": {
        "chapter": "03 / 收藏与复制", "poster": 7.5,
        "segments": [
            (0.8, 2.8, FULL, "常用片段，放进固定的位置", "本片使用已经建立的“常用片段”收藏夹"),
            (4.2, 7.0, (23, 337, 600, 372), "点击左侧“常用片段”", "收藏夹筛选后只剩 1 条 · 侧栏局部放大"),
            (9.4, 12.4, (232, 68, 610, 376), "选中“常用开场白”", "片段内容与收藏标记都保留在本机"),
            (14.2, 16.5, (805, 487, 596, 372), "点右下角“复制”", "操作区局部放大 · 不需要重选或重写正文"),
            (16.5, 17.7, (275, 16, 620, 384), "出现“已复制到剪贴板”提示", "结果已在隔离剪贴板中独立核对"),
            (17.7, 19.2, FULL, "常用内容，准备好再次使用", "本片未演示向其他 App 自动粘贴"),
        ],
        "independent_result": "录制主线程读取named pasteboard，确认内容一致；系统剪贴板changeCount始终为503。",
    },
}


def run(*args):
    subprocess.run(args, check=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probe(path):
    return json.loads(subprocess.check_output([FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True))


def timestamp(seconds):
    milliseconds = round(seconds * 1000)
    return f"{milliseconds // 3600000:02}:{milliseconds // 60000 % 60:02}:{milliseconds // 1000 % 60:02}.{milliseconds % 1000:03}"


def caption(path, height, lines):
    im = Image.new("RGB", (WIDTH, height), "#f5f0fa")
    draw = ImageDraw.Draw(im)
    for text, position, size, color in lines:
        font = ImageFont.truetype(FONT, size)
        assert draw.textbbox(position, text, font=font)[2] <= WIDTH - 26, "Caption exceeds the safe margin"
        draw.text(position, text, font=font, fill=color)
    im.save(path)


def concat(parts, target, name):
    listing = WORK / f"{name}-concat.txt"
    listing.write_text("".join(f"file '{part.as_posix()}'\n" for part in parts))
    run(FFMPEG, "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(listing),
        "-c", "copy", "-map_metadata", "-1", "-movflags", "+faststart", str(target))


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    # The recording belongs to a fixed observed build, not a mutable release directory.
    release = json.loads((OUT / "recording-source.json").read_text())
    assert release["version"] == "1.1" and str(release["build"]) == "34" and release["edition"] == "local", "These recordings belong to Clip 1.1 local build 34"
    overview = OUT / "overview.png"
    overview_before = sha(overview) if overview.exists() else None
    entries, chapter_parts, tutorial_cues, offset = {}, [], [], 0.0
    for name, scene in SCENES.items():
        raw = RAW / f"{name}.mov"
        raw_info = probe(raw)
        video = next(stream for stream in raw_info["streams"] if stream["codec_type"] == "video")
        assert (video["width"], video["height"]) == (1426, 890), "Crops were reviewed only for this source geometry"
        raw_duration = float(raw_info["format"]["duration"])
        parts, cuts, cues, elapsed = [], [], [], 0.0
        for index, (start, end, rect, title, subtitle) in enumerate(scene["segments"]):
            assert 0 <= start < end <= raw_duration, "Trim exceeds original footage"
            x, y, width, height = rect
            assert x >= 0 and y >= 0 and x + width <= video["width"] and y + height <= video["height"]
            prefix = WORK / f"{name}-{index}"
            header, footer = prefix.with_suffix(".header.png"), prefix.with_suffix(".footer.png")
            mode = "真实窗口" if rect == FULL else "局部放大"
            caption(header, HEADER_HEIGHT, [
                (f"Clip  {scene['chapter']}", (30, 18), 25, "#4d2864"),
                (f"{mode} · 原速 · 已剪去等待", (815, 23), 19, "#7d628e"),
            ])
            caption(footer, FOOTER_HEIGHT, [
                (title, (32, 30), 35, "#4d2864"),
                (subtitle, (32, 98), 23, "#74617f"),
            ])
            part = prefix.with_suffix(".mp4")
            duration = end - start
            filters = (f"[0:v]crop={width}:{height}:{x}:{y},setpts=PTS-STARTPTS,"
                       f"scale={WIDTH}:{VIEW_HEIGHT}:force_original_aspect_ratio=decrease:force_divisible_by=2,"
                       f"pad={WIDTH}:{VIEW_HEIGHT}:(ow-iw)/2:(oh-ih)/2:white,setsar=1,fps=30[v];"
                       "[1:v][v][2:v]vstack=inputs=3[out]")
            run(FFMPEG, "-y", "-v", "error", "-ss", str(start), "-i", str(raw),
                "-loop", "1", "-framerate", "30", "-i", str(header), "-loop", "1", "-framerate", "30", "-i", str(footer),
                "-filter_complex", filters, "-map", "[out]", "-an", "-t", f"{duration:.3f}",
                "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-profile:v", "high",
                "-map_metadata", "-1", "-movflags", "+faststart", str(part))
            actual_duration = float(probe(part)["format"]["duration"])
            text = title + "\n" + subtitle
            cues.append(f"{timestamp(elapsed)} --> {timestamp(elapsed + actual_duration)}\n{text}")
            tutorial_cues.append(f"{timestamp(offset + elapsed)} --> {timestamp(offset + elapsed + actual_duration)}\n{scene['chapter']}\n{text}")
            cuts.append({"source_start": start, "source_end": end, "output_start": round(elapsed, 3),
                         "output_end": round(elapsed + actual_duration, 3), "crop_xywh": list(rect),
                         "view": mode, "speed": 1, "title": title, "subtitle": subtitle})
            parts.append(part)
            elapsed += actual_duration
        target = OUT / f"{name}.mp4"
        concat(parts, target, name)
        run(FFMPEG, "-y", "-v", "error", "-ss", str(scene["poster"]), "-i", str(target), "-frames:v", "1", str(OUT / f"{name}.png"))
        (OUT / f"{name}.vtt").write_text("WEBVTT\n\n" + "\n\n".join(cues) + "\n")
        chapter_parts.append(target)
        entries[name] = {"raw_file": f"{name}.mov", "raw_sha256": sha(raw), "raw_duration": raw_duration,
                         "raw_geometry": [video["width"], video["height"]], "cuts": cuts,
                         "removed_seconds": round(raw_duration - sum(end - start for start, end, *_ in scene["segments"]), 3),
                         "output_duration": float(probe(target)["format"]["duration"]), "output_sha256": sha(target),
                         "poster_time": scene["poster"], "independent_result": scene["independent_result"],
                         "visual_review": "原片首中尾及操作前后关键帧已逐片核对；最终由主线程验收。"}
        offset += elapsed
    concat(chapter_parts, OUT / "tutorial.mp4", "tutorial")
    (OUT / "tutorial.vtt").write_text("WEBVTT\n\n" + "\n\n".join(tutorial_cues) + "\n")
    checks = {}
    for name in (*SCENES, "tutorial"):
        target = OUT / f"{name}.mp4"
        result = subprocess.run([FFMPEG, "-hide_banner", "-v", "info", "-i", str(target),
                                 "-vf", "crop=1280:792:0:64,blackdetect=d=0.2:pic_th=0.98:pix_th=0.10", "-an", "-f", "null", "-"],
                                capture_output=True, text=True)
        assert result.returncode == 0 and "black_start:" not in result.stderr, f"Decode or black-frame check failed for {name}"
        (WORK / f"{name}-decode.log").write_text(result.stderr)
        info = probe(target)
        v = next(s for s in info["streams"] if s["codec_type"] == "video")
        assert v["codec_name"] == "h264" and v["pix_fmt"] == "yuv420p" and (v["width"], v["height"]) == (1280, 1024)
        checks[name] = {"decode": "passed", "black_frames": "none in product-image area >= 0.2s at 98% black", "duration": float(info["format"]["duration"]),
                        "sha256": sha(target), "bytes": target.stat().st_size}
    metadata = {
        "product": "Clip", "version": release["version"], "build": str(release["build"]), "edition": "local",
        "recorded_at": "2026-09-10", "environment": {"macos": "27.0", "chip": "Apple M4"},
        "release_sha256_observed_before_editing": release["release_sha256_observed_before_editing"],
        "source": "real-app-window", "synthetic_input": True, "synthetic_records": 13,
        "isolation": {"same_executable_as_release_candidate": True, "separate_bundle_and_preferences": True,
                      "background_non_key_panel": True, "capture_paused": True, "copy_sound": False,
                      "cloud_enabled": False, "named_pasteboard": True, "system_clipboard_unchanged": True},
        "editing": {"caption_bands_outside_product_image": True, "local_zoom_labelled": True,
                    "retained_footage_speed": 1, "removed_waits_labelled": True,
                    "tutorial_is_three_separate_chapters": True, "audio": "原片无音轨，成片静音"},
        "scenes": entries, "checks": checks,
        "not_covered": ["向其他应用自动粘贴", "系统剪贴板写入", "云同步", "新用户安装与权限授予"],
        "private_data_review": "已核源片均为13条虚构样例；未见用户聊天、账户、目录或其他应用。系统剪贴板未进入录像。",
        "final_visual_review": "pending-main-thread",
    }
    (OUT / "recording.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    assert (sha(overview) if overview.exists() else None) == overview_before, "overview.png must remain untouched"
    print(json.dumps(checks, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
