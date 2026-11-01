<#
.SYNOPSIS
    Builds a ready-to-run Minecraft server from a CurseForge modpack (GSPack).

.DESCRIPTION
    1. Gets the client zip (local file or from CurseForge by project ID)
    2. Downloads every mod in manifest.json and filters out client-only mods
    3. Copies overrides (config, kubejs, ...) and any server-overrides
    4. Installs the mod loader (NeoForge / Forge / Fabric)
    5. Makes sure the right Java is available (downloads portable Temurin if missing)
    6. Writes start.bat / start.sh, user_jvm_args.txt and eula.txt

    The server goes into its own folder, GSPackServer\ next to this script by default.
    No CurseForge API key needed. Downloads are cached in .cache\ next to the script,
    so re-running for a new pack version is quick. Note: the mods\ folder is rebuilt
    on every run from the manifest (+ the extra-mods\ folder, see below).

.EXAMPLE
    .\Build-ServerPack.ps1 -Zip .\GSPack-0.1.zip -AcceptEula

.EXAMPLE
    # Straight from CurseForge:
    .\Build-ServerPack.ps1 -ProjectId 1234567 -AcceptEula

.EXAMPLE
    # Only the folders + NeoForge installer (install it yourself / through your host)
    .\Build-ServerPack.ps1 -Zip .\GSPack-0.1.zip -FilesOnly
#>
[CmdletBinding(DefaultParameterSetName = 'Zip')]
param(
    # Path to the CurseForge export zip (client pack)
    [Parameter(ParameterSetName = 'Zip', Mandatory = $true)]
    [string]$Zip,

    # CurseForge project ID of the modpack
    [Parameter(ParameterSetName = 'CurseForge', Mandatory = $true)]
    [int]$ProjectId,

    # Specific file ID of the pack (default: latest release)
    [Parameter(ParameterSetName = 'CurseForge')]
    [int]$FileId,

    # Server output folder (default: .\<PackName>Server next to this script, e.g. GSPackServer)
    [string]$OutDir,

    # Set eula=true (you agree to https://aka.ms/MinecraftEULA)
    [switch]$AcceptEula,

    # Server memory in MB (default 8192 = 8 GB)
    [int]$RamMB,

    # Path to java.exe; by default JAVA_HOME, PATH and <OutDir>\java are searched
    [string]$JavaPath,

    # Extra regex patterns (on file name) for mods that must NOT go on the server
    [string[]]$ExcludeMods = @(),

    # Skip the client-only filter (keep all mods)
    [switch]$KeepClientMods,

    # Only the folders (mods, config, ...) + the mod loader installer; installs nothing,
    # no Java, no start scripts. Handy for a hosting panel.
    [switch]$FilesOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$UserAgent = 'Mozilla/5.0 (GSPack server builder)'
$CfSite = 'https://www.curseforge.com/api/v1'

# Mods often tagged Client+Server that only work client-side
$KnownClientOnly = @(
    '^oculus', '^iris', '^sodium', '^embeddium', '^rubidium', '^entityculling', '^fancymenu',
    '^drippyloadingscreen', '^konkrete', '^legendarytooltips', '^betterf3', '^jeresources-client',
    '^mousetweaks', '^appleskin-client', '^ding', '^notenoughanimations', '^citresewn',
    '^entity_?texture_?features', '^entity_?model_?features', '^skinlayers3d', '^3dskinlayers',
    '^firstperson', '^cherishedworlds', '^controlling', '^searchables', '^catalogue',
    '^configured-client', '^betterthirdperson', '^shulkerboxtooltip-client', '^xaerominimap-client',
    '^modernfix-client', '^immediatelyfast', '^enhancedvisuals', '^presencefootsteps',
    '^soundphysics', '^ambientsounds', '^dynamiclights', '^lambdynamiclights', '^sodiumdynamiclights',
    '^chat_heads', '^chatheads', '^blur', '^loadmyresources', '^yeetusexperimentus'
) + $ExcludeMods

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

function Invoke-Download([string]$Url, [string]$Dest) {
    $tmp = "$Dest.part"
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UserAgent $UserAgent -UseBasicParsing
            Move-Item -Force -LiteralPath $tmp -Destination $Dest
            return
        } catch {
            if ($i -eq 3) { throw }
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

function Get-Json([string]$Url) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            return Invoke-RestMethod -Uri $Url -UserAgent $UserAgent -UseBasicParsing
        } catch {
            if ($i -eq 3) { throw }
            Start-Sleep -Seconds (2 * $i)
        }
    }
}

# True if a jar contains blocks or server data (recipes, loot tables, worldgen).
# Such a mod has to be on the server too, even if CurseForge tags it client-only.
function Test-ServerContent([string]$Jar) {
    $z = [IO.Compression.ZipFile]::OpenRead($Jar)
    try {
        foreach ($e in $z.Entries) {
            if ($e.FullName -match '^assets/[^/]+/blockstates/' -or
                $e.FullName -match '^data/[^/]+/(recipe|recipes|loot_table|loot_tables|worldgen)/') { return $true }
        }
        return $false
    } finally { $z.Dispose() }
}

function Get-JavaMajor([string]$Exe) {
    if (-not $Exe -or -not (Test-Path $Exe)) { return 0 }
    $out = & cmd /c "`"$Exe`" -version 2>&1"
    $line = ($out | Select-Object -First 1) -as [string]
    if ($line -match 'version "(\d+)(\.(\d+))?') {
        if ($Matches[1] -eq '1') { return [int]$Matches[3] }
        return [int]$Matches[1]
    }
    return 0
}

# ---------------------------------------------------------------------------
# Cache lives next to the script so the server folder stays clean
$Cache = Join-Path $PSScriptRoot '.cache'
$ModCache = Join-Path $Cache 'mods'
$MetaCache = Join-Path $Cache 'meta'
New-Item -ItemType Directory -Force $ModCache, $MetaCache | Out-Null

# 1. Get the client pack -----------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'CurseForge') {
    Write-Step "Fetching modpack from CurseForge (project $ProjectId)"
    if (-not $FileId) {
        $files = Get-Json "$CfSite/mods/$ProjectId/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=true"
        $latest = $files.data | Where-Object { $_.fileName -like '*.zip' } | Select-Object -First 1
        if (-not $latest) { throw "No pack file found for project $ProjectId (is it approved yet?)" }
        $FileId = $latest.id
        Write-Host "Latest version: $($latest.displayName) (file $FileId)"
    }
    $Zip = Join-Path $Cache "pack-$FileId.zip"
    if (-not (Test-Path $Zip)) { Invoke-Download "$CfSite/mods/$ProjectId/files/$FileId/download" $Zip }
} else {
    $Zip = (Resolve-Path $Zip).Path
}

Write-Step "Extracting pack: $Zip"
$PackDir = Join-Path $Cache 'pack'
if (Test-Path $PackDir) { Remove-Item -Recurse -Force $PackDir }
[IO.Compression.ZipFile]::ExtractToDirectory($Zip, $PackDir)

$manifestPath = Join-Path $PackDir 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "No manifest.json in $Zip - is this a CurseForge export?" }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mcVersion = $manifest.minecraft.version
$loader = ($manifest.minecraft.modLoaders | Where-Object { $_.primary } | Select-Object -First 1).id
if (-not $loader) { $loader = $manifest.minecraft.modLoaders[0].id }
Write-Host "$($manifest.name) $($manifest.version) - Minecraft $mcVersion, $loader, $($manifest.files.Count) mods"

# Default output folder: <PackName>Server next to this script, e.g. GSPackServer
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot (($manifest.name -replace '[^\w.-]', '') + 'Server') }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force $OutDir | Out-Null
Write-Host "Output folder: $OutDir"

if (-not $RamMB) { $RamMB = 8192 }
# Write as G when it's a whole number of GB (8192 -> 8G)
$RamArg = "$($RamMB)M"
if ($RamMB % 1024 -eq 0) { $RamArg = "$($RamMB / 1024)G" }

# 2. Download mods ------------------------------------------------------------
Write-Step 'Downloading mods'
$ModsDir = Join-Path $OutDir 'mods'
if (Test-Path $ModsDir) { Remove-Item -Recurse -Force $ModsDir }
New-Item -ItemType Directory -Force $ModsDir | Out-Null

$skipped = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]
$keptTagged = New-Object System.Collections.Generic.List[string]
$n = 0
$total = @($manifest.files).Count
foreach ($f in $manifest.files) {
    $n++
    $pid_ = $f.projectID; $fid = $f.fileID
    try {
        $metaFile = Join-Path $MetaCache "$fid.json"
        if (Test-Path $metaFile) {
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
        } else {
            $meta = (Get-Json "$CfSite/mods/$pid_/files/$fid").data
            $meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
        }
        $name = $meta.fileName
        $tags = @($meta.gameVersions)

        if ($name -notlike '*.jar') {
            # Resource/shader packs don't belong on the server
            $skipped.Add($name)
            Write-Host ("[{0}/{1}] not a mod (resource/shader pack), skipped: {2}" -f $n, $total, $name) -ForegroundColor DarkYellow
            continue
        }

        # Cache by file ID: file names can contain [ ] (wildcards in PowerShell)
        $cached = Join-Path $ModCache "$fid.jar"
        if (-not (Test-Path -LiteralPath $cached) -or ((Get-Item -LiteralPath $cached).Length -ne $meta.fileLength)) {
            Write-Host ("[{0}/{1}] download {2}" -f $n, $total, $name)
            Invoke-Download "$CfSite/mods/$pid_/files/$fid/download" $cached
        } else {
            Write-Host ("[{0}/{1}] cached   {2}" -f $n, $total, $name) -ForegroundColor DarkGray
        }

        if (-not $KeepClientMods) {
            $clientOnly = ($tags -contains 'Client') -and -not ($tags -contains 'Server')
            $listed = $KnownClientOnly | Where-Object { $name -match $_ }
            if ($clientOnly -or $listed) {
                if (Test-ServerContent $cached) {
                    # Mis-tagged (e.g. Equivox): without this mod clients can't join
                    $keptTagged.Add($name)
                    Write-Host ("[{0}/{1}] client tag but has blocks/recipes, kept on server: {2}" -f $n, $total, $name) -ForegroundColor Green
                } else {
                    $skipped.Add($name)
                    Write-Host ("[{0}/{1}] client-only, skipped: {2}" -f $n, $total, $name) -ForegroundColor DarkYellow
                    continue
                }
            }
        }

        [IO.File]::Copy($cached, (Join-Path $ModsDir $name), $true)
    } catch {
        $failed.Add("project $pid_ / file $fid ($($_.Exception.Message)) -> https://www.curseforge.com/projects/$pid_")
        Write-Host ("[{0}/{1}] FAILED project {2} file {3}" -f $n, $total, $pid_, $fid) -ForegroundColor Red
    }
}

# 3. Overrides ----------------------------------------------------------------
Write-Step 'Copying overrides'
foreach ($ov in @($manifest.overrides, 'server-overrides')) {
    if (-not $ov) { continue }
    $src = Join-Path $PackDir $ov
    if (Test-Path $src) {
        Write-Host "  $ov\ -> server"
        Copy-Item -Recurse -Force (Join-Path $src '*') $OutDir
    }
}
# Your own server-only mods: put them in <OutDir>\extra-mods, they're kept
$extra = Join-Path $OutDir 'extra-mods'
New-Item -ItemType Directory -Force $extra | Out-Null
Get-ChildItem $extra -Filter *.jar | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $ModsDir $_.Name), $true); Write-Host "  extra mod: $($_.Name)" }
# Also remove client-only mods that came in through the overrides
if (-not $KeepClientMods) {
    Get-ChildItem $ModsDir -Filter *.jar | Where-Object { $nm = $_.Name; $KnownClientOnly | Where-Object { $nm -match $_ } } |
        ForEach-Object { $skipped.Add($_.Name); Remove-Item -LiteralPath $_.FullName }
}

# 4. Java ---------------------------------------------------------------------
$java = $null
if (-not $FilesOnly) {
    Write-Step 'Checking Java'
    $javaNeeded = 21
    try {
        $vm = Get-Json 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
        $v = $vm.versions | Where-Object { $_.id -eq $mcVersion } | Select-Object -First 1
        if ($v) { $javaNeeded = [int](Get-Json $v.url).javaVersion.majorVersion }
    } catch { Write-Warning "Couldn't get the Java version from Mojang, assuming Java $javaNeeded" }
    Write-Host "Minecraft $mcVersion needs Java $javaNeeded"

    $localJava = Join-Path $OutDir 'java\bin\java.exe'
    $candidates = @($JavaPath, $localJava)
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\java.exe') }
    $onPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }

    foreach ($c in $candidates) {
        if ($c -and (Get-JavaMajor $c) -ge $javaNeeded) { $java = (Resolve-Path $c).Path; break }
    }
    if (-not $java) {
        Write-Host "No Java $javaNeeded+ found, downloading portable Temurin JRE $javaNeeded..."
        $jreZip = Join-Path $Cache "temurin-$javaNeeded.zip"
        Invoke-Download "https://api.adoptium.net/v3/binary/latest/$javaNeeded/ga/windows/x64/jre/hotspot/normal/eclipse" $jreZip
        $jreTmp = Join-Path $Cache 'jre-extract'
        if (Test-Path $jreTmp) { Remove-Item -Recurse -Force $jreTmp }
        [IO.Compression.ZipFile]::ExtractToDirectory($jreZip, $jreTmp)
        $inner = Get-ChildItem $jreTmp -Directory | Select-Object -First 1
        $javaDir = Join-Path $OutDir 'java'
        if (Test-Path $javaDir) { Remove-Item -Recurse -Force $javaDir }
        Move-Item $inner.FullName $javaDir
        Remove-Item -Recurse -Force $jreTmp
        $java = $localJava
    }
    Write-Host "Java: $java"
    $javaInStart = 'java'
    if ($java -eq $localJava) { $javaInStart = '%~dp0java\bin\java.exe' }
}

# 5. Mod loader ---------------------------------------------------------------
Write-Step "Installing mod loader: $loader"
$loaderName, $loaderVer = $loader -split '-', 2
$winArgs = $null; $unixArgs = $null; $serverJar = $null

switch ($loaderName) {
    'neoforge' {
        $inst = Join-Path $Cache "neoforge-$loaderVer-installer.jar"
        if (-not (Test-Path $inst)) {
            Invoke-Download "https://maven.neoforged.net/releases/net/neoforged/neoforge/$loaderVer/neoforge-$loaderVer-installer.jar" $inst
        }
        $argsDir = "libraries/net/neoforged/neoforge/$loaderVer"
    }
    'forge' {
        $full = "$mcVersion-$loaderVer"
        $inst = Join-Path $Cache "forge-$full-installer.jar"
        if (-not (Test-Path $inst)) {
            Invoke-Download "https://maven.minecraftforge.net/net/minecraftforge/forge/$full/forge-$full-installer.jar" $inst
        }
        $argsDir = "libraries/net/minecraftforge/forge/$full"
    }
    'fabric' {
        $installer = (Get-Json 'https://meta.fabricmc.net/v2/versions/installer' | Select-Object -First 1).version
        $serverJar = 'fabric-server.jar'
        Invoke-Download "https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loaderVer/$installer/server/jar" (Join-Path $OutDir $serverJar)
    }
    default { throw "Mod loader '$loaderName' is not supported" }
}

if ($FilesOnly) {
    if ($loaderName -in 'neoforge', 'forge') {
        Copy-Item -Force $inst $OutDir
        Write-Host "Installer placed: $(Split-Path $inst -Leaf)"
        Write-Host "To install: java -jar $(Split-Path $inst -Leaf) --installServer"
    } else {
        Write-Host "Fabric server launcher placed: $serverJar"
    }
} elseif ($loaderName -in 'neoforge', 'forge') {
    if (Test-Path (Join-Path $OutDir "$argsDir/win_args.txt")) {
        Write-Host 'Mod loader already installed, skipping'
    } else {
        Push-Location $OutDir
        try {
            & $java -jar $inst --installServer $OutDir
            if ($LASTEXITCODE -ne 0) { throw "Installer failed (exit $LASTEXITCODE)" }
        } finally { Pop-Location }
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir '*installer.jar.log')
    }
    if (Test-Path (Join-Path $OutDir "$argsDir/win_args.txt")) {
        $winArgs = "@$argsDir/win_args.txt"; $unixArgs = "@$argsDir/unix_args.txt"
    } else {
        # Old Forge (<1.17) produces a standalone jar
        $serverJar = (Get-ChildItem $OutDir -Filter 'forge-*.jar' | Where-Object { $_.Name -notlike '*installer*' } | Select-Object -First 1).Name
    }
}

# 6. Start scripts + eula -----------------------------------------------------
if (-not $FilesOnly) {
    Write-Step 'Writing start scripts'
    "-Xms$RamArg`r`n-Xmx$RamArg`r`n" | Set-Content (Join-Path $OutDir 'user_jvm_args.txt') -Encoding ASCII -NoNewline

    if ($winArgs) { $launchWin = "$winArgs nogui"; $launchUnix = "$unixArgs nogui" }
    else { $launchWin = "-jar $serverJar nogui"; $launchUnix = $launchWin }

    @"
@echo off
cd /d "%~dp0"
:start
"$javaInStart" @user_jvm_args.txt $launchWin %*
echo.
echo Server stopped. Restarting in 10 seconds, press Ctrl+C to quit.
timeout /t 10
goto start
"@ | Set-Content (Join-Path $OutDir 'start.bat') -Encoding ASCII

    $sh = @"
#!/usr/bin/env sh
cd "`$(dirname "`$0")"
JAVA=java
[ -x ./java/bin/java ] && JAVA=./java/bin/java
while true; do
  "`$JAVA" @user_jvm_args.txt $launchUnix "`$@"
  echo "Server stopped. Restarting in 10 seconds, Ctrl+C to quit."
  sleep 10
done
"@
    [IO.File]::WriteAllText((Join-Path $OutDir 'start.sh'), ($sh -replace "`r`n", "`n"))

    $eula = if ($AcceptEula) { 'true' } else { 'false' }
    "# https://aka.ms/MinecraftEULA`r`neula=$eula`r`n" | Set-Content (Join-Path $OutDir 'eula.txt') -Encoding ASCII

    # Remove the NeoForge/Forge installer's own run scripts (start.bat replaces them)
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir 'run.bat'), (Join-Path $OutDir 'run.sh')
}

# Summary ---------------------------------------------------------------------
Write-Step 'Done'
$modCount = @(Get-ChildItem $ModsDir -Filter *.jar).Count
Write-Host "Server is in:   $OutDir"
Write-Host "Mods on server: $modCount   (client-only / resource packs skipped: $($skipped.Count))"
if ($skipped.Count) { [IO.File]::WriteAllLines((Join-Path $OutDir 'skipped-client-mods.txt'), [string[]]($skipped | Sort-Object -Unique)); Write-Host "  list: skipped-client-mods.txt" }
if ($keptTagged.Count) { Write-Host "Kept on server (client tag, but has content): $($keptTagged -join ', ')" -ForegroundColor Green }
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir 'failed-mods.txt')
if ($failed.Count) {
    Write-Host "FAILED: $($failed.Count) mods - download these by hand into extra-mods\ and run again:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $failed | Set-Content (Join-Path $OutDir 'failed-mods.txt') -Encoding UTF8
}
if ($FilesOnly) {
    Write-Host 'Files only: mod loader not installed, no start scripts/eula written.' -ForegroundColor Yellow
} else {
    if (-not $AcceptEula) { Write-Host "Note: eula.txt is set to false. Run again with -AcceptEula or edit eula.txt." -ForegroundColor Yellow }
    Write-Host "Start with: $OutDir\start.bat" -ForegroundColor Green
}
