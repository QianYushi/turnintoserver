# turnintoserver

[中文](README.md)

<p>
  <img src="icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

Use a MacBook as a closed-lid server, while keeping the built-in display dark.

I built this app because most keep-awake tools only solve the sleep problem. What I actually wanted was slightly different: keep SSH, remote desktop, local services, and development servers running after closing the lid, without leaving the MacBook display lit inside.

`turnintoserver` is made for that workflow.

## What It Does

- Keeps the Mac running after the lid is closed.
- Dims the built-in MacBook display when the lid closes.
- Does not intentionally turn off external monitors.
- Enables Server Mode while connected to power.
- Pauses automatically on battery, then resumes after power is reconnected.
- Can optionally keep running on battery for temporary uninterrupted sessions.
- Supports launch at login.

## When To Use It

- SSH into a closed-lid Mac.
- Run development servers on your local network.
- Connect to a closed-lid MacBook with remote desktop.
- Keep sync tools, downloads, media services, or automation tasks running.
- Use a MacBook as a small desktop server for a while.

## Install

Download the latest version from Releases:

https://github.com/QianYushi/turnintoserver/releases/latest

After downloading `turnintoserver.dmg`:

1. Open the DMG.
2. Drag `turnintoserver.app` into Applications.
3. Launch `turnintoserver`.
4. Enable Server Mode from the menu bar.

The first time you enable it, macOS may ask for an administrator password. The app needs permission to let macOS keep running with the lid closed.

## How To Use

The app lives only in the menu bar.

The menu has a few simple controls:

- `Start Server Mode`: keeps the Mac running while connected to power.
- `Allow Server Mode on Battery`: keeps running after power is unplugged. Off by default.
- `Launch at Login`: starts the app after login.
- `Quit`: restores the default sleep behavior before quitting.

For normal use, turn on Server Mode and close the lid.

If battery mode is off, unplugging power pauses Server Mode. Plugging power back in resumes it automatically.

## Display Care

`turnintoserver` is not just about preventing sleep. The point is to keep the Mac running while also handling the built-in display after the lid closes.

When the lid is closed, the app tries to dim only the built-in MacBook display instead of sending a global display-off command. That means it does not intentionally blank external monitors, while the hidden built-in display does not need to stay lit.

## Safety

Do not keep a closed MacBook running inside a bag, drawer, or any poorly ventilated space.

This app is meant for plugged-in desktop use with normal airflow. Dimming the display can reduce unnecessary light and heat, but it does not replace cooling.

## Requirements

- macOS 14 or later.
- A MacBook connected to power is recommended.

## Note

`turnintoserver` is not a Mac App Store app and does not use App Sandbox. It is a small utility built around a personal closed-lid server workflow.
