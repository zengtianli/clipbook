# Clip 使用演示 · AI 剪辑样片

[观看静音版 sample.mp4](sample.mp4)。38.6 秒，1920 × 1080、30 fps，中文字幕。当前采用静音版，默认渲染不添加音乐。

配乐试验仅留在本地，不用于产品主页。

内容依次为搜索记录、编辑保存、从已有收藏夹取出并复制。真实操作来自 Clip 1.1 local build 34 的 2026-09-10 隔离演示录像，包含虚构样例数据；本次复用原片重新剪辑，未录制当前安装版本。

原片保留不动；保留的操作片段均为原速。章节间切换到不同任务，片中标注已剪去等待。放大画面直接取自同一帧原片，字幕与外部标题不覆盖操作区域。不演示安装授权、云同步或向其他 App 自动粘贴。原录制中的复制结果在隔离剪贴板核对，不能据本样片推断操作了用户当前系统剪贴板。

## 修改与重渲染

- `edit.json`：剪点、字幕、章节文案、镜头范围；时间单位为秒，裁切坐标为原片像素。
- `index.tsx`：Remotion 版式、动画、放大框与片头片尾。
- `prepare.py`：核原片 SHA-256，使用 FFmpeg 准备中间片段，输出字幕和来源清单。
- `sample.vtt`：同步字幕；`manifest.json`：来源版本、原片哈希及覆盖范围。
- `mix-music.py`：复用静音视频添加背景音乐，直接复制画面流；`music/mix.json` 记录音量参数及素材/成片哈希。

本机复用既有博客视频工程的 Remotion 4.0.489 和已安装的 FFmpeg，不修改博客工程、不安装新软件。

```bash
cd /Users/tianli/Apps/clip/mac/docs/demo/ai-sample
bash render.sh
```

仅调整配乐时运行 `python3 mix-music.py`，无需重新渲染画面。

`REMOTION_ENGINE` 可指定含已安装 `node_modules` 的 Remotion 工程。默认依赖本机已验证的 Apple Silicon Headless Chrome 路径。中间片段在 Clip 的 `build/ai-video-sample/public`；需要原片目录 `build/homepage-recording/raw`，这不是独立分发包。

产品主页演示区从本目录取已验收的静音视频、封面、字幕及来源清单。构建时核对 `manifest.json` 中的验收哈希；源码、原片与配乐试验均不进入公开目录。

验收：1158 帧、38.6 秒、仅视频轨；全片解码通过，产品画面区域未检出持续 ≥0.1 秒的黑屏。首中尾、编辑保存与复制反馈等关键画面已目验，另经独立复核字幕、剪点与排版。未重新操作当前安装的 Clip 验证现行功能。
