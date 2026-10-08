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
import product_facts  # facts.json published with the page for the portal and Chapter

ROOT = Path(__file__).resolve().parents[1]
SCENES = [("search", "找到需要的记录", "输入关键词，从结果中选中需要的片段。"),
          ("edit", "直接编辑，保存复用", "选择一条文字，修改后保存，核对实际结果。"),
          ("organize", "从收藏夹再次取用", "打开常用片段，选中记录，再点击复制。")]

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def historical_reuse(release, proof_path):
    proof = json.loads(proof_path.read_text())
    assert proof.get("state") == "passed" and proof.get("local_github_entry_selftest") and proof.get("original_selftest_passed"), "Current local production selftests are required"
    assert proof.get("version") == release["version"] and str(proof.get("build")) == str(release["build"]), "Historical reuse tests belong to another release"
    assert proof.get("sha256") == release["sha256"], "Historical reuse tests belong to another archive"
    assert proof.get("source_head") == release.get("source_commit"), "Historical reuse tests belong to another source commit"
    assert sha(Path(proof["log"])) == proof["log_sha256"], "Historical reuse test log changed"
    receipt = json.loads(Path(proof["receipt_path"]).read_text())
    assert receipt["source"]["sha256"] == proof["receipt_source_sha256"] and receipt["source"]["commit"] == proof["source_head"], "Historical reuse receipt source changed"
    return {"archive_sha256": release["sha256"], "source_sha256": proof["receipt_source_sha256"],
            "source_commit": proof["source_head"], "checked_at": proof["finished_at"],
            "tests": ["original production --selftest", "actual local UI update source is GitHub zengtianli/clipbook"],
            "reason": "Retain reviewed original footage as historical reference; the new configuration/update window is outside its recorded scope",
            "not_covered": ["配置与更新窗口", "配置导出与导入", "真实跨设备 iCloud 配置同步", "GitHub 新版下载与手动安装"]}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "build/site")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--keep-history", action="store_true", help="Explicitly retain reviewed original media/performance, labelled as historical evidence")
    parser.add_argument("--history-tests", type=Path, help="Archive/source-bound current local build and production selftest proof")
    args = parser.parse_args()
    if args.keep_history and (args.preview or not args.history_tests):
        parser.error("--keep-history requires --history-tests and an actual release, without --preview")
    if args.history_tests and not args.keep_history:
        parser.error("--history-tests requires --keep-history")
    release_dir = ROOT / "build/local-release"
    release = json.loads((release_dir / "release.json").read_text())
    archive = release_dir / release["filename"]
    assert sha(archive) == release["sha256"], "Release archive changed"
    reuse = historical_reuse(release, args.history_tests) if args.keep_history else None
    measured = json.loads((ROOT / "perf/lightweight.json").read_text())
    media = ROOT / "docs/demo"
    needed = ["overview.png", "tutorial.mp4", "recording.json"]
    needed += [f"{name}.{ext}" for name, _, _ in SCENES for ext in ("mp4", "png", "vtt")]
    missing = [name for name in needed if not (media / name).is_file()]
    if missing and not args.preview:
        raise SystemExit("Actual reviewed media is required: " + ", ".join(missing))
    if not args.preview:
        recording = json.loads((media / "recording.json").read_text())
        if reuse:
            recording.setdefault("reused_for", {})[release["version"]] = reuse
        assert recording.get("final_visual_review") == "passed", "Final visual review is required"
        compatible = recording.get('reused_for', {}).get(release['version'])
        assert (recording.get("version") == release["version"] or compatible) and recording.get("edition") == release["edition"], "Recording edition differs from release"
        for name in needed:
            if name != "recording.json":
                assert recording.get("reviewed_media_sha256", {}).get(name) == sha(media / name), f"Reviewed media changed: {name}"
    guide_dir = media / "ai-sample"
    guide = json.loads((guide_dir / "manifest.json").read_text())
    if reuse:
        guide.setdefault("reused_for", {})[release["version"]] = reuse
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
    (out / "media/clip-guide-recording.json").write_text(json.dumps(guide, ensure_ascii=False, indent=2) + "\n")
    if reuse:
        (out / "media/recording.json").write_text(json.dumps(recording, ensure_ascii=False, indent=2) + "\n")
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
              "LIGHT": perf_block.standalone_section(ROOT / "perf/lightweight.json", measured["version"].split(" ")[0], "#8250ad"),
              "HERO": '<img src="media/overview.png" alt="Clip 的真实三栏窗口：来源与类型筛选、剪贴板记录、正文编辑">' if (media / "overview.png").is_file() else '<div class="preview-placeholder">等待真实窗口截图</div>',
              "VIDEOS": "".join(videos), "GUIDE": guide_player,
              "GUIDE_DOWNLOAD": "media/" + guide_files["sample.mp4"]}
    measured_build = str(measured["version"])
    released_build = f"{release['version']} ({release['build']})"
    if measured_build != released_build:
        scope = (f"本地验收构建 {measured_build} 的实测；当前公开下载为 {released_build}。"
                 "下列数据不代表已发布包；没有将本地测量记成公开版的新测。")
        values["LIGHT"] = values["LIGHT"].replace("<div class='perf-grid'>",
            "<p class='fine'>" + html.escape(scope) + "</p><div class='perf-grid'>", 1)
    page = (ROOT / "site/index.html").read_text()
    history = None
    if reuse:
        history = {"measured_version": measured["version"], "measured_at": measured["measured_at"],
                   "recorded_version": recording["version"], "recorded_build": recording["build"], "recorded_at": recording["recorded_at"],
                   "guide_version": guide["source_version"], "guide_build": guide["source_build"], "guide_recorded_at": guide["source_recorded_at"],
                   "not_covered": reuse["not_covered"]}
        text = (f"当前下载为 Clip {release['version']}({release['build']}) 本地版。录像和截图为 {recording['version']}({recording['build']})（{recording['recorded_at']}），"
                f"教程原片为 {guide['source_version']}({guide['source_build']})（{guide['source_recorded_at']}）；性能数据为 {measured['version']}（{measured['measured_at']}）。"
                "历史参考、不代表新版新测。新增的「配置与更新…」窗口、配置导入/导出、可选 iCloud 配置同步和 GitHub 更新下载未在旧录像中展示。")
        notice = '<aside class="wrap" role="note" style="padding:20px;border:1px solid #8250ad;margin-top:24px"><strong>历史参考、不代表新版新测</strong><p>' + html.escape(text) + '</p></aside>'
        page = page.replace('<main>', '<main>' + notice, 1)
        page = page.replace("当前下载版专注本地剪贴板，不含 iCloud 同步。", "当前下载版的剪贴板历史留在本机；可在「配置与更新…」导出、导入配置或选择开启 iCloud 配置同步。")
        page = page.replace("本地发行版不提供 iCloud 同步。", "本地发行版的剪贴板历史保存在本机；配置可选择跟随 iCloud。")
        page = page.replace("这个 Mac 安装包不含 iCloud 同步，两端记录不会互通。", "这个 Mac 安装包的剪贴板历史不走 iCloud，两端记录不会互通；配置可单独选择开启 iCloud 同步。")
        values["GUIDE"] = values["GUIDE"].replace("当前版沿用相同的搜索、编辑和收藏界面。", "仅作为搜索、编辑和收藏流程的历史参考。")
    page = page.replace('href="style.css"', f'href="style.css?v={sha(ROOT / "site/style.css")[:12]}"')
    for key, value in values.items():
        page = page.replace("{{" + key + "}}", value if key in ("HERO", "VIDEOS", "GUIDE", "LIGHT") else html.escape(value, quote=True))
    assert not re.search(r"\{\{[^}]+\}\}", page), "Unresolved website placeholder"
    (out / "index.html").write_text(page)
    facts = product_facts.from_repo(ROOT, product_id="clipbook", icon="images/icon.png")
    facts["download_bytes"] = archive.stat().st_size
    if reuse:
        facts.update(historical_reference=True, measured_version=measured["version"], historical_reference_note="历史参考、不代表新版新测")
        facts["card_line"] = f"当前下载 {perf_block.size_mb(archive.stat().st_size)} · 历史实测 {measured['version']}（{measured['measured_at']}） · " + facts["card_line"]
        facts["card_text"] = product_facts.card_text(facts["card_line"])
    product_facts.write(out, facts)
    files = [{"path": p.relative_to(out).as_posix(), "sha256": sha(p)} for p in sorted(out.rglob("*")) if p.is_file()]
    (out / "site-manifest.json").write_text(json.dumps({"product": "Clip", "preview": args.preview, "keep_history": args.keep_history, "history": history, "files": files}, ensure_ascii=False, indent=2) + "\n")
    print(out)

if __name__ == "__main__":
    main()
