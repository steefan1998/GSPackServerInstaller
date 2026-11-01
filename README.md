# GSPackServerInstaller

Builds a ready-to-run Minecraft server from the **GSPack** modpack (or any other CurseForge modpack).
Works on **Windows** (PowerShell) and **Linux/macOS** (bash). No CurseForge API key needed.

## What it does

1. Gets the pack: the latest GSPack straight from CurseForge
   ([project 1777849](https://www.curseforge.com/projects/1777849)), or a local export zip
2. Downloads every mod in `manifest.json`
   - client-only mods (Sodium, Iris, FancyMenu, …) and resource/shader packs are left out
   - mods tagged client-only on CurseForge that do contain blocks/recipes
     (e.g. Equivox) **are** kept, otherwise clients can't join
3. Copies the overrides (`config`, `kubejs`, …) and any `server-overrides`
4. Installs the mod loader (NeoForge, Forge or Fabric)
5. Downloads a portable Java (Temurin) if the right version is missing
6. Writes `start.bat` / `start.sh` (with auto-restart), `user_jvm_args.txt` (8 GB RAM) and `eula.txt`

The server goes into its own folder: **`GSPackServer/`** next to the script.

## Usage

### Windows

Double-click `Build-ServerPack.bat` to build from the latest GSPack on CurseForge
(or drag a pack zip onto it). Or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-ServerPack.ps1 -AcceptEula
```

Start it with `GSPackServer\start.bat`.

### Linux / macOS

```bash
sudo apt install curl unzip jq        # once (Debian/Ubuntu)
chmod +x build-serverpack.sh
./build-serverpack.sh --accept-eula
```

Start it with `GSPackServer/start.sh`.

### From a local zip or another modpack

```powershell
.\Build-ServerPack.ps1 -Zip .\GSPack-0.2.zip -AcceptEula
.\Build-ServerPack.ps1 -ProjectId <id> -AcceptEula
```
```bash
./build-serverpack.sh --zip GSPack-0.2.zip --accept-eula
./build-serverpack.sh --project <id> --accept-eula
```

Once you've accepted the EULA, rebuilding without the flag keeps `eula=true`.

## Options

| PowerShell | bash | Meaning |
|---|---|---|
| `-Zip` | `--zip` | build from a local CurseForge export zip |
| `-ProjectId` / `-FileId` | `--project` / `--file` | CurseForge pack (default `1777849` = GSPack, latest version) |
| `-OutDir` | `--out` | output folder (default `GSPackServer`) |
| `-AcceptEula` | `--accept-eula` | sets `eula=true` ([Minecraft EULA](https://aka.ms/MinecraftEULA)) |
| `-RamMB` | `--ram` | memory in MB (default 8192 = 8 GB) |
| `-JavaPath` | `--java` | use your own Java |
| `-ExcludeMods` | `--exclude` | extra regex for mods that must not go on the server |
| `-KeepClientMods` | `--keep-client-mods` | turn off the client-only filter |
| `-FilesOnly` | `--files-only` | only the folders + mod loader installer (for hosting panels) |
| `-NoBrowser` | `--no-browser` | don't open the download page of mods that failed to download |

## Updating

Run the script again with the new pack zip. Downloads are cached in `.cache/`, so it's quick.
`mods/` is rebuilt every time; your world, `server.properties` and whitelist are left alone.
Put your own server-only mods in `GSPackServer/extra-mods/`; they're copied in on every build.

## Troubleshooting

- **"Channel … is missing on the server side"** when joining: a mod that was skipped as client-only
  is needed on the server after all. Check `skipped-client-mods.txt` and put the jar in `extra-mods/`,
  or run with `-KeepClientMods`.
- **A mod fails to download**: the script opens the CurseForge download page of that exact
  mod version in your browser (on Windows also the `extra-mods\` folder). Download the jar into
  `extra-mods/` and run the script again. The links are also in `failed-mods.txt`.
