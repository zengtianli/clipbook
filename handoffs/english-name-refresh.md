# Clips 命名与质量更新

产品名来自 catalog.yaml，经构建注入 CFBundleDisplayName，UI读取Bundle。中英文README统一英文名；BundleID、数据路径、仓目录与remote保留。图标沿用字形，去TL角标。

生产selftest通过；本地HTTP忽略Range夹具证明256KiB后返回，旧实现同测试失败。数据路径/URL scheme不变。

构建复用 `/Users/tianli/Dev/tools/dev/lib/tools/macapp/` 的 Xcode 选择器、CodingKey检查、图标工厂。安装脚本不强杀运行实例。
