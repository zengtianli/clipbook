# 简化名称与设置入口

- 用户要求名称更简练、必须能设置；catalog 的 display_name 改为 Clip，安装名与界面沿用现有派生链。
- 侧栏底部常驻「设置…」，应用主菜单补「设置…」，工具栏设置按钮添加可访问标识。
- 复用原有设置页与 UserDefaults：暂停、纯文本、链接标题、保留数量/时长、忽略应用、登录启动等。
- 主窗口观察 AppSettings，暂停标记随设置变更刷新。
- build.sh --build-only 与生产 --selftest 通过；存在原有 AppModel Swift 并发警告。
- CUA 选择旧应用两次超时，getState 亦超时，无法核对旧窗口未保存编辑或完成点击/重启持久化验收。安装新版时保留旧进程，避免丢失未保存编辑；使用新版需先正常退出旧进程。
- 总部复用：xcode_env.sh 工具链选择、check_codingkeys.py 构建门；数据目录、bundle_id、URL scheme 保持兼容。
