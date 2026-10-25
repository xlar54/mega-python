VICE helpers
============

Small tools for driving VICE (`x64sc.exe` for the C64, `xscpu64.exe` for the C64 with a
SuperCPU) through its remote monitor. They're useful for studying an original game, or for
testing C64-mode code.

VICE is at `C:\Emulation\Commodore\vice\GTK3VICE-3.9-win64\bin\`.

Start the emulator with a remote monitor:

```
x64sc.exe   -remotemonitor -remotemonitoraddress ip4://127.0.0.1:6510 -8 game.d64
xscpu64.exe -simmsize 16 -drive8type 1581 -remotemonitor -remotemonitoraddress ip4://127.0.0.1:6510 -8 game.d81
```

In PowerShell, use `Start-Process` with `-RedirectStandardOutput` so the console log doesn't fill
the tool output.

| Tool | Use |
|------|-----|
| `mon.py "cmd ;; cmd"` | Run monitor commands (use `'` for `"`), then resume. Example: `mon.py "bank ram ;; m 0800 08ff"` |
| `snap.py name ["cmd" ...]` | Screenshot to `name.png` next to the script |
| `vmon.py` | Minimal command sender (used by the others) |
| `hostkey.ps1 -Key " "` / `-Key "F1,ENTER"` / `-Key N0` | A *real* key press in the VICE window. Games scanning the CIA matrix ignore the monitor's `keybuf`. |

Recipes:

* **Load and run:** `mon.py "keybuf load'*',8,1\nrun\n"`. That goes through the KERNAL buffer, so
  it's fine at the BASIC prompt.
* **Joystick:** enable a keyset joystick in port 2, then send Z/I/K/J/L with `hostkey.ps1`:

  ```
  mon.py "resourceset 'KeySetEnable' '1' ;; resourceset 'KeySet1Fire' '122' ;; resourceset 'KeySet1North' '105' ;; resourceset 'KeySet1South' '107' ;; resourceset 'KeySet1West' '106' ;; resourceset 'KeySet1East' '108' ;; resourceset 'JoyDevice2' '2'"
  ```

* **Dump memory:** `mon.py "bank ram ;; save 'C:/path/ram.bin' 0 0000 ffff ;; bank io ;; save 'C:/path/io.bin' 0 d000 dfff"`.
  SuperCPU banks are named `ram00` to `ramf7`.
* **Disk swap:** `mon.py "attach 'C:/path/disk2.d81' 8"`.
* Reconnect for every command batch. Long-lived connections and watchpoints crashed VICE.
* A full play-and-record bot is in `C:\Users\scott\repos\mega-dust\tools\vice\bot.py`.
