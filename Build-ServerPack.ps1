<#
.SYNOPSIS
    Bouwt een kant-en-klare Minecraft server uit een CurseForge modpack (GSPack).

.DESCRIPTION
    1. Haalt de client-zip op (lokaal bestand of van CurseForge via project-ID)
    2. Downloadt alle mods uit manifest.json en filtert client-only mods eruit
    3. Kopieert overrides (config, kubejs, ...) en eventuele server-overrides
    4. Installeert de modloader (NeoForge / Forge / Fabric)
    5. Zorgt voor de juiste Java (downloadt portable Temurin als die ontbreekt)
    6. Schrijft start.bat / start.sh, user_jvm_args.txt en eula.txt

    De server komt in een aparte map, standaard GSPackServer\ naast dit script.
    Er is geen CurseForge API-key nodig. Downloads worden gecachet in .cache\ naast het script,
    dus opnieuw draaien voor een nieuwe packversie is snel. Let op: de map mods\ wordt
    bij elke run opnieuw opgebouwd uit het manifest (+ de map extra-mods\, zie hieronder).

.EXAMPLE
    .\Build-ServerPack.ps1 -Zip "C:\Users\Chaos\Documents\GSPack-0.1.zip" -AcceptEula

.EXAMPLE
    # Zodra GSPack op CurseForge is goedgekeurd:
    .\Build-ServerPack.ps1 -ProjectId 1234567 -AcceptEula

.EXAMPLE
    # Alleen de mappen + NeoForge installer (installeer je zelf / via je host)
    .\Build-ServerPack.ps1 -Zip "C:\Users\Chaos\Documents\GSPack-0.1.zip" -FilesOnly
#>
[CmdletBinding(DefaultParameterSetName = 'Zip')]
param(
    # Pad naar de CurseForge export-zip (client pack)
    [Parameter(ParameterSetName = 'Zip', Mandatory = $true)]
    [string]$Zip,

    # CurseForge project-ID van het modpack
    [Parameter(ParameterSetName = 'CurseForge', Mandatory = $true)]
    [int]$ProjectId,

    # Specifieke file-ID van het pack (standaard: nieuwste release)
    [Parameter(ParameterSetName = 'CurseForge')]
    [int]$FileId,

    # Doelmap van de server (standaard: .\<PackNaam>Server naast dit script, bijv. GSPackServer)
    [string]$OutDir,

    # Zet eula=true (je gaat akkoord met https://aka.ms/MinecraftEULA)
    [switch]$AcceptEula,

    # Geheugen voor de server in MB (standaard 8192 = 8 GB)
    [int]$RamMB,

    # Pad naar java.exe; standaard wordt gezocht in JAVA_HOME, PATH en <OutDir>\java
    [string]$JavaPath,

    # Extra regex-patronen (op bestandsnaam) van mods die NIET op de server mogen
    [string[]]$ExcludeMods = @(),

    # Sla de client-only filter over (alle mods meenemen)
    [switch]$KeepClientMods,

    # Alleen de mappen (mods, config, ...) + de modloader-installer; niets installeren,
    # geen Java, geen startscripts. Handig voor een hostingpanel.
    [switch]$FilesOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$UserAgent = 'Mozilla/5.0 (GSPack server builder)'
$CfSite = 'https://www.curseforge.com/api/v1'

# Mods die vaak als Client+Server getagd zijn maar alleen client-side werken
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

# True als een jar blocks of server-data (recipes, loot tables, worldgen) bevat.
# Zo'n mod moet ook op de server, ook al is hij op CurseForge als client-only getagd.
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
# Cache staat naast het script, zodat de servermap schoon blijft
$Cache = Join-Path $PSScriptRoot '.cache'
$ModCache = Join-Path $Cache 'mods'
$MetaCache = Join-Path $Cache 'meta'
New-Item -ItemType Directory -Force $ModCache, $MetaCache | Out-Null

# 1. Client pack ophalen ------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'CurseForge') {
    Write-Step "Modpack ophalen van CurseForge (project $ProjectId)"
    if (-not $FileId) {
        $files = Get-Json "$CfSite/mods/$ProjectId/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=true"
        $latest = $files.data | Where-Object { $_.fileName -like '*.zip' } | Select-Object -First 1
        if (-not $latest) { throw "Geen pack-bestand gevonden voor project $ProjectId (al goedgekeurd?)" }
        $FileId = $latest.id
        Write-Host "Nieuwste versie: $($latest.displayName) (file $FileId)"
    }
    $Zip = Join-Path $Cache "pack-$FileId.zip"
    if (-not (Test-Path $Zip)) { Invoke-Download "$CfSite/mods/$ProjectId/files/$FileId/download" $Zip }
} else {
    $Zip = (Resolve-Path $Zip).Path
}

Write-Step "Pack uitpakken: $Zip"
$PackDir = Join-Path $Cache 'pack'
if (Test-Path $PackDir) { Remove-Item -Recurse -Force $PackDir }
[IO.Compression.ZipFile]::ExtractToDirectory($Zip, $PackDir)

$manifestPath = Join-Path $PackDir 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "Geen manifest.json in $Zip - is dit een CurseForge export?" }
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mcVersion = $manifest.minecraft.version
$loader = ($manifest.minecraft.modLoaders | Where-Object { $_.primary } | Select-Object -First 1).id
if (-not $loader) { $loader = $manifest.minecraft.modLoaders[0].id }
Write-Host "$($manifest.name) $($manifest.version) - Minecraft $mcVersion, $loader, $($manifest.files.Count) mods"

# Standaard doelmap: <PackNaam>Server naast dit script, bijv. GSPackServer
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot (($manifest.name -replace '[^\w.-]', '') + 'Server') }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force $OutDir | Out-Null
Write-Host "Doelmap: $OutDir"

if (-not $RamMB) { $RamMB = 8192 }
# Schrijf als G als het een heel aantal GB is (8192 -> 8G)
$RamArg = "$($RamMB)M"
if ($RamMB % 1024 -eq 0) { $RamArg = "$($RamMB / 1024)G" }

# 2. Mods downloaden ----------------------------------------------------------
Write-Step 'Mods downloaden'
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
            # Resource-/shaderpacks horen niet op de server
            $skipped.Add($name)
            Write-Host ("[{0}/{1}] geen mod (resource/shaderpack), overgeslagen: {2}" -f $n, $total, $name) -ForegroundColor DarkYellow
            continue
        }

        # Cache op file-ID: bestandsnamen kunnen [ ] bevatten (wildcards in PowerShell)
        $cached = Join-Path $ModCache "$fid.jar"
        if (-not (Test-Path -LiteralPath $cached) -or ((Get-Item -LiteralPath $cached).Length -ne $meta.fileLength)) {
            Write-Host ("[{0}/{1}] download {2}" -f $n, $total, $name)
            Invoke-Download "$CfSite/mods/$pid_/files/$fid/download" $cached
        } else {
            Write-Host ("[{0}/{1}] cache    {2}" -f $n, $total, $name) -ForegroundColor DarkGray
        }

        if (-not $KeepClientMods) {
            $clientOnly = ($tags -contains 'Client') -and -not ($tags -contains 'Server')
            $listed = $KnownClientOnly | Where-Object { $name -match $_ }
            if ($clientOnly -or $listed) {
                if (Test-ServerContent $cached) {
                    # Verkeerd getagd (bijv. Equivox): zonder deze mod kan de client niet joinen
                    $keptTagged.Add($name)
                    Write-Host ("[{0}/{1}] client-tag maar bevat blocks/recipes, toch op server: {2}" -f $n, $total, $name) -ForegroundColor Green
                } else {
                    $skipped.Add($name)
                    Write-Host ("[{0}/{1}] client-only, overgeslagen: {2}" -f $n, $total, $name) -ForegroundColor DarkYellow
                    continue
                }
            }
        }

        [IO.File]::Copy($cached, (Join-Path $ModsDir $name), $true)
    } catch {
        $failed.Add("project $pid_ / file $fid ($($_.Exception.Message)) -> https://www.curseforge.com/projects/$pid_")
        Write-Host ("[{0}/{1}] MISLUKT project {2} file {3}" -f $n, $total, $pid_, $fid) -ForegroundColor Red
    }
}

# 3. Overrides ----------------------------------------------------------------
Write-Step 'Overrides kopieren'
foreach ($ov in @($manifest.overrides, 'server-overrides')) {
    if (-not $ov) { continue }
    $src = Join-Path $PackDir $ov
    if (Test-Path $src) {
        Write-Host "  $ov\ -> server"
        Copy-Item -Recurse -Force (Join-Path $src '*') $OutDir
    }
}
# Eigen server-only mods: zet ze in <OutDir>\extra-mods, die blijven bewaard
$extra = Join-Path $OutDir 'extra-mods'
New-Item -ItemType Directory -Force $extra | Out-Null
Get-ChildItem $extra -Filter *.jar | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $ModsDir $_.Name), $true); Write-Host "  extra mod: $($_.Name)" }
# Client-only mods die via overrides binnenkwamen er ook uithalen
if (-not $KeepClientMods) {
    Get-ChildItem $ModsDir -Filter *.jar | Where-Object { $nm = $_.Name; $KnownClientOnly | Where-Object { $nm -match $_ } } |
        ForEach-Object { $skipped.Add($_.Name); Remove-Item -LiteralPath $_.FullName }
}

# 4. Java ---------------------------------------------------------------------
$java = $null
if (-not $FilesOnly) {
Write-Step 'Java controleren'
$javaNeeded = 21
try {
    $vm = Get-Json 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    $v = $vm.versions | Where-Object { $_.id -eq $mcVersion } | Select-Object -First 1
    if ($v) { $javaNeeded = [int](Get-Json $v.url).javaVersion.majorVersion }
} catch { Write-Warning "Kon Java-versie niet bij Mojang opvragen, ga uit van Java $javaNeeded" }
Write-Host "Minecraft $mcVersion vereist Java $javaNeeded"

$localJava = Join-Path $OutDir 'java\bin\java.exe'
$candidates = @($JavaPath, $localJava)
if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\java.exe') }
$onPath = Get-Command java.exe -ErrorAction SilentlyContinue
if ($onPath) { $candidates += $onPath.Source }

$java = $null
foreach ($c in $candidates) {
    if ($c -and (Get-JavaMajor $c) -ge $javaNeeded) { $java = (Resolve-Path $c).Path; break }
}
if (-not $java) {
    Write-Host "Geen Java $javaNeeded+ gevonden, portable Temurin JRE $javaNeeded downloaden..."
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

# 5. Modloader ----------------------------------------------------------------
Write-Step "Modloader installeren: $loader"
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
    default { throw "Modloader '$loaderName' wordt niet ondersteund" }
}

if ($FilesOnly) {
    if ($loaderName -in 'neoforge', 'forge') {
        Copy-Item -Force $inst $OutDir
        Write-Host "Installer klaargezet: $(Split-Path $inst -Leaf)"
        Write-Host "Installeren: java -jar $(Split-Path $inst -Leaf) --installServer"
    } else {
        Write-Host "Fabric server-launcher klaargezet: $serverJar"
    }
} elseif ($loaderName -in 'neoforge', 'forge') {
    if (Test-Path (Join-Path $OutDir "$argsDir/win_args.txt")) {
        Write-Host 'Modloader is al geinstalleerd, overslaan'
    } else {
        Push-Location $OutDir
        try {
            & $java -jar $inst --installServer $OutDir
            if ($LASTEXITCODE -ne 0) { throw "Installer faalde (exit $LASTEXITCODE)" }
        } finally { Pop-Location }
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir '*installer.jar.log')
    }
    if (Test-Path (Join-Path $OutDir "$argsDir/win_args.txt")) {
        $winArgs = "@$argsDir/win_args.txt"; $unixArgs = "@$argsDir/unix_args.txt"
    } else {
        # Oude Forge (<1.17) maakt een losse jar
        $serverJar = (Get-ChildItem $OutDir -Filter 'forge-*.jar' | Where-Object { $_.Name -notlike '*installer*' } | Select-Object -First 1).Name
    }
}

# 6. Startscripts + eula ------------------------------------------------------
if (-not $FilesOnly) {
Write-Step 'Startscripts schrijven'
"-Xms$RamArg`r`n-Xmx$RamArg`r`n" | Set-Content (Join-Path $OutDir 'user_jvm_args.txt') -Encoding ASCII -NoNewline

if ($winArgs) { $launchWin = "$winArgs nogui"; $launchUnix = "$unixArgs nogui" }
else { $launchWin = "-jar $serverJar nogui"; $launchUnix = $launchWin }

@"
@echo off
cd /d "%~dp0"
:start
"$javaInStart" @user_jvm_args.txt $launchWin %*
echo.
echo Server gestopt. Herstart over 10 seconden, druk Ctrl+C om te stoppen.
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
  echo "Server gestopt. Herstart over 10 seconden, Ctrl+C om te stoppen."
  sleep 10
done
"@
[IO.File]::WriteAllText((Join-Path $OutDir 'start.sh'), ($sh -replace "`r`n", "`n"))

$eula = if ($AcceptEula) { 'true' } else { 'false' }
"# https://aka.ms/MinecraftEULA`r`neula=$eula`r`n" | Set-Content (Join-Path $OutDir 'eula.txt') -Encoding ASCII

# Overbodige installer-scripts van NeoForge/Forge opruimen (start.bat vervangt ze)
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir 'run.bat'), (Join-Path $OutDir 'run.sh')
}

# Samenvatting ----------------------------------------------------------------
Write-Step 'Klaar'
$modCount = @(Get-ChildItem $ModsDir -Filter *.jar).Count
Write-Host "Server staat in: $OutDir"
Write-Host "Mods op server:  $modCount   (client-only / resourcepacks overgeslagen: $($skipped.Count))"
if ($skipped.Count) { [IO.File]::WriteAllLines((Join-Path $OutDir 'skipped-client-mods.txt'), [string[]]($skipped | Sort-Object -Unique)); Write-Host "  lijst: skipped-client-mods.txt" }
if ($keptTagged.Count) { Write-Host "Toch op server (client-tag, maar met content): $($keptTagged -join ', ')" -ForegroundColor Green }
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $OutDir 'failed-mods.txt')
if ($failed.Count) {
    Write-Host "MISLUKT: $($failed.Count) mods - download deze handmatig naar extra-mods\ en draai opnieuw:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $failed | Set-Content (Join-Path $OutDir 'failed-mods.txt') -Encoding UTF8
}
if ($FilesOnly) {
    Write-Host 'Alleen bestanden: modloader niet geinstalleerd, geen startscripts/eula geschreven.' -ForegroundColor Yellow
} else {
    if (-not $AcceptEula) { Write-Host "Let op: eula.txt staat op false. Draai opnieuw met -AcceptEula of pas eula.txt aan." -ForegroundColor Yellow }
    Write-Host "Starten: $OutDir\start.bat" -ForegroundColor Green
}
