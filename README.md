# PARANOIA TGE Resolution Patch

[Русская инструкция](README.ru.md)

Adds selectable **2560x1440** and **3840x2160 (4K)** modes to
**PARANOIA: The Game Edition v1.2.2 (RU/EN)** running on the original
**Xash3D 0.96 build 2664**.

The stock engine has a hard-coded mode table and ignores `-width` / `-height`.
This patcher changes two entries in that table and their menu labels locally:

- mode 22: 2560x1600 becomes 2560x1440;
- mode 10: 800x480 becomes 3840x2160.

Both installers add both resolutions. The installer you choose only selects
which one will be active on the next launch.

## Install

1. Close the game.
2. From the GitHub release, download the named asset
   **`paranoia-tge-resolution-patch-v1.0.0.zip`**. Do not download GitHub's
   automatically generated "Source code" archive.
3. Extract the ZIP contents directly into the game directory, beside
   `paranoia.exe`, `xash.dll`, and `menu.dll`. Allow the new `scripts` directory
   to be created. The archive does not replace anything when extracted.
4. Run `Install-1440p.cmd` or `Install-4K.cmd`.
5. Start `paranoia.exe` normally. No Steam launch options are required.

Administrator rights are not required when your Windows account can write to
the game directory. If you added the game to Steam as a non-Steam shortcut,
keep `paranoia.exe` as the target and the game directory as "Start in".

## Restore

Close the game and run `Restore.cmd`. It restores the verified stock DLLs and
the `video.cfg` that existed before the first installation. The local backup is
stored in `.paranoia-resolution-patch-backup` inside the game directory while
the patch is active, then removed after a successful restore so a later
installation takes a fresh snapshot.

## Safety

- No engine DLL, game executable, or game asset is distributed.
- The patcher accepts only exact known SHA-256 states of the v1.2.2 build 2664
  `xash.dll` and `menu.dll`. Unknown or modified files are refused before any
  game file is changed.
- It reconstructs and verifies pristine files for backup, stages both patched
  DLLs, verifies their hashes, and rolls the pair back if any step fails.
- The rest of `video.cfg` is preserved. The selected mode is fullscreen with
  automatic refresh rate (`vid_displayfrequency 0`).
- If `video.cfg` did not exist before installation, Restore keeps the newly
  created file but selects the stock-safe 1920x1080 mode instead of deleting
  later settings.

You can verify the downloaded ZIP with Windows PowerShell:

```powershell
Get-FileHash .\paranoia-tge-resolution-patch-v1.0.0.zip -Algorithm SHA256
```

Compare the result with the separately attached `SHA256SUMS.txt` on the same
GitHub release.

## Compatibility and limitations

- Supported: PARANOIA TGE v1.2.2 RU/EN, Xash3D 0.96 build 2664.
- Not supported: other Xash3D builds, Xash3D FWGS replacements, or already
  modified unknown DLLs.
- 2560x1440 exclusive fullscreen was verified as an actual 2560x1440 game
  window.
- A real 3840x2160 in-game frame was rendered and captured. Exclusive 4K
  fullscreen could not be physically validated on the test PC because its
  monitor is 2560x1440 and Windows rejects 3840x2160 as a display mode. A 4K
  monitor or a driver-exposed DSR/VSR 3840x2160 mode is therefore required.
- The original engine has no native borderless-fullscreen mode.

## Why not replace the engine?

Current Xash3D FWGS builds support custom dimensions, but their official
compatibility list marks PARANOIA support as temporarily abandoned. Replacing
the full engine can also affect the mod's custom renderer hook and game DLLs.
This patch deliberately changes only four fixed data fields in the exact engine
and menu files shipped with TGE v1.2.2.

## License and credits

The patcher and its documentation are MIT-licensed. See [NOTICE.md](NOTICE.md)
for third-party ownership and project status. This is an unofficial community
project and is not affiliated with the PARANOIA team, Xash3D projects, or
Valve.
