"""Build the Clip website from the actual release and reviewed real media."""
from pathlib import Path
import argparse
import hashlib
import html
import json
import re
import shutil
import sys

sys.path.insert(0, str(Path.home() / "Apps/apps-portal/site"))
import perf_block  # shared lightweight block; numbers come from perf/lightweight.json

ROOT = Path(__file__).resolve().parents[1]
SCENES = [("search", "找到需要的记录", "输入关键词，从结果中选中需要的片段。"),
          ("edit", "直接编辑，保存复用", "选择一条文字，修改后保存，核对实际结果。"),
          ("organize", "从收藏夹再次取用", "打开常用片段，选中记录，再点击复制。")]

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "build/site")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    release_dir = ROOT / "build/local-release"
    release = json.loads((release_dir / "release.json").read_text())
    archive = release_dir / release["filename"]
    assert sha(archive) == release["sha256"], "Release archive changed"
    media = ROOT / "docs/demo"
    needed = ["overview.png", "tutorial.mp4", "recording.json"]
    needed += [f"{name}.{ext}" for name, _, _ in SCENES for ext in ("mp4", "png", "vtt")]
    missing = [name for name in needed if not (media / name).is_file()]
    if missing and not args.preview:
        raise SystemExit("Actual reviewed media is required: " + ", ".join(missing))
    if not args.preview:
        recording = json.loads((media / "recording.json").read_text())
        assert recording.get("final_visual_review") == "passed", "Final visual review is required"
        compatible = recording.get('reused_for', {}).get(release['version'])
        assert (recording.get("version") == release["version"] or compatible) and recording.get("edition") == release["edition"], "Recording edition differs from release"
        for name in needed:
            if name != "recording.json":
                assert recording.get("reviewed_media_sha256", {}).get(name) == sha(media / name), f"Reviewed media changed: {name}"
    guide_dir = media / "ai-sample"
    guide = json.loads((guide_dir / "manifest.json").read_text())
    guide_files = {name: f"clip-guide-{sha(guide_dir / name)[:12]}{(guide_dir / name).suffix}"
                   for name in ("sample.mp4", "poster.jpg", "sample.vtt")}
    assert guide.get("final_visual_review") == "passed", "Guide visual review is required"
    assert guide.get("source_version") == release["version"] or guide.get('reused_for', {}).get(release['version']), "Guide source version differs from release"
    for name in guide_files:
        assert guide.get("reviewed_media_sha256", {}).get(name) == sha(guide_dir / name), f"Reviewed guide changed: {name}"
    out = args.out
    if out.exists():
        shutil.rmtree(out)
    for part in ("images", "downloads", "media"):
        (out / part).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "icon/AppIcon.png", out / "images/icon.png")
    shutil.copy2(ROOT / "site/style.css", out / "style.css")
    shutil.copy2(archive, out / "downloads" / archive.name)
    shutil.copy2(release_dir / "SHA256SUMS.txt", out / "downloads/SHA256SUMS.txt")
    (out / "release.json").write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n")
    for name in needed:
        if (media / name).is_file():
            shutil.copy2(media / name, out / "media" / name)
    for name, public_name in guide_files.items():
        shutil.copy2(guide_dir / name, out / "media" / public_name)
    shutil.copy2(guide_dir / "manifest.json", out / "media/clip-guide-recording.json")
    guide_player = (f'<article class="featured-demo"><video controls playsinline preload="metadata" '
                    f'width="1920" height="1080" aria-label="Clip 完整使用演示：搜索、编辑保存、收藏复制" '
                    f'poster="media/{guide_files["poster.jpg"]}">'
                    f'<source src="media/{guide_files["sample.mp4"]}" type="video/mp4">'
                    f'<track kind="subtitles" src="media/{guide_files["sample.vtt"]}" srclang="zh" label="中文">'
                    '你的浏览器不支持视频，请下载观看。</video>'
                    '<h3>39 秒，了解 Clip 的三个常用操作</h3>'
                    '<p>搜索记录 → 编辑保存 → 收藏复制。静音中文字幕，关键操作局部放大。</p>'
                    f'<p>原片为 Clip {html.escape(guide["source_version"])} 本地版实录；当前版沿用相同的搜索、编辑和收藏界面。云同步与自动粘贴不在本演示范围。</p></article>')
    videos = []
    for name, title, description in SCENES:
        player = (f'<video controls playsinline preload="metadata" poster="media/{name}.png"><source src="media/{name}.mp4" type="video/mp4"><track kind="subtitles" src="media/{name}.vtt" srclang="zh" label="中文">你的浏览器不支持视频，请下载观看。</video>'
                  if (media / f"{name}.mp4").is_file() else '<div class="preview-placeholder">真实片段录制准备中</div>')
        videos.append(f'<article>{player}<h3>{title}</h3><p>{description}</p><a href="media/{name}.mp4" download>下载这一段 ↗</a></article>')
    values = {"DOWNLOAD": "downloads/" + archive.name, "VERSION": release["version"],
              "MIN_OS": release["minimum_macos"], "FILENAME": archive.name,
              "SIZE": perf_block.size_mb(release["bytes"]), "SHA256": release["sha256"],
              "LIGHT": perf_block.standalone_section(ROOT / "perf/lightweight.json", release["version"], "#8250ad"),
              "HERO": '<img src="media/overview.png" alt="Clip 的真实三栏窗口：来源与类型筛选、剪贴板记录、正文编辑">' if (media / "overview.png").is_file() else '<div class="preview-placeholder">等待真实窗口截图</div>',
              "VIDEOS": "".join(videos), "GUIDE": guide_player,
              "GUIDE_DOWNLOAD": "media/" + guide_files["sample.mp4"]}
    page = (ROOT / "site/index.html").read_text()
    page = page.replace('href="style.css"', f'href="style.css?v={sha(ROOT / "site/style.css")[:12]}"')
    for key, value in values.items():
        page = page.replace("{{" + key + "}}", value if key in ("HERO", "VIDEOS", "GUIDE", "LIGHT") else html.escape(value, quote=True))
    assert not re.search(r"\{\{[^}]+\}\}", page), "Unresolved website placeholder"
    (out / "index.html").write_text(page)
    files = [{"path": p.relative_to(out).as_posix(), "sha256": sha(p)} for p in sorted(out.rglob("*")) if p.is_file()]
    (out / "site-manifest.json").write_text(json.dumps({"product": "Clip", "preview": args.preview, "files": files}, ensure_ascii=False, indent=2) + "\n")
    print(out)

if __name__ == "__main__":
    main()
