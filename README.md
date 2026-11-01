# GSPackServerInstaller

Bouwt een kant-en-klare Minecraft server uit het **GSPack** modpack (of elk ander CurseForge modpack).
Werkt op **Windows** (PowerShell) en **Linux/macOS** (bash). Er is geen CurseForge API-key nodig.

## Wat het doet

1. Haalt het pack op: een lokale CurseForge export-zip, of direct van CurseForge via project-ID
2. Downloadt alle mods uit `manifest.json`
   - client-only mods (Sodium, Iris, FancyMenu, …) en resource-/shaderpacks gaan er niet in
   - mods die op CurseForge als client-only getagd zijn maar wel blocks/recipes bevatten
     (bijv. Equivox) gaan **wel** mee, anders kun je niet joinen
3. Kopieert de overrides (`config`, `kubejs`, …) en eventuele `server-overrides`
4. Installeert de modloader (NeoForge, Forge of Fabric)
5. Downloadt een portable Java (Temurin) als de juiste versie ontbreekt
6. Schrijft `start.bat` / `start.sh` (met auto-herstart), `user_jvm_args.txt` (8 GB RAM) en `eula.txt`

De server komt in een aparte map: **`GSPackServer/`** naast het script.

## Gebruik

### Windows

Sleep de pack-zip op `Build-ServerPack.bat`, of:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-ServerPack.ps1 -Zip .\GSPack-0.1.zip -AcceptEula
```

Starten: `GSPackServer\start.bat`

### Linux / macOS

```bash
sudo apt install curl unzip jq        # eenmalig (Debian/Ubuntu)
chmod +x build-serverpack.sh
./build-serverpack.sh --zip GSPack-0.1.zip --accept-eula
```

Starten: `GSPackServer/start.sh`

### Direct van CurseForge

```powershell
.\Build-ServerPack.ps1 -ProjectId <id> -AcceptEula
```
```bash
./build-serverpack.sh --project <id> --accept-eula
```

## Opties

| PowerShell | bash | Betekenis |
|---|---|---|
| `-Zip` | `--zip` | CurseForge export-zip |
| `-ProjectId` / `-FileId` | `--project` / `--file` | pack van CurseForge (standaard nieuwste versie) |
| `-OutDir` | `--out` | doelmap (standaard `GSPackServer`) |
| `-AcceptEula` | `--accept-eula` | zet `eula=true` ([Minecraft EULA](https://aka.ms/MinecraftEULA)) |
| `-RamMB` | `--ram` | geheugen in MB (standaard 8192 = 8 GB) |
| `-JavaPath` | `--java` | eigen Java gebruiken |
| `-ExcludeMods` | `--exclude` | extra regex van mods die niet op de server mogen |
| `-KeepClientMods` | `--keep-client-mods` | client-only filter uitzetten |
| `-FilesOnly` | `--files-only` | alleen mappen + modloader-installer (voor hostingpanels) |

## Updaten

Draai het script opnieuw met de nieuwe pack-zip. Downloads worden gecachet in `.cache/`, dus dat gaat snel.
`mods/` wordt elke keer opnieuw opgebouwd; je wereld, `server.properties` en whitelist blijven staan.
Eigen server-only mods zet je in `GSPackServer/extra-mods/`, die worden elke build meegekopieerd.

## Problemen

- **"Channel … is missing on the server side"** bij joinen: een mod die als client-only is overgeslagen hoort
  toch op de server. Kijk in `skipped-client-mods.txt` en zet de jar in `extra-mods/`, of draai met
  `-KeepClientMods`.
- **Mod mislukt bij downloaden**: staat in `failed-mods.txt`. Download hem handmatig naar `extra-mods/`.
