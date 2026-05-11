# turnintoserver

[English](README.en.md) · [产品页面](https://qianyushi.github.io/turnintoserver/)

<p>
  <img src="https://qianyushi.github.io/turnintoserver/icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

合上盖子。  
Mac 继续工作。  
内建屏不再发光。

`turnintoserver` 是一个 macOS 菜单栏小工具。

给 MacBook 接上电源，打开 Server Mode，合盖后它还能继续跑 SSH、远程桌面、开发服务器和局域网服务。同时，它会尽量只把 MacBook 自己的内建屏幕亮度降到 0，避免那块看不见的屏幕继续发光。

我写它，是因为我想把 MacBook 临时当一台小服务器用。但普通防睡眠工具通常只管“不睡”，不太管合盖后屏幕还亮不亮。

## 主要功能

- 合盖后保持 Mac 运行。
- 合盖时把内建屏幕亮度降到 0。
- 不主动关闭外接显示器。
- 接电源时运行，切到电池后自动暂停。
- 接回电源后自动恢复。
- 可以手动允许电池模式。
- 电池模式下可通过 iMessage 或 Bark 提醒电量不足。
- 支持自定义全局快捷键。
- 支持开机自动启动。

## 适合这些情况

- 合盖后继续 SSH 到这台 Mac。
- 在局域网里跑开发服务器。
- 用远程桌面连接 MacBook。
- 让同步、下载、媒体服务继续跑。
- 临时把 MacBook 放桌面上当小服务器。

## 安装

下载最新版：

https://github.com/QianYushi/turnintoserver/releases/latest

然后：

1. 打开 `turnintoserver.dmg`。
2. 把 `turnintoserver.app` 拖到“应用程序”。
3. 启动 `turnintoserver`。
4. 在菜单栏里打开 Server Mode。

第一次开启时，macOS 可能会要求输入管理员密码。这是为了允许系统在合盖后继续运行。

## 使用

打开后，app 只会出现在菜单栏。

常用的就这几个：

- `启动 Server 模式`：开启后，接电源时合盖也会继续运行。
- `电池也允许 Server 模式`：断电后也继续运行。默认关闭。
- `推送低电量通知`：电池模式运行时，低于 50% 和 20% 会通过已配置通道提醒，右侧“设置”可配置 iMessage / Bark。
- `启用快捷键`：开启或关闭全局快捷键，右侧“设置”可录制两个快捷键。
- `开机自动启动`：登录后自动打开 app。
- `关于应用`：查看版本、开发者、GitHub 地址并检查更新。
- `退出`：退出前恢复系统默认睡眠行为。

一般情况下，打开 Server Mode，然后合盖就可以了。

如果没有打开电池模式，拔掉电源后它会暂停；再次接上电源后会自动恢复。

低电量提醒需要先在菜单中点击“推送低电量通知”右侧的“设置”，配置 iMessage 或 Bark，并测试成功后才能开启。只填写一个通道就只推送一个；两个都填写时会同时推送。iMessage 首次发送时，macOS 会询问是否允许 `turnintoserver` 控制 Messages，请选择允许。Bark 支持填写类似 `https://api.day.app/你的key` 的推送地址。

检查更新会直接下载新版 DMG，显示下载进度，准备好后可以点击“重新启动应用”完成替换安装。

## 关于屏幕

`turnintoserver` 不只是让 Mac 不睡。

它更在意合盖后的那块内建屏幕。合盖时，它会尽量只把 MacBook 自己的屏幕亮度降到 0，而不是把所有显示器都关掉。这样外接显示器不会被它主动熄灭，合盖里面那块屏幕也不再发光。

## 注意

不要把合盖运行中的 MacBook 放进包里、抽屉里，或者其他不通风的位置。

它适合接电源、放桌面、有正常散热空间的使用方式。内建屏亮度降到 0 后，可以减少那块屏幕的发光、发热和亮屏损耗，但不能替代散热。

## 系统要求

- Intel Mac：macOS 10.15 Catalina 或更高版本。
- Apple Silicon Mac：macOS 11 Big Sur 或更高版本。
- 推荐接电源使用。

## 说明

`turnintoserver` 不是 Mac App Store 应用，也没有启用 App Sandbox。
