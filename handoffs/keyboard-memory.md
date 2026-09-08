# 键盘导航与内存（2026-09-08）

用户要求：自建 app 都要键盘友好；本轮直接修 Clip 的方向键，并减轻运行内存。

卡片原来拿到 first responder 后只处理鼠标，导致方向键无动作。现由稳定的 GridKeyboard responder 接收导航，点击卡片把焦点交给它；方向键遵循实际列数，Shift 扩选，Home/End、Page Up/Down、Return 复制、Esc 清除、Tab 切换控件，选中项滚入视野。没有新增默认全局绑定。收藏夹图标/颜色改为可访问按钮。

隐藏主窗卸载 HostingView、清理图标与图片缓存、停止界面查询，只保留当前草稿和选中记录供已配置的全局复制使用。后台仍然记录；菜单计数打开时单独查询；恢复时重载。设置窗关闭时释放。ImageIO 按目标尺寸解码（卡片 512px / 详情 1600px），NSCache 设置 12 MiB 成本限制和 48 条数量限制；复制、导出仍读原件。

同一份生产库与 blobs 的隔离副本、相同 Release 编译器、同一 `tests/MemoryProbe.swift` 流程：

| 阶段（phys_footprint，MiB） | 原版 9c340bf | 改后 |
|---|---:|---:|
| 主窗口 | 51.4 | 51.3 |
| 主窗和设置 | 69.4 | 70.3 |
| 两窗关闭 | 69.2 | 71.0 |
| 图片首页 | 129.6 | 106.3 |
| 图片翻页 | 275.5 | 117.3 |
| 图片翻页后关闭 | 275.5 | 106.7 |
| 重开 | 277.3 | 125.3 |

改善在图片浏览后的增长与保留：翻页约 -57%，关闭后约 -61%。基础开窗并未明显变小；释放对象也不意味着系统立刻归还所有堆页，不承诺后台固定 20 MB。尝试 allocator pressure relief 未带来有效收益，最终未采用。后加的 Tab 分发及菜单计数不在该无按键图片流程中执行。

生产 `--selftest` 增加方向键/扩选/边界、隐藏恢复、图片缩放与原图保真回归。打包二进制 `--keyboard-window-test` 在隔离目录/偏好下驱动真实 NSWindow 事件分发，7 项通过：初始焦点、Tab、方向键、文本光标、真实未保存草稿跨 HostingView 重建、HostingView 释放、选择恢复。它不发送系统全局按键，不碰 KM 的 ⌘⇧V。

复验：

```bash
cd /Users/tianli/Apps/mac/clipbook
CLIPBOOK_HOME="$PWD/build/keyboard-window-fixture" CLIPBOOK_PREFERENCES_SUITE=Clip.KeyboardWindowTest build/Clipbook.app/Contents/MacOS/Clipbook --keyboard-window-test
```

内存诊断入口 `bash tests/test-memory-probe.sh current` 要先备好 `build/memory-fixture`（数据库一致性副本和 blobs）；baseline 另需 `build/memory-baseline/Sources` 源码快照。两者都使用隔离偏好，停止监听，不向生产库写入。
