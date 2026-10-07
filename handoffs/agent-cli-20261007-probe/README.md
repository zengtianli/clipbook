# 探针：配置同步开着时，连改两次的设置被写回前一次的值

对象是共用层 `swift-shared/AppConfiguration.swift`（sha256 66d1b04072dbcbcb…，Clip 的 `Sources/Shared/AppConfiguration.swift` 与它逐字节相同）。只是证据，不参与 Clip 的构建；共用层没有改。说明见 `../agent-cli-20261006.md` 第四轮。

复现（隔离的支持目录与云端目录、一次性偏好域，不碰任何产品的真实配置）：

```bash
mkdir /tmp/probe && cd /tmp/probe
cp ~/Dev/tools/dev/lib/tools/macapp/swift-shared/AppConfiguration.swift .
cp ~/Apps/clip/mac/handoffs/agent-cli-20261007-probe/reconcile-race-probe.swift.txt main.swift
xcrun swiftc -O -target arm64-apple-macosx14.0 main.swift AppConfiguration.swift -o probe
./probe 30        # 每档 30 轮，约两分钟
rm -f ~/Library/Preferences/cyou.tianli.probe.reconcile-race.*.plist   # 偏好守护进程留下的空壳
```

- `run-b-30-rounds.log`：这份源码的输出。
- `run-a-40-rounds.log`：同一探针较早的一版（只有主循环，五档间隔，每档 40 轮）的输出。
