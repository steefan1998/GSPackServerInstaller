# GSPackServerInstaller

Builds a ready-to-run Minecraft server from the **GSPack** modpack (or any other CurseForge modpack).
Works on **Windows** (PowerShell) and **Linux/macOS** (bash). No CurseForge API key needed.

## What it does

1. Gets the pack: the latest GSPack release straight from CurseForge
   ([project 1777849](https://www.curseforge.com/projects/1777849)), any older release you pick,
   or a local export zip. Dev builds (alphas) are never used. It tells you when a newer
   version is on CurseForge than the one you're building or have installed.
2. Downloads every mod in `manifest.json`
   - client-only mods (Sodium, Iris, FancyMenu, …) and resource/shader packs are left out
   - mods tagged client-only on CurseForge that do contain blocks/recipes
     (e.g. Equivox) **are** kept, otherwise clients can't join
3. Copies the overrides (`config`, `kubejs`, …) and any `server-overrides`
4. Installs the mod loader (NeoForge, Forge or Fabric)
5. Downloads a portable Java (Temurin) if the right version is missing
6. Writes `start.bat` / `start.sh` (with auto-restart), `user_jvm_args.txt` (8 GB RAM) and `eula.txt`
7. Adds the GSPack `server-icon.png` (64×64) for the server list, unless the server already has one

The server goes into its own folder: **`GSPackServer/`** next to the script.

## Usage

### Windows

**Program (GUI):** start `GSPackInstaller.exe` (in the release zip; keep it next to the scripts).
It shows the installed version and the newest one on CurseForge, and lets you:

- build or update to the latest version, pick an older version, or use a local zip
- set the RAM, accept the EULA, turn the mod download pages on/off, or build files only
- run the server in a separate **Server console** window, with Start/Stop controls,
  live output, commands and a **spark tps** button
- open the server folder, with the build output shown live
- convert an older world to GSPack 0.5's unified materials (*Convert world*, see below)

The installer and server console automatically follow Windows' light/dark app theme,
including changes while the windows are open. Stop the server in the console before updating it.

Local zip imports support **GSPack only**. The installer checks the pack name in
`manifest.json` before changing the server folder; renaming another modpack's zip does not bypass this check.

**Menu:** double-click `Build-ServerPack.bat` for the same options in a text menu:

```
  1  Build / update to the latest version
  2  Choose a version
  3  Build from a local zip
  4  Start the server
  5  Open the server folder
  6  Files only (for a hosting panel)
  7  Settings  (RAM, EULA, open mod pages)
  8  Convert the world  (GSPack 0.5)
  0  Exit
```

Dragging a pack zip onto `Build-ServerPack.bat` builds from that zip right away. Or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-ServerPack.ps1 -AcceptEula
```

Start it with `GSPackServer\start.bat`.

To build the GUI yourself: `powershell -ExecutionPolicy Bypass -File gui\build-gui.ps1`
(uses the C# compiler that comes with Windows).

### Linux / macOS

```bash
sudo apt install curl unzip jq        # once (Debian/Ubuntu)
chmod +x build-serverpack.sh
./build-serverpack.sh --accept-eula
```

Start it with `GSPackServer/start.sh`.

### A specific version, a local zip or another modpack

```powershell
.\Build-ServerPack.ps1 -ListVersions
.\Build-ServerPack.ps1 -Version 0.3 -AcceptEula
.\Build-ServerPack.ps1 -Zip .\GSPack-0.2.zip -AcceptEula
.\Build-ServerPack.ps1 -ProjectId <id> -AcceptEula
```
```bash
./build-serverpack.sh --list
./build-serverpack.sh --version 0.3 --accept-eula
./build-serverpack.sh --zip GSPack-0.2.zip --accept-eula
./build-serverpack.sh --project <id> --accept-eula
```

Once you've accepted the EULA, rebuilding without the flag keeps `eula=true`.

## Options

| PowerShell | bash | Meaning |
|---|---|---|
| `-Zip` | `--zip` | build from a local CurseForge export zip |
| `-ProjectId` / `-FileId` | `--project` / `--file` | CurseForge pack (default `1777849` = GSPack, latest version) |
| `-Version` | `--version` | pack version from CurseForge, e.g. `0.3` (default: latest release) |
| `-ListVersions` | `--list` | list the versions on CurseForge and the installed one |
| `-Menu` | | the text menu (what `Build-ServerPack.bat` opens) |
| `-OutDir` | `--out` | output folder (default `GSPackServer`) |
| `-AcceptEula` | `--accept-eula` | sets `eula=true` ([Minecraft EULA](https://aka.ms/MinecraftEULA)) |
| `-RamMB` | `--ram` | memory in MB (default 8192 = 8 GB) |
| `-JavaPath` | `--java` | use your own Java |
| `-ExcludeMods` | `--exclude` | extra regex for mods that must not go on the server |
| `-KeepClientMods` | `--keep-client-mods` | turn off the client-only filter |
| `-FilesOnly` | `--files-only` | only the folders + mod loader installer (for hosting panels) |
| `-NoBrowser` | `--no-browser` | don't open the download page of mods that failed to download |

## Updating

Every build checks CurseForge: it shows `Updating server: GSPack 0.2 -> GSPack 0.4`, or
`Update available` when you build an older version. The installed version is kept in
`GSPackServer/pack-version.txt`. To update, build again without `-Zip` / `-Version` (or choose 1 in
the menu, or Build in the GUI). Downloads are cached in `.cache/`, so it's quick.
`mods/` is rebuilt every time; your world, `server.properties` and whitelist are left alone.
Put your own server-only mods in `GSPackServer/extra-mods/`; they're copied in on every build.

## Converting a world (GSPack 0.5)

GSPack 0.5 unifies materials: one item per metal, dust or plate (AllTheOres first), and ores that
AllTheOres also has no longer generate. A world from an older version still holds the old blocks and
items. The pack converts them while you play, but **Convert-World** converts the whole world at once,
also areas nobody visits. Update the server to 0.5 first, then **stop it** and use one of:

- **GUI:** the *Convert world* button: pick the server or world folder in File Explorer
- **Menu:** option `8` in `Build-ServerPack.bat` (Enter = this server, `B` = browse for a folder)
- **Windows:** double-click `Convert-World.bat` and pick the folder in File Explorer, or drag a server or world folder onto it
- **Linux / macOS:** `./convert-world.sh [server folder]` (needs [PowerShell 7](https://aka.ms/powershell), `pwsh`)
- **Directly:** `powershell -ExecutionPolicy Bypass -File .\Convert-World.ps1 -World <server or world folder> [-DryRun]`
  (`-Interactive` = dry run first, then ask; `-Pick` = choose the folder in File Explorer)

It always shows a dry run first and asks before writing. It converts placed blocks in every dimension,
items in chests and machines, dropped items, player inventories and saved mod data, and refuses to run
while the world is open. Every file it changes is copied to `<world>/gspack-convert-backup` first; delete
that folder once the world works. The id tables are built in, so it also works on a world copied on its
own or a server still on 0.4; when the server's `kubejs` folder is on 0.5 or newer, it uses that one
instead. `Convert-World.ps1` is the same file as `tools/convert-world.ps1`
in the [GSPack repository](https://github.com/steefan1998/GSPack).

## Troubleshooting

- **"Channel … is missing on the server side"** when joining: a mod that was skipped as client-only
  is needed on the server after all. Check `skipped-client-mods.txt` and put the jar in `extra-mods/`,
  or run with `-KeepClientMods`.
- **A mod fails to download**: the script opens the CurseForge download page of that exact
  mod version in your browser (on Windows also the `extra-mods\` folder). Download the jar into
  `extra-mods/` and run the script again. The links are also in `failed-mods.txt`.
