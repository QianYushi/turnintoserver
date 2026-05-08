# turnintoserver

<p>
  <img src="icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

`turnintoserver` is a native macOS menu bar app that keeps a plugged-in MacBook available as a small local server while making the built-in display go dark when the lid is closed.

`turnintoserver` 是一个原生 macOS 菜单栏应用，用来让接入电源的 MacBook 在合盖时继续作为本地小服务器运行，同时让内建屏幕变暗/熄屏。

It is designed for personal workflows such as LAN services, SSH access, remote desktop sessions, development servers, media tools, and other local tasks that should stay reachable while the Mac is connected to power.

它适合个人使用场景，例如局域网服务、SSH、远程桌面、开发服务器、媒体工具，以及其他希望 Mac 接电源后持续可访问的本地任务。

The core idea is simple: keep the machine awake, but do not leave the MacBook display lit behind a closed lid.

它的核心目标很简单：电脑继续运行，但合盖后的 MacBook 内建屏幕不要继续亮着。

## Highlights / 功能亮点

- Built for closed-lid server use: keeps local services reachable while turning the built-in display dark.
- 专为合盖服务器场景设计：保持本地服务可访问，同时让内建屏幕变暗。
- Menu bar only: no Dock icon and no main window.
- 纯菜单栏应用：不显示 Dock 图标，也没有主窗口。
- Power-aware Server Mode: automatically pauses on battery unless battery mode is explicitly allowed.
- 电源感知的 Server Mode：默认只在接电源时运行，切到电池后自动暂停，除非手动允许电池模式。
- Lid-aware display handling: reduces the built-in display brightness when the lid is closed, helping avoid unnecessary panel wear, image retention risk, and heat.
- 感知合盖状态：合盖后调暗内建显示器亮度，帮助降低长期亮屏带来的屏幕老化、残影和发热风险。
- Preserves user sleep settings: toggles only `pmset disablesleep`, instead of rewriting sleep or display-sleep timers.
- 保留用户原有睡眠设置：只切换 `pmset disablesleep`，不改写系统睡眠或显示器睡眠时间。
- Uses a scoped `caffeinate` process while Server Mode is active.
- Server Mode 开启时使用受控的 `caffeinate` 进程维持唤醒。
- Supports launch at login through `SMAppService`.
- 通过 `SMAppService` 支持开机自动启动。
- Built as a native Swift and SwiftUI macOS app.
- 使用 Swift 和 SwiftUI 构建的原生 macOS 应用。

## Why This Exists / 为什么需要它

Many keep-awake utilities are good at preventing sleep, but closed-lid server use has a second problem: the computer should keep running while the built-in display should not remain lit behind the lid.

很多防睡眠工具可以让电脑保持运行，但合盖服务器场景还有另一个问题：电脑要继续运行，内建屏幕却不应该在合盖后继续亮着。

`turnintoserver` treats display care as part of Server Mode. When the lid closes, it targets the built-in display and reduces its brightness, instead of sending a global display-sleep command that could also blank external monitors.

`turnintoserver` 把屏幕保护作为 Server Mode 的一部分。合盖后，它只针对内建显示器调暗亮度，而不是发送全局显示器睡眠命令，避免误伤外接显示器。

This makes it different from generic sleep-prevention tools: it is built around the exact workflow of using a MacBook as a closed-lid local server while reducing unnecessary stress on the built-in panel.

这正是它和普通防睡眠工具的区别：它围绕“MacBook 合盖当本地服务器使用”这个具体工作流设计，同时尽量降低内建屏幕不必要的损耗。

## Requirements / 系统要求

- macOS 14.0 or later.
- macOS 14.0 或更高版本。
- A Mac supported by the configured Xcode target.
- 支持当前 Xcode target 的 Mac。
- Administrator approval the first time Server Mode needs permission to run `pmset disablesleep`.
- 第一次启用 Server Mode 时需要管理员授权，以允许应用执行 `pmset disablesleep`。

## Download And Install / 下载与安装

Download the latest `turnintoserver.dmg` from the GitHub Releases page.

请从 GitHub Releases 页面下载最新的 `turnintoserver.dmg`。

1. Open the DMG.
2. Drag `turnintoserver.app` into Applications, or run it from your preferred local app folder.
3. Launch `turnintoserver`.
4. Use the menu bar item to enable Server Mode.

1. 打开 DMG。
2. 将 `turnintoserver.app` 拖入“应用程序”，也可以放在你偏好的本地应用目录中运行。
3. 启动 `turnintoserver`。
4. 在菜单栏中开启 Server Mode。

This app is not sandboxed and is not distributed through the Mac App Store.

本应用未启用 App Sandbox，也不通过 Mac App Store 分发。

## How It Works / 工作原理

When Server Mode is enabled, the app:

开启 Server Mode 后，应用会：

- Runs `pmset disablesleep 1` with administrator-approved privileges.
- 使用管理员授权后的权限执行 `pmset disablesleep 1`。
- Starts `caffeinate -i -m`, and adds `-s` while connected to power.
- 启动 `caffeinate -i -m`，接电源时额外添加 `-s`。
- Watches power-source changes through IOKit.
- 通过 IOKit 监听电源来源变化。
- Watches lid state with `ioreg`.
- 通过 `ioreg` 检测合盖状态。
- Dims the built-in display when the lid is closed, while avoiding global display-sleep commands.
- 合盖时调暗内建显示器，同时避免使用全局显示器睡眠命令。
- Restores sleep behavior with `pmset disablesleep 0` when Server Mode is disabled, paused, or the app exits.
- 在关闭、暂停 Server Mode 或退出应用时，通过 `pmset disablesleep 0` 恢复系统睡眠行为。

If battery mode is disabled and the Mac switches to battery power, `turnintoserver` pauses Server Mode and automatically resumes after power is reconnected.

如果未允许电池模式，Mac 切到电池供电后，`turnintoserver` 会暂停 Server Mode，并在重新接入电源后自动恢复。

## Permissions / 权限说明

`turnintoserver` may ask for administrator approval the first time it needs to control `pmset disablesleep`. The permission is scoped to the following commands:

`turnintoserver` 第一次控制 `pmset disablesleep` 时可能会请求管理员授权。授权范围限制在以下命令：

```text
/usr/bin/pmset disablesleep 0
/usr/bin/pmset disablesleep 1
```

The app uses this to avoid repeated password prompts while still keeping the elevated command surface narrow.

这样可以避免每次切换 Server Mode 都重复弹出密码窗口，同时将提权命令范围控制得尽量小。

## Safety / 安全提示

Do not keep a MacBook running closed inside a bag, drawer, or any poorly ventilated space. Server Mode is intended for plugged-in, ventilated desktop use. Turning the built-in display dark helps reduce unnecessary panel stress, but it does not replace proper ventilation.

不要让合盖运行中的 MacBook 放在包里、抽屉里或任何通风不良的位置。Server Mode 适合接电源、通风良好的桌面环境。让内建屏幕变暗可以减少不必要的屏幕压力，但不能替代良好散热。

## Build From Source / 从源码构建

Open the project in Xcode, or build from the command line:

可以用 Xcode 打开工程，也可以通过命令行构建：

```bash
./script/build_and_run.sh --verify
```

The build script places the runnable app at:

构建脚本会把可运行的应用放在：

```text
turnintoserver.app
```

For a Developer ID signed Release build:

如需构建 Developer ID 签名的 Release 版本：

```bash
./script/build_and_run.sh --release-verify
```

The Release path expects the configured Developer ID certificate to be available in the local Keychain.

Release 构建需要本机钥匙串中已有配置好的 Developer ID 证书。

## Notarized Distribution / 公证分发

After creating a Release build, notarize and staple the app:

创建 Release 构建后，对应用进行公证并 staple：

```bash
./script/notarize_release.sh
```

Create a drag-and-drop DMG:

生成拖拽安装风格的 DMG：

```bash
./script/make_dmg.sh
./script/notarize_dmg.sh
```

The final `turnintoserver.dmg` should be uploaded to GitHub Releases as a release asset. It should not be committed to the repository.

最终的 `turnintoserver.dmg` 应上传到 GitHub Releases 作为 release asset，不应提交进 git 仓库。

## Maintainer Release Checklist / 维护者发布清单

1. Update the app version and build number in Xcode.
2. Build and verify the Release app.
3. Notarize and staple the app.
4. Build and notarize the DMG.
5. Validate the DMG.
6. Create a GitHub release tag, for example `v1.0.0`.
7. Upload `turnintoserver.dmg` to that GitHub Release.

1. 在 Xcode 中更新应用版本号和 build number。
2. 构建并验证 Release 应用。
3. 对应用进行公证并 staple。
4. 生成并公证 DMG。
5. 验证 DMG。
6. 创建 GitHub release tag，例如 `v1.0.0`。
7. 将 `turnintoserver.dmg` 上传到该 GitHub Release。

Recommended commands:

推荐命令：

```bash
./script/build_and_run.sh --release-verify
./script/notarize_release.sh
./script/make_dmg.sh
./script/notarize_dmg.sh
spctl -a -vv -t open --context context:primary-signature turnintoserver.dmg
xcrun stapler validate turnintoserver.dmg
```

## Repository Hygiene / 仓库维护

Local agent context, build outputs, generated app bundles, notarization ZIP files, and DMG files are intentionally ignored by git.

本地 agent 上下文、构建产物、生成的 `.app`、公证用 zip 和 DMG 文件都已配置为不进入 git。

The repository should contain source code, assets, Xcode project files, scripts, and documentation. Release binaries belong in GitHub Releases.

仓库中应只保留源码、资源、Xcode 工程文件、脚本和文档。二进制发布产物应放在 GitHub Releases。

## License / 许可证

No open-source license has been added yet. Add a `LICENSE` file before publishing if you want other people to reuse, modify, or redistribute the code.

当前还没有添加开源许可证。如果希望其他人复用、修改或再分发代码，请在公开发布前添加 `LICENSE` 文件。
