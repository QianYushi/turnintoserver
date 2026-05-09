# turnintoserver

[中文](README.md)

<p>
  <img src="icon.png" alt="turnintoserver app icon" width="96" height="96">
</p>

Close the lid.  
Keep the Mac running.  
Turn the built-in display to zero brightness.

`turnintoserver` is a small macOS menu bar utility.

Plug in your MacBook, turn on Server Mode, and close the lid. SSH, remote desktop, development servers, and local network services can keep running. At the same time, it tries to set only the built-in MacBook display to zero brightness, so the screen hidden behind the lid no longer emits light.

I built it because I wanted to use a MacBook as a small temporary server. Most keep-awake apps handle the sleep part, but not the closed-lid display part.

## Main Features

- Keeps the Mac running after the lid is closed.
- Sets the built-in display to zero brightness when the lid closes.
- Does not intentionally turn off external monitors.
- Runs on power, pauses automatically on battery.
- Resumes automatically when power is connected again.
- Can optionally keep running on battery.
- Can send low battery iMessage alerts while running on battery.
- Supports launch at login.

## Good For

- SSH into a closed-lid Mac.
- Run development servers on your local network.
- Connect to a MacBook with remote desktop.
- Keep sync, download, or media services running.
- Use a MacBook as a small desktop server for a while.

## Install

Download the latest version:

https://github.com/QianYushi/turnintoserver/releases/latest

Then:

1. Open `turnintoserver.dmg`.
2. Drag `turnintoserver.app` into Applications.
3. Launch `turnintoserver`.
4. Turn on Server Mode from the menu bar.

The first time you enable it, macOS may ask for an administrator password. This allows the system to keep running after the lid is closed.

## Use

The app lives only in the menu bar.

The main controls are:

- `Start Server Mode`: keeps the Mac running while connected to power.
- `Allow Server Mode on Battery`: keeps running after power is unplugged. Off by default.
- `Low Battery iMessage Alerts`: sends iMessage alerts below 50% and 20% while running on battery.
- `Open at Login`: opens the app after login.
- `About`: shows the version, checks for updates, configures the iMessage recipient, and sends a test message.
- `Quit`: restores the default sleep behavior before quitting.

For normal use, turn on Server Mode and close the lid.

If battery mode is off, unplugging power pauses Server Mode. Plugging power back in resumes it automatically.

Low battery iMessage alerts need a recipient phone number or Apple ID email in About. Use Send Test to confirm it works. The first send may ask macOS for permission to let `turnintoserver` control Messages; allow it. This feature depends on Messages being signed in with a working iMessage account on the Mac.

## About The Display

`turnintoserver` is not only about preventing sleep.

It also cares about the built-in display after the lid is closed. When the lid closes, it tries to set only the MacBook display to zero brightness, instead of turning off every display. External monitors are not intentionally blanked, and the hidden built-in screen no longer emits light.

## Safety

Do not keep a closed MacBook running inside a bag, drawer, or any poorly ventilated space.

Use it plugged in, on a desk, with normal airflow. Setting the built-in display to zero brightness reduces unnecessary light, heat, and screen wear from that panel, but it is not a replacement for cooling.

## Requirements

- Intel Mac: macOS 10.15 Catalina or later.
- Apple Silicon Mac: macOS 11 Big Sur or later.
- Plugged-in use is recommended.

## Note

`turnintoserver` is not a Mac App Store app and does not use App Sandbox.
