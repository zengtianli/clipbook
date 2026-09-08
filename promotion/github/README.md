# Clip for macOS

**快速取用，轻装常驻。** 原生 Mac 剪贴板库，把搜索、选择、编辑和复制放在一个窗口里。

[产品主页](https://app-mac-clips.tianli.cyou/) · [51 秒实机演示](https://apps.tianli.cyou/assets/mac/clipbook/demo.mp4)

![Clip 的搜索、选择和编辑窗口](https://apps.tianli.cyou/assets/mac/clipbook/01.jpg)

## 手留在键盘上

方向键移动，Shift 扩选，Return 复制，Tab 切换控件。搜索框和正文编辑中的方向键仍然移动文字光标。快捷键可配置，默认不注册全局组合。

## 找到，改好，再复用

在本机保存文本、富文本、链接、图片、文件与代码；按类型和来源筛选，直接编辑片段，收藏常用内容，多选后一起复制。

## 少占资源，是产品要求

全 Swift 原生应用，无网页渲染进程。build 26 本机安装占用约 3.3 MB。

同一台 Apple M4、同一份图片历史与操作脚本的优化前后测试中，图片浏览内存从 **275.5 降至 117.3 MiB，约下降 57%**。这是 Clip 自己优化前后的比较，**不是比竞品少 57%**。预览按显示尺寸解码，缓存有上限，关窗释放界面；原始图片和未保存草稿仍保留。

[36 秒真实窗口对比视频](clip-competitors.mp4) · [测试数据与方法](COMPETITOR-RESULTS.md)

同一批 20 张 2048×2048 PNG 的本机观察：Clip 图片网格 **95.5 MiB**，PastePal 2.21.1 图片网格 **271.9 MiB**，Maccy 2.7.1 图片预览 **409.8 MiB**。均为主进程 physical footprint、30 秒阶段结束值。各自窗口大小与 UI 形态不同，属于单轮情景观察；纯文本下 Clip 与 Maccy 接近。尚无同负载速度结论，不宣称全面领先。

## 适合谁

主要需要本机历史检索、片段编辑与键盘复制的 Mac 用户。当前不提供跨设备同步、AI 或插件生态；如果这些功能是你的核心需求，Clip 暂时不能完整替代现有工具。

## 当前状态

本仓是公开产品介绍与演示入口，源代码保持私有。当前暂无公开安装包。演示来自真实 build 26，使用 13 条隔离的虚构数据，操作片段原速、剪去等待；演示不是速度基准。

---

**Native macOS clipboard library. Keyboard-first, local, and built to stay light.** Search, edit, organize and copy snippets in one window. The measured 57% reduction describes Clip's own image-browsing optimization, not a competitor comparison. No public installer is available yet.
