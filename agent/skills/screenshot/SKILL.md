---
name: screenshot
description: Locate and inspect the most recent macOS screenshot without requiring the user to drag a file into the terminal. Use when asked to inspect the latest screenshot.
---

# Latest Screenshot

Resolve the configured macOS screenshot directory with:

```zsh
defaults read com.apple.screencapture location 2>/dev/null
```

Fall back to `~/Desktop` only when no location is configured. Select the newest
regular image whose filename matches the system screenshot convention. Accept
PNG, JPEG, HEIC, and TIFF files. Do not scan the entire home directory.

Before renaming, confirm the requested name has a safe extension and does not
overwrite an existing file. Use the filesystem result as the source of truth;
never invent a screenshot path. Return a clear not-found result when the
directory contains no matching image.
