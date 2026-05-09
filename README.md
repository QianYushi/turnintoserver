# turnintoserver

[English](README.en.md)

<p>
  <img src="icon.png" alt="turnintoserver app icon" width="96" height="96">
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
- `开机自动启动`：登录后自动打开 app。
- `退出`：退出前恢复系统默认睡眠行为。

一般情况下，打开 Server Mode，然后合盖就可以了。

如果没有打开电池模式，拔掉电源后它会暂停；再次接上电源后会自动恢复。

## 关于屏幕

`turnintoserver` 不只是让 Mac 不睡。

它更在意合盖后的那块内建屏幕。合盖时，它会尽量只把 MacBook 自己的屏幕亮度降到 0，而不是把所有显示器都关掉。这样外接显示器不会被它主动熄灭，合盖里面那块屏幕也不再发光。

## 注意

不要把合盖运行中的 MacBook 放进包里、抽屉里，或者其他不通风的位置。

它适合接电源、放桌面、有正常散热空间的使用方式。内建屏亮度降到 0 后，可以减少那块屏幕的发光、发热和亮屏损耗，但不能替代散热。

## 系统要求

- macOS 14 或更高版本。
- 推荐接电源使用。

## 说明

`turnintoserver` 不是 Mac App Store 应用，也没有启用 App Sandbox。
