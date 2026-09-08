# Clip 产品流程与推广 · 2026-09-08

**最终收尾：用户明确“不要测试了，差不多”，停止继续测试。** 已退出 Paste/CleanClip/PastePal/Maccy 测试进程、恢复剪贴板及正常 Clip/Deck。所有结果保存在 promotion/README.md 索引下。公开展示仓 c30e660 含三款对比、数据与36秒视频；私人仓保存完整22条采样和其他竞品结果。Paste 后续已测文本56.0/55.5MiB；CleanClip MacKed版 SIGBUS 崩溃，换官方2.4.7可进入免费版设置，但未继续测负载。新增网站GitHub链接因无关注册表错误未部署，其未发布配置已撤回，原有公开产品页与51秒视频保持可访问。以下是过程记录，不能据其“待测”自动恢复已被用户停止的测试。没有发布公开安装包。

## 后续实测与公开推广（本轮仍有未完成项）

公开展示仓已建并推送：`https://github.com/zengtianli/clip-macos`，最新公开提交 `c30e660`。只包含产品介绍、限定范围的三款对比、采样 JSON 和 36 秒真实窗口比较视频；原 `clipbook` 源码仓仍私有，没有公开安装包。交付总入口 `promotion/README.md`。

Clip / PastePal / Maccy 完成文本、20 张同源 2048×2048 图片、关窗后的 30 秒单轮观察。图片界面结束值分别 95.5 / 271.9 / 409.8 MiB，收起后 94.7 / 260.1 / 444.1 MiB。窗口大小、UI 形态不同；文本 Clip 100 条、其余 102 条。绝不泛化为全面性能胜出或速度倍数。数据在 `promotion/performance/competitors-20260908/`，表在 `promotion/COMPETITOR-RESULTS.md`。

早期采样的 proc rusage CPU 时间在本机为 mach ticks；以 125/3 校正并与 ps TIME 对照。正式 samples.json/CSV 已校正且有元数据，build 下原 JSONL 部分早期 CPU 未校正，不能直接拿来展示。

Deck 原历史曾移入 gitignored build 中完整保存，用临时库测接收。600ms 文本流 + 20 图片首次仅收 62+16，补发后66+18；最后停应用按现有表结构补齐临时库为100+20（图片200px预览），重启后台23.5MiB、0.014%单核，但未打开图片面板，不能与其他应用浏览后排名。**已执行 restore-deck.py 恢复原目录并重启正常 Deck，Clip 也恢复正常库，lsof 核验通过。剪贴板已恢复图片测试前的值。** 临时库在 build/competitor-benchmark/deck-test-*，恢复标记 DECK-RESTORED.txt。不要再次执行旧的原库搬走步骤覆盖保留物。

Paste 6.6.10、CleanClip 2.4.7 为 MacKed 包，下载摘要/签名已记；首次启动返回取消，随后应用出现在 ~/.Trash。CleanClip 系统评估拒绝。尚无有效运行数据，已问用户是否手动点了移到废纸篓，未收到答案。PastePal 由用户完成激活，当前可运行。

Deck 菜单栏窗口无法由当前 CUA 读取；已请求用户展开面板。读到的用户 app_launch 是 Ctrl+Cmd+Shift+V（区别于禁止的 Cmd+Shift+V），尝试仍未展开。不要反复猜快捷键。

网站现有产品页/51秒演示仍200。新增公开GitHub链接已写 products.yaml，但全量 gen_site/deploy 在资产枚举处失败：~/Dev/jobs/archive、updates 无catalog。日志 build/competitor-benchmark/site-deploy.log，没有部署变更；该SSOT改动尚未提交。还需解决该发布阻断并核验新内容。目标仍包括全部测试与推广，不能因已发三款视频就标完成；仍缺两款运行、Deck界面、对等速度/重复轮次。

用户要求所有自研 app：功能完成后极致降低 RAM / CPU、提升响应速度，保持键盘友好；形成“竞品对比 → 实测优化 → 产品卖点 → 实机视频 → GitHub / 个人网站推广”的可复用流程。

已写入共享 HARNESS，app skill 引用 `references/product-loop.md`；已同步并检查无漂移，cc-home commit d78824e。

Clip build 26 的功能与优化交付见 `keyboard-memory.md`，本轮没有更改生产代码。文档与素材 commit 3952393 已推送。GitHub 介绍/homepage 已更新，但仓库仍 PRIVATE，未发公开安装包。

公开产品页：https://app-mac-clips.tianli.cyou/ ，目录详情：https://apps.tianli.cyou/p/clipbook.html 。51 秒视频：https://apps.tianli.cyou/assets/mac/clipbook/demo.mp4 。Safari 实际播放检查到 20 秒 / 总长 51 秒，下载文件与 staging SHA256 相同。SSOT configs commit eb6951a；共用生成器增加 demo / comparison 支持，stations commit 77c6c4e。都已推送。

测量口径与差异在 `promotion/COMPARISON.md`，证据在 `promotion/performance/`。不要宣传全面胜过 Deck：当前 CPU 观察 Clip 更高，两个 app 状态不一致；速度尚未对等计时。图片浏览减少 57% 指 Clip 自己优化前后。Deck 的 AI / 同步 / 插件仍未替代。

视频由 build 26 真实窗口录制，13 条隔离虚构数据，原片与中间文件保留在 gitignored `promotion/video/`。`prepare_demo.py` 和 `render_video.py` 保留复用；公开只用审核后的 `clip-demo.mp4` 与 `clip-editor.png`。已退出演示实例并恢复生产 Clip，lsof 验证打开正常 Application Support/Clipbook 数据库。

唯一待用户选择：GitHub 对外只发介绍/安装包、源码保持私有，还是审查脱敏后公开源码。已通过异步问题询问，未收到答复；不把默认选项视为授权。现有公开网页暂无安装包的提示属实。用户选定后继续实际发行（检查签名、公证、可独立构建与公开内容），不要直接将私有历史改公开。

stations 工作区存在其他会话修改；本轮仅提交 apps-site/gen_site.py，其他改动保留。部署日志 `/tmp/clip-product-deploy-20260908.log`。源代码 build 26 的实测不会因后续文档 commit 自动变成新二进制版本。
