Adds 2560x1440 and 3840x2160 to **PARANOIA: The Game Edition v1.2.2
(RU/EN)** on **Xash3D 0.96 build 2664**.

Download **`paranoia-tge-resolution-patch-v1.0.0.zip`** below — not GitHub's
automatically generated "Source code" archive. Extract its contents directly
beside `paranoia.exe`, then run `Install-1440p.cmd` or `Install-4K.cmd`.

Both installers add both modes; the chosen installer only selects the initial
fullscreen mode. The patcher verifies exact `xash.dll` / `menu.dll` hashes,
creates a local stock backup, and `Restore.cmd` restores the original DLLs and
previous `video.cfg`. A completed backup is removed after Restore, so the next
install takes a fresh snapshot. No game or engine binaries/assets are
distributed.

## Compatibility / limitations

- Only the exact TGE v1.2.2 build 2664 is supported; unknown binaries are
  refused.
- 2560x1440 replaces mode 22 (2560x1600); 3840x2160 replaces mode 10
  (800x480).
- 1440p fullscreen was verified at an actual 2560x1440 game-window size.
- 4K rendering was verified from a real 3840x2160 in-game frame. Exclusive 4K
  fullscreen remains hardware-validation pending because the test display is
  2560x1440 and Windows rejected the 3840x2160 display mode. It requires a
  monitor/driver that exposes 3840x2160 (or DSR/VSR).
- Close the game before installation. Steam launch options are unnecessary.

See `README.md` or `README.ru.md` for full instructions.
