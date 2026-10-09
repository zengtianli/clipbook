# Clip 在 Mac mini 上启动即被系统杀掉 · 2026-10-09

## 现象

两台 `/Applications/Clip.app` 同为 1.2.1 (110)、同一份包，Air 正常，Mini 上任何入口（窗口、`clip version`）都立刻退出 137。系统日志原话：`Provisioning profile does not allow this device`，随后 `Disallowing cyou.tianli.clipbook because no eligible provisioning profiles found`。

## 原因

CloudKit 版用 Apple Development 签名加 Xcode 自动管理的描述文件（`cloud-project.yml` 的 `CODE_SIGN_STYLE: Automatic`，`build-cloud.sh` 带 `-allowProvisioningUpdates`）。这类描述文件带设备清单，清单在生成那一刻定死：包内那份 `Mac Team Provisioning Profile: cyou.tianli.clipbook` 生成于 2026-09-08，当时账号里只有 Air，Mini 是之后才登记的。Xcode 只要本机缓存里还有一份没过期、含本机的描述文件就一直复用，不会因为账号里多了设备而重出。

`codesign --verify --deep --strict` 在 Mini 上照样退出 0：它只验签名完整，不验设备是否在清单里。所以“两台同版本、签名验证通过”不等于“两台都能启动”。

## 做法

1. 新 Mac 先登记进开发者账号设备表（本次 Mini 已登记且启用）。
2. 在签名机（Air）把缓存里属于 `cyou.tianli.clipbook` 的旧描述文件移进废纸篓。位置是 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`（旧版 Xcode 在 `~/Library/MobileDevice/Provisioning Profiles/`），用 `security cms -D -i <文件>` 读 `Entitlements` 里的 application-identifier 判断，只移这一个 bundle id 的。
3. 先做一个真实提交（构建号是提交数，同版本号不许换内容），再走 `./build.sh`；构建脚本不用改。
4. 装机前核包内清单：`security cms -D -i <包>/Contents/embedded.provisionprofile` 的 `ProvisionedDevices` 必须同时含每台要装的 Mac 的 Provisioning UDID（`system_profiler SPHardwareDataType` 读）。缺任何一台就不装、不发更新源。
5. 每台装完实际启动一次：`clip version` 退出 0，`clip start` 后 `clip status --json` 读到运行中。

## 以后

再添一台 Mac，或描述文件到期（一年）重出之后，都按上面 4、5 两步核一遍。本次执行的实际读数在 `~/mac-pair/tasks/own-app-same-version-20261009/output/revendor/clip-mini-launch.md`。
