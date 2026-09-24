# Clip 静音演示上线

目标页面：https://app-mac-clips.tianli.cyou/#demo

演示区顶部使用 38.6 秒、1920×1080、30fps 静音版，下方保留搜索、编辑保存、收藏复制三个原分段。新版静音成片与可编辑工程在 `docs/demo/ai-sample/`；配乐试验仅本地保留，不进入发布清单。

- 线上视频：https://app-mac-clips.tianli.cyou/media/clip-guide-0a6f43d83fa9.mp4
- SHA-256：`0a6f43d83fa967b04ba7738fa1bf31db2066bbca2223570e693dfbbd91246744`
- 发布入口：`python3 scripts/build-site.py`，再从 apps-portal/site 执行 `bash deploy.sh --products-only clipbook --dry-run`，核计划后 `--deploy --plan <plan.json>`。
- 本轮计划：`/Users/tianli/Apps/apps-portal/site/build/product-publish/20260924T022503Z-0c711e74/plan.json`。
- 回滚脚本：同计划目录的 `rollback.sh`；远端备份 `/var/backups/apps-products/20260924T022503Z-0c711e74`。
- 发布范围：仅 `/var/www/apps-products/mac/clips/`，未更新目录站或 nginx；23 个远端文件 SHA-256 验证通过。
- HTTPS 回读：HTML 与构建产物一致；新版视频下载哈希一致、仅视频轨、时长 38.6 秒；Range 请求返回 206。页面四个播放器引用完整。
- 浏览器实播未执行：Chrome 隔离接口不支持 `visible:false`，为避免抢占用户焦点，未创建可见标签页。

本次另修复 apps-portal 的单产品发布入口被无关 iOS 展示集合缺项阻断的问题。完整目录默认检查保留；产品准入、退役、域名、产物清单、隐私、备份与回滚检查保持，22 项相关测试通过。未修改正在维护的产品注册表。
