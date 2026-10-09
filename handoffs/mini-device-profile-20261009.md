# Clip 的签名与描述文件：现行做法是 Developer ID · 2026-10-10 改写

本文件原来记的是“把 Mac mini 加进描述文件的设备清单”。那个方向错了，已废弃：本人 2026-10-09 纠正，Clip 是给所有人用的产品，装进 /Applications 或发到更新源的包必须任何一台 Mac 拿到都能直接运行。下面是现行做法，末尾留着废弃做法为什么不行。

## 现行做法

- 签名身份 `Developer ID Application: tianli Zeng (B9LJH93LA4)`，hardened runtime，安全时间戳（`cloud-project.yml`：手动签名、`OTHER_CODE_SIGN_FLAGS: --timestamp`、`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`）。
- 描述文件用 Developer ID 直接分发那一种：账号里名为 `Clip Developer ID`，接口类型 `MAC_APP_DIRECT`，UUID `51f6ff8d-1c77-4799-a8de-40816f8f350c`，2026-10-10 用接口建，2044-10-04 到期。它带 iCloud 能力（容器 `iCloud.cyou.tianli.clip`，环境只有 `Production`，推送环境 `production`），`ProvisionsAllDevices` 为真，**没有 `ProvisionedDevices`**。`Cloud.entitlements` 的推送环境因此是 `production`。
- `scripts/developer-id-profile.py` 在构建前把它放到本机 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`：本机已有就不联网；没有则用 App Store Connect 接口密钥取回；账号里没有时建一次（绑定账号里有效的 Developer ID Application 证书）。`--check` 只读本机。密钥编号不打印。
- `build-cloud.sh`（`./build.sh` 调它）：先核本机有 Developer ID 身份（没有就退出 4，不退回别的签法）→ 取描述文件 → XcodeGen → Release 构建 → `--selftest` → 发行等级检查（共享的 `~/Dev/tools/dev/lib/tools/macapp/distribution_grade.py check --stage signed`，加本产品自己核的 CloudKit 容器、`Production` 环境、无设备清单、构建号等于提交数）→ 公证并装订（`distribution_grade.py notarize`）→ 装机 → 对装好的包再按 notarized 判据读一遍。
  - `--build-only`：停在检查之后。包已是 Developer ID 签名，未公证。四项固定验收用它。
  - `--install-only`：不重编，把这次提交 `--build-only` 留下的那份包公证、装订、装机。验收过的字节就是装机的字节；等公证时不占构建队列。
- 证书只在 Air 的登录钥匙串。纯 SSH 里 codesign 报 `errSecInternalComponent`，签名步骤放进 Air 登录会话（一次性 LaunchAgent）。公证和装订在纯 SSH 里能跑。
- 装机后发 `cloud` 更新源用装好的这一份；另一台 Mac 走 `clip update install --yes --json` 或取同一个 zip。两台都读：`spctl --assess --type execute --verbose=2` 是 `source=Notarized Developer ID`，`xcrun stapler validate` 通过，`security cms -D -i <包>/Contents/embedded.provisionprofile` 里没有 `ProvisionedDevices`。

## Xcode 自己出不了这份描述文件

2026-10-09 在 Air 实测：归档后 `xcodebuild -exportArchive`（`method: developer-id`，`signingStyle: automatic`，带 `-allowProvisioningUpdates` 和接口密钥）退出 70，原话：

```
error: exportArchive Cloud signing permission error
  You haven't been given access to cloud-managed distribution certificates. Please contact your team's Account Holder or an Admin to give you access.
error: exportArchive No profiles for 'cyou.tianli.clipbook' were found
  Xcode couldn't find any Developer ID provisioning profiles matching 'cyou.tianli.clipbook'.
```

带接口密钥时 Xcode 要用云端托管的分发证书去建托管描述文件，这把密钥没有那项权限，本机钥匙串里的 Developer ID 证书它不用。同一把密钥直接调接口 `POST /v1/profiles`（`MAC_APP_DIRECT`）是允许的，所以改为接口建、手动签名指定。共享的 `build-platforms.sh --only mac --distribution` 走的也是自动导出，遇到需要描述文件的 App（iCloud、钥匙串组）会撞同一个错，可以照这里的办法补。

## 已废弃：带设备清单的开发描述文件

2026-10-09 之前，CloudKit 版用 Apple Development 签名加 Xcode 自动管理的 `Mac Team Provisioning Profile: cyou.tianli.clipbook`。那种描述文件带设备清单，清单在生成那一刻定死：1.2.1 (110) 的清单只有 Air，Mini 上任何入口都立刻退出 137（系统日志 `Provisioning profile does not allow this device`），而 `codesign --verify --deep --strict` 照样退出 0。当晚第一轮的处理是让 Xcode 重出一份把 Mini 也列进去的描述文件，装成 1.2.1 (113)。两台是能跑了，第三台 Mac 仍然跑不了，`spctl` 也是 rejected。以后不许再用这套：不用 Apple Development 签装机包，不把“往清单里加设备”当修法，不需要把 Mac 登记进开发者账号。

留下的两条教训仍然有效：`codesign --verify` 只验签名完整，不代表这台机器能启动，装完每台实际跑一次 `clip version`；无人值守的 xcodebuild 看不到 Xcode 窗口里登录的账号（报 `No Accounts`）。

各轮实际读数：`~/mac-pair/tasks/own-app-same-version-20261009/output/grade/clip.md`（Developer ID 这一轮）、`output/revendor/clip-mini-launch.md`（已废弃的那一轮）。
