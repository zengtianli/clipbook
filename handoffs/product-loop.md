# Clip 产品流程与推广 · 2026-09-08

用户要求所有自研 app：功能完成后极致降低 RAM / CPU、提升响应速度，保持键盘友好；形成“竞品对比 → 实测优化 → 产品卖点 → 实机视频 → GitHub / 个人网站推广”的可复用流程。

已写入共享 HARNESS，app skill 引用 `references/product-loop.md`；已同步并检查无漂移，cc-home commit d78824e。

Clip build 26 的功能与优化交付见 `keyboard-memory.md`，本轮没有更改生产代码。文档与素材 commit 3952393 已推送。GitHub 介绍/homepage 已更新，但仓库仍 PRIVATE，未发公开安装包。

公开产品页：https://app-mac-clips.tianli.cyou/ ，目录详情：https://apps.tianli.cyou/p/clipbook.html 。51 秒视频：https://apps.tianli.cyou/assets/mac/clipbook/demo.mp4 。Safari 实际播放检查到 20 秒 / 总长 51 秒，下载文件与 staging SHA256 相同。SSOT configs commit eb6951a；共用生成器增加 demo / comparison 支持，stations commit 77c6c4e。都已推送。

测量口径与差异在 `promotion/COMPARISON.md`，证据在 `promotion/performance/`。不要宣传全面胜过 Deck：当前 CPU 观察 Clip 更高，两个 app 状态不一致；速度尚未对等计时。图片浏览减少 57% 指 Clip 自己优化前后。Deck 的 AI / 同步 / 插件仍未替代。

视频由 build 26 真实窗口录制，13 条隔离虚构数据，原片与中间文件保留在 gitignored `promotion/video/`。`prepare_demo.py` 和 `render_video.py` 保留复用；公开只用审核后的 `clip-demo.mp4` 与 `clip-editor.png`。已退出演示实例并恢复生产 Clip，lsof 验证打开正常 Application Support/Clipbook 数据库。

唯一待用户选择：GitHub 对外只发介绍/安装包、源码保持私有，还是审查脱敏后公开源码。已通过异步问题询问，未收到答复；不把默认选项视为授权。现有公开网页暂无安装包的提示属实。用户选定后继续实际发行（检查签名、公证、可独立构建与公开内容），不要直接将私有历史改公开。

stations 工作区存在其他会话修改；本轮仅提交 apps-site/gen_site.py，其他改动保留。部署日志 `/tmp/clip-product-deploy-20260908.log`。源代码 build 26 的实测不会因后续文档 commit 自动变成新二进制版本。
