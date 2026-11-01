# GSPackServerInstaller

Builds a ready-to-run Minecraft server from the **GSPack** modpack (or any other CurseForge modpack).
Works on **Windows** (PowerShell) and **Linux/macOS** (bash). No CurseForge API key needed.

## What it does

1. Gets the pack: a local CurseForge export zip, or straight from CurseForge by project ID
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

Drag the pack zip onto `Build-ServerPack.bat`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-ServerPack.ps1 -Zip .\GSPack-0.1.zip -AcceptEula
```

Start it with `GSPackServer\start.bat`.

### Linux / macOS

```bash
sudo apt install curl unzip jq        # once (Debian/Ubuntu)
chmod +x build-serverpack.sh
./build-serverpack.sh --zip GSPack-0.1.zip --accept-eula
```

Start it with `GSPackServer/start.sh`.

### Straight from CurseForge

```powershell
.\Build-ServerPack.ps1 -ProjectId <id> -AcceptEula
```
```bash
./build-serverpack.sh --project <id> --accept-eula
```

## Options

| PowerShell | bash | Meaning |
|---|---|---|
| `-Zip` | `--zip` | CurseForge export zip |
| `-ProjectId` / `-FileId` | `--project` / `--file` | pack from CurseForge (latest version by default) |
| `-OutDir` | `--out` | output folder (default `GSPackServer`) |
| `-AcceptEula` | `--accept-eula` | sets `eula=true` ([Minecraft EULA](https://aka.ms/MinecraftEULA)) |
| `-RamMB` | `--ram` | memory in MB (default 8192 = 8 GB) |
| `-JavaPath` | `--java` | use your own Java |
| `-ExcludeMods` | `--exclude` | extra regex for mods that must not go on the server |
| `-KeepClientMods` | `--keep-client-mods` | turn off the client-only filter |
| `-FilesOnly` | `--files-only` | only the folders + mod loader installer (for hosting panels) |

## Updating

Run the script again with the new pack zip. Downloads are cached in `.cache/`, so it's quick.
`mods/` is rebuilt every time; your world, `server.properties` and whitelist are left alone.
Put your own server-only mods in `GSPackServer/extra-mods/`; they're copied in on every build.

## Troubleshooting

- **"Channel … is missing on the server side"** when joining: a mod that was skipped as client-only
  is needed on the server after all. Check `skipped-client-mods.txt` and put the jar in `extra-mods/`,
  or run with `-KeepClientMods`.
- **A mod fails to download**: it's listed in `failed-mods.txt`. Download it by hand into `extra-mods/`.
