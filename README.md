# turnintoserver

[English](README.en.md)

<p>
  <img src="icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

把 MacBook 合盖当服务器用，同时让内建屏幕熄掉。

我做这个 app 是因为常见的防睡眠工具大多只管“不睡眠”。但我真正需要的是：合盖后服务继续跑，SSH、远程桌面、开发服务器不断线，同时 MacBook 自己的屏幕不要一直亮在里面。

`turnintoserver` 就是为这个场景做的。

## 它能做什么

- 合盖后让 Mac 继续运行。
- 合盖时调暗 MacBook 内建屏幕，避免长时间亮屏。
- 不主动熄灭外接显示器。
- 接电源时启用 Server Mode。
- 切到电池时自动暂停，接回电源后自动恢复。
- 可以手动允许电池模式，适合临时不断线。
- 支持开机自动启动。

## 适合什么场景

- 合盖后继续 SSH 到这台 Mac。
- 在局域网里跑开发服务器。
- 用远程桌面连接合盖的 MacBook。
- 让同步、下载、媒体服务或自动化任务继续跑。
- 临时把 MacBook 当一台小服务器放在桌面上。

## 安装

在 Releases 下载最新版：

https://github.com/QianYushi/turnintoserver/releases/latest

下载 `turnintoserver.dmg` 后：

1. 打开 DMG。
2. 把 `turnintoserver.app` 拖到“应用程序”。
3. 启动 `turnintoserver`。
4. 在菜单栏里开启 Server Mode。

第一次开启时，系统可能会要求输入管理员密码。这是因为 app 需要允许 macOS 在合盖时继续运行。

## 使用方法

打开 app 后，它只会出现在菜单栏。

菜单里有几个常用开关：

- `启动 Server 模式`：让 Mac 接电源时保持运行。
- `电池也允许 Server 模式`：断电后也继续保持运行，默认关闭。
- `开机自动启动`：登录后自动启动 app。
- `退出`：退出前会恢复系统默认睡眠行为。

正常使用时，只需要打开 Server Mode，然后合盖就可以了。

如果没有打开电池模式，拔掉电源后 app 会暂停 Server Mode；再次接上电源后会自动恢复。

## 屏幕保护

`turnintoserver` 的重点不是单纯防睡眠，而是合盖后让电脑继续运行，同时处理内建屏幕。

合盖时，它会尝试只调暗 MacBook 自己的屏幕，而不是发送全局熄屏命令。这样做的好处是：外接显示器不会被它主动关掉，而合盖里面那块屏幕也不需要长时间亮着。

## 注意事项

不要把合盖运行中的 MacBook 放进包里、抽屉里，或者任何不通风的位置。

这个 app 适合接电源、放在桌面、有正常散热空间的使用方式。屏幕变暗能减少不必要的亮屏和发热，但不能替代散热。

## 系统要求

- macOS 14 或更高版本。
- MacBook 推荐接电源使用。

## 说明

`turnintoserver` 不是 Mac App Store 应用，也没有启用 App Sandbox。它是一个自用场景出发的小工具。
