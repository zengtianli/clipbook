# Clip 官网下载改用 GitHub Release · 2026-10-11

Task ID：`lintel-github-release-downloads-20261011`。执行开始：15:32:30（上海）。总预算 30 分钟，范围为本仓站点生成器、必要回归、正式重建 `build/site`、只读 Lintel 静态自查、限定提交与交接；不部署、不 push、不改 App 版本或 App 内渠道、不构建/安装 App、不重录素材。沿 Chapter 的 `--pid 27228 --session chapter-task:8553c354d35649bbbd0fd6df78b95f54` check 原写入声明，不释放声明。

已加载所属 CLAUDE；入场其他会话有 project.yaml/perf 改动，站点生成器和模板未改。主会话负责共享下载登记，本轮仅通过只读 `apps-portal show clipbook --json` 取得 download/source/homepage_bundle，未修改 configs、apps-portal、Lintel 或共享源码。

公开资产：[Clip-1.2.1-local-arm64.zip](https://github.com/zengtianli/clipbook/releases/download/v1.2.1/Clip-1.2.1-local-arm64.zip)。GitHub API `repos/zengtianli/clipbook/releases/tags/v1.2.1` 返回该资产大小 2083786 字节、digest `sha256:0257b371e5da46adf85111d687643a50f2605ad9e9485c2d7d962f6f7c147d47`，均与本地发行单一源 `build/local-release/release.json` 及 ZIP 实际字节一致。仍为 1.2.1 (78) local/arm64，iCloud=false。

改动：生成器用只读门户 CLI 获取 GitHub 资产，并在删除旧输出前校验产品、源码仓、版本、文件名及 HTTPS GitHub Release 路径；停止向站点复制 ZIP。版本、大小、SHA、资源数据继续从原发行/实测证据派生；保留校验文件、版本信息、原演示视频及教程下载。本地发行目录和原 ZIP 保留。结果与耗时见下方。

## 已完成与耗时

截至 15:38:32，本仓实现、原入口构建、自查及阻挡定位耗时 361.4 秒（约 6 分钟）；未耗满 30 分钟扩查旧欠项。

源码提交：`254284785ba55ddcb78f35313c0058a44d75eb25`，仅 `scripts/build-site.py`，25 行新增、2 行删除；未 push。共享登记在本轮由资产直链变成了明确的 `v1.2.1` 发布页。生成器同时接受已登记的同版本发布页或同版本资产，统一输出本产品已验证的 ZIP 直链；拒绝错版本、错仓库、站内路径、非 HTTPS、附加参数、错文件名和不固定版本的 latest。未改共享登记。

- GitHub 实际 ZIP 下载并算 SHA：4.265 秒；2083786 字节、SHA `0257b371e5da46adf85111d687643a50f2605ad9e9485c2d7d962f6f7c147d47`，与 GitHub API digest、本地 release.json、原 ZIP 完全一致。
- 生产函数回归：资产/明确版本发布页均输出同一资产；8 种错误登记被拒，错误版本不能删除或替换旧站点输出。通过。
- 正式重建：`cd /Users/tianli/Apps/clip/mac && /Users/tianli/Dev/.venv/bin/python -B scripts/build-site.py`，退出 0，1.209 秒。`-B` 仅避免在共享依赖目录生成 bytecode；仍是登记的原构建入口。
- 构建目录：`/Users/tianli/Apps/clip/mac/build/site`。清单 22 个文件（不含清单本身），逐文件 SHA 与实际目录完全一致。3 个安装包按钮均为上述 GitHub ZIP 直链，无站内安装包或备用下载。
- 包目录无 `.zip/.dmg/.pkg/.app`；`downloads/` 只剩从原发行 SHA 派生的 `SHA256SUMS.txt`。原 `build/local-release/Clip-1.2.1-local-arm64.zip` 保留且 SHA/大小未变。release.json 未变，演示/教程 MP4、字幕及截图逐字节仍是原素材。
- 指定静态自查耗时约 3.084 秒（输出文件创建至最终写入），CLI 退出 0 但 **ready=false，10 个 error、4 个字幕 warning**，不能按退出码伪报通过。

## 静态检查的共享阻挡

```sh
/Users/tianli/Dev/.venv/bin/python /Users/tianli/Apps/lintel/engine/lintel.py site check --site apps --product clipbook --bundle /Users/tianli/Apps/clip/mac/build/site --json
```

完整原始结果：[github-downloads-20261011-check.json](github-downloads-20261011-check.json)。原日志无 stderr；检查结果的 `homepage` 是 **`https://app-ios-clip.tianli.cyou/`**，实际门户 `show clipbook` 与本仓 canonical 均为 **`https://app-mac-clips.tianli.cyou/`**。只读检查器 `check_bundle` 先选产品族里第一个 public 行，用其首页/政策/实测作为当前产品上下文。因此当前自查混入 iOS 上下文；本轮不改共享检查器，也不把 Mac 主页、隐私政策或原实测改成 iOS 来通关。

全部错误：

- `resources.metric.download` / `.installed` / `.memory` / `.cpu` / `.speed`：资源模块中的各数字必须与当前原始实测及共享渲染器完全一致。
- `resources.metrics`：资源模块的五项公开数字必须齐全；存在当前实测时还必须与共享渲染器逐字一致。
- `resources.context`：资源模块的实测版本、设备/环境或测量日期与原始证据不一致。
- `metadata.canonical_target`：canonical 必须唯一并指向本产品真实 HTTPS 主页。
- `policy.private_source`：源码私有政策与页面源码入口冲突。
- `package.integrity`：3 个真实 GitHub ZIP 链接均被原规则拒绝为“链接不能映射到同源站点产物”。此规则与本轮明确要求移除站内安装包镜像直接冲突，需要主会话在其共享责任边界处理。本仓不复制 ZIP 或隐藏真实链接来绕过。

4 个 warning 为 `video.1.captions_default` 至 `video.4.captions_default`：中文字幕未声明默认启用，需实际播放确认字幕显示。原素材未改，本轮只做静态检查，未重录或新增取证/发布脚本。

本仓修改、GitHub 资产/SHA 验证、正式构建及目录无镜像检查均已完成；剩余为上述共享静态闸两类问题（产品族上下文、GitHub 安装包来源认可）。主会话修复其原入口后重跑同一条只读 check，再统一冻结发布即可，不能把本次结果称为 ready。

**本轮未发布，等待主会话统一冻结与部署。**
