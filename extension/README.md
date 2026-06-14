# Lap Guard Browser Extension

Load this folder in Chrome or Edge using **Load unpacked**.

The manifest is at the root of this folder, and the extension files live under `lap/`.

## What it does

- Blocks curated gaming and game-download websites.
- Also blocks broad gaming/download keywords in page URLs for wider coverage.
- Uses the credentials:
  - Username: `AJ_encoded`
  - Password: `19782004`
- Supports timed pauses of 2, 5, 10, 15, 25, 35, 50, and 60 minutes.
- Opens the dashboard with `Ctrl+Shift+L`.

## Folder layout

- `manifest.json`: root manifest that Chrome loads.
- `lap/`: the browser UI, service worker, options page, and styling.
