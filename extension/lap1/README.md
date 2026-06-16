# Lap Guard Laptop Blocker

This folder is separate from the Chrome extension. It is the system-wide Windows blocker for the entire laptop.

## What it does

- Runs as a Windows app that edits the hosts file.
- Blocks a default gaming and game-download list across the whole machine.
- Uses the credentials:
  - Username: `AJ_encoded`
  - Password: `19782004`
- Supports pause durations of 2, 5, 10, 15, 25, 35, 50, and 60 minutes.
- Can auto-start at login through a scheduled task.
- Includes a local HTML disable page served by the web dashboard.

## Files

- `lap.ps1`: main desktop app and blocker.
- `start-lap.ps1`: launches the desktop app and HTML dashboard together.
- `web.ps1`: local HTML dashboard for disabling, pausing, and re-enabling.
- `web/index.html`: the browser page served by the dashboard.
- `setup-startup.ps1`: registers or removes the Windows startup task.

## Setup

1. Open PowerShell as Administrator.
2. Run `setup-startup.ps1` from this folder to install the startup task.
3. Launch `lap.ps1` to open the app, or open `http://127.0.0.1:17820/` for the HTML disable page.

## Notes

- This is system-wide blocking, but it still uses the Windows hosts file rather than DNS server control.
- The Chrome extension remains in `extension/lap` and is separate from this laptop-wide app.
