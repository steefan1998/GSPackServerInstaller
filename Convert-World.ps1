# Converts an existing GSPack world to the unified materials while the server is OFF (no players needed).
# Every duplicate block and item id (kubejs/startup_scripts/gspack_unify_table.js and server_scripts/gspack_zz_unify_blocks.js)
# is replaced by the preferred id in:
#   - placed blocks (the block palette of every chunk), in all dimensions;
#   - items in chests, machines and other block entities, item entities, minecarts, ...;
#   - player inventories and ender chests (playerdata), and saved mod data (data/*.dat).
# Only exact id strings are replaced. Every file that changes is copied to <world>\gspack-convert-backup first.
#
# Usage (stop the server first):
#   powershell -ExecutionPolicy Bypass -File convert-world.ps1 -World "D:\Servers\GSPack"
#   -World is a world folder (with level.dat) or a server folder (the world named in server.properties).
#   Without -World it uses GSPackServer next to this script (the GSPack Server Installer's folder).
#   add -DryRun to only count what would change.
#   -Interactive: a dry run first, then it asks before converting.
#   -Pick: choose the folder in a File Explorer folder picker (Windows; with -Interactive).
# The id tables come from the kubejs folder next to the world (a server or instance on GSPack 0.5 or newer),
# or -KubeJS <folder>; without one it uses the copy built into this file, so any old world can be converted.
# This same file ships with the GSPack repository (tools/) and the GSPack Server Installer.
# PowerShell 7 runs it on Linux too:  pwsh -File convert-world.ps1 -World ./server
param([string]$World = '', [string]$KubeJS = '', [switch]$DryRun, [switch]$Interactive, [switch]$Pick, [switch]$UpdateBuiltIn)
$ErrorActionPreference = 'Stop'
# Problems are shown as one plain message (not a PowerShell error with a stack trace) and exit with code 1.
trap { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; exit 1 }

# The id tables built into this file ("old id new id" per line), used when the world has no GSPack 0.5 kubejs
# folder next to it. Pack makers refresh them from the repository's kubejs scripts after changing the tables:
#   powershell -ExecutionPolicy Bypass -File tools\convert-world.ps1 -UpdateBuiltIn
# >>> built-in tables
$BuiltInTable = @'
appflux:diamond_dust alltheores:diamond_dust
appflux:emerald_dust mekanism:dust_emerald
enderio:iron_gear alltheores:iron_gear
enderio:powdered_coal mekanism:dust_coal
enderio:powdered_copper alltheores:copper_dust
enderio:powdered_ender_pearl ae2:ender_dust
enderio:powdered_gold alltheores:gold_dust
enderio:powdered_iron alltheores:iron_dust
enderio:powdered_lapis_lazuli mekanism:dust_lapis_lazuli
enderio:powdered_obsidian mekanism:dust_obsidian
enderio:powdered_quartz mekanism:dust_quartz
enderio:powdered_tin alltheores:tin_dust
justdirethings:charcoal mekanism:block_charcoal
ltxi:copper_plate alltheores:copper_plate
ltxi:deepslate_silver_ore alltheores:deepslate_silver_ore
ltxi:fluorite alltheores:fluorite
ltxi:gold_plate alltheores:gold_plate
ltxi:raw_silver alltheores:raw_silver
ltxi:raw_silver_block alltheores:raw_silver_block
ltxi:raw_titanium stellaris:raw_titanium
ltxi:raw_titanium_block stellaris:raw_titanium_block
ltxi:silver_block alltheores:silver_block
ltxi:silver_dust alltheores:silver_dust
ltxi:silver_ingot alltheores:silver_ingot
ltxi:silver_nugget alltheores:silver_nugget
ltxi:silver_ore alltheores:silver_ore
ltxi:silver_plate alltheores:silver_plate
ltxi:sulfur_dust alltheores:sulfur_dust
ltxi:titanium_block stellaris:titanium_block
ltxi:titanium_ingot stellaris:titanium_ingot
ltxi:titanium_nugget stellaris:titanium_nugget
mekanism:block_bronze alltheores:bronze_block
mekanism:block_fluorite alltheores:fluorite_block
mekanism:block_lead alltheores:lead_block
mekanism:block_osmium alltheores:osmium_block
mekanism:block_raw_lead alltheores:raw_lead_block
mekanism:block_raw_osmium alltheores:raw_osmium_block
mekanism:block_raw_tin alltheores:raw_tin_block
mekanism:block_raw_uranium alltheores:raw_uranium_block
mekanism:block_steel alltheores:steel_block
mekanism:block_tin alltheores:tin_block
mekanism:block_uranium alltheores:uranium_block
mekanism:deepslate_fluorite_ore alltheores:deepslate_fluorite_ore
mekanism:deepslate_lead_ore alltheores:deepslate_lead_ore
mekanism:deepslate_osmium_ore alltheores:deepslate_osmium_ore
mekanism:deepslate_tin_ore alltheores:deepslate_tin_ore
mekanism:deepslate_uranium_ore alltheores:deepslate_uranium_ore
mekanism:dust_bronze alltheores:bronze_dust
mekanism:dust_copper alltheores:copper_dust
mekanism:dust_diamond alltheores:diamond_dust
mekanism:dust_fluorite alltheores:fluorite_dust
mekanism:dust_gold alltheores:gold_dust
mekanism:dust_iron alltheores:iron_dust
mekanism:dust_lead alltheores:lead_dust
mekanism:dust_netherite alltheores:netherite_dust
mekanism:dust_osmium alltheores:osmium_dust
mekanism:dust_steel alltheores:steel_dust
mekanism:dust_sulfur alltheores:sulfur_dust
mekanism:dust_tin alltheores:tin_dust
mekanism:dust_uranium alltheores:uranium_dust
mekanism:fluorite_gem alltheores:fluorite
mekanism:fluorite_ore alltheores:fluorite_ore
mekanism:ingot_bronze alltheores:bronze_ingot
mekanism:ingot_lead alltheores:lead_ingot
mekanism:ingot_osmium alltheores:osmium_ingot
mekanism:ingot_steel alltheores:steel_ingot
mekanism:ingot_tin alltheores:tin_ingot
mekanism:ingot_uranium alltheores:uranium_ingot
mekanism:lead_ore alltheores:lead_ore
mekanism:nugget_bronze alltheores:bronze_nugget
mekanism:nugget_lead alltheores:lead_nugget
mekanism:nugget_osmium alltheores:osmium_nugget
mekanism:nugget_steel alltheores:steel_nugget
mekanism:nugget_tin alltheores:tin_nugget
mekanism:nugget_uranium alltheores:uranium_nugget
mekanism:osmium_ore alltheores:osmium_ore
mekanism:raw_lead alltheores:raw_lead
mekanism:raw_osmium alltheores:raw_osmium
mekanism:raw_tin alltheores:raw_tin
mekanism:raw_uranium alltheores:raw_uranium
mekanism:salt alltheores:salt_dust
mekanism:tin_ore alltheores:tin_ore
mekanism:uranium_ore alltheores:uranium_ore
mekmm:block_raw_silver alltheores:raw_silver_block
mekmm:block_silver alltheores:silver_block
mekmm:deepslate_silver_ore alltheores:deepslate_silver_ore
mekmm:dust_silver alltheores:silver_dust
mekmm:ingot_silver alltheores:silver_ingot
mekmm:nugget_silver alltheores:silver_nugget
mekmm:raw_silver alltheores:raw_silver
mekmm:silver_ore alltheores:silver_ore
occultism:copper_dust alltheores:copper_dust
occultism:emerald_dust mekanism:dust_emerald
occultism:gold_dust alltheores:gold_dust
occultism:iron_dust alltheores:iron_dust
occultism:lapis_dust mekanism:dust_lapis_lazuli
occultism:netherite_dust alltheores:netherite_dust
occultism:obsidian_dust mekanism:dust_obsidian
occultism:raw_silver alltheores:raw_silver
occultism:raw_silver_block alltheores:raw_silver_block
occultism:silver_block alltheores:silver_block
occultism:silver_dust alltheores:silver_dust
occultism:silver_ingot alltheores:silver_ingot
occultism:silver_nugget alltheores:silver_nugget
occultism:silver_ore alltheores:silver_ore
occultism:silver_ore_deepslate alltheores:deepslate_silver_ore
oritech:coal_dust mekanism:dust_coal
oritech:copper_dust alltheores:copper_dust
oritech:deepslate_nickel_ore alltheores:deepslate_nickel_ore
oritech:deepslate_platinum_ore alltheores:deepslate_platinum_ore
oritech:deepslate_uranium_ore alltheores:deepslate_uranium_ore
oritech:electrum alltheores:electrum_block
oritech:electrum_dust alltheores:electrum_dust
oritech:electrum_ingot alltheores:electrum_ingot
oritech:endstone_platinum_ore alltheores:end_platinum_ore
oritech:gold_dust alltheores:gold_dust
oritech:iron_dust alltheores:iron_dust
oritech:nickel alltheores:nickel_block
oritech:nickel_dust alltheores:nickel_dust
oritech:nickel_ingot alltheores:nickel_ingot
oritech:nickel_nugget alltheores:nickel_nugget
oritech:nickel_ore alltheores:nickel_ore
oritech:platinum alltheores:platinum_block
oritech:platinum_dust alltheores:platinum_dust
oritech:platinum_ingot alltheores:platinum_ingot
oritech:platinum_nugget alltheores:platinum_nugget
oritech:quartz_dust mekanism:dust_quartz
oritech:raw_nickel alltheores:raw_nickel
oritech:raw_nickel_block alltheores:raw_nickel_block
oritech:raw_platinum alltheores:raw_platinum
oritech:raw_platinum_block alltheores:raw_platinum_block
oritech:raw_uranium alltheores:raw_uranium
oritech:raw_uranium_block alltheores:raw_uranium_block
oritech:silicon_block extendedae:silicon_block
oritech:steel alltheores:steel_block
oritech:steel_dust alltheores:steel_dust
oritech:steel_ingot alltheores:steel_ingot
oritech:uranium_dust alltheores:uranium_dust
railcraft:brass_block alltheores:brass_block
railcraft:brass_gear alltheores:brass_gear
railcraft:brass_ingot alltheores:brass_ingot
railcraft:brass_nugget alltheores:brass_nugget
railcraft:brass_plate alltheores:brass_plate
railcraft:bronze_block alltheores:bronze_block
railcraft:bronze_gear alltheores:bronze_gear
railcraft:bronze_ingot alltheores:bronze_ingot
railcraft:bronze_nugget alltheores:bronze_nugget
railcraft:bronze_plate alltheores:bronze_plate
railcraft:charcoal_dust mekanism:dust_charcoal
railcraft:coal_dust mekanism:dust_coal
railcraft:copper_gear alltheores:copper_gear
railcraft:copper_plate alltheores:copper_plate
railcraft:deepslate_lead_ore alltheores:deepslate_lead_ore
railcraft:deepslate_nickel_ore alltheores:deepslate_nickel_ore
railcraft:deepslate_silver_ore alltheores:deepslate_silver_ore
railcraft:deepslate_sulfur_ore alltheores:deepslate_sulfur_ore
railcraft:deepslate_tin_ore alltheores:deepslate_tin_ore
railcraft:deepslate_zinc_ore alltheores:deepslate_zinc_ore
railcraft:ender_dust ae2:ender_dust
railcraft:gold_gear alltheores:gold_gear
railcraft:gold_plate alltheores:gold_plate
railcraft:invar_block alltheores:invar_block
railcraft:invar_gear alltheores:invar_gear
railcraft:invar_ingot alltheores:invar_ingot
railcraft:invar_nugget alltheores:invar_nugget
railcraft:invar_plate alltheores:invar_plate
railcraft:iron_gear alltheores:iron_gear
railcraft:iron_plate alltheores:iron_plate
railcraft:lead_block alltheores:lead_block
railcraft:lead_gear alltheores:lead_gear
railcraft:lead_ingot alltheores:lead_ingot
railcraft:lead_nugget alltheores:lead_nugget
railcraft:lead_ore alltheores:lead_ore
railcraft:lead_plate alltheores:lead_plate
railcraft:lead_raw alltheores:raw_lead
railcraft:nickel_block alltheores:nickel_block
railcraft:nickel_gear alltheores:nickel_gear
railcraft:nickel_ingot alltheores:nickel_ingot
railcraft:nickel_nugget alltheores:nickel_nugget
railcraft:nickel_ore alltheores:nickel_ore
railcraft:nickel_plate alltheores:nickel_plate
railcraft:nickel_raw alltheores:raw_nickel
railcraft:obsidian_dust mekanism:dust_obsidian
railcraft:silver_block alltheores:silver_block
railcraft:silver_gear alltheores:silver_gear
railcraft:silver_ingot alltheores:silver_ingot
railcraft:silver_nugget alltheores:silver_nugget
railcraft:silver_ore alltheores:silver_ore
railcraft:silver_plate alltheores:silver_plate
railcraft:silver_raw alltheores:raw_silver
railcraft:steel_block alltheores:steel_block
railcraft:steel_gear alltheores:steel_gear
railcraft:steel_ingot alltheores:steel_ingot
railcraft:steel_nugget alltheores:steel_nugget
railcraft:steel_plate alltheores:steel_plate
railcraft:sulfur_dust alltheores:sulfur_dust
railcraft:sulfur_ore alltheores:sulfur_ore
railcraft:tin_block alltheores:tin_block
railcraft:tin_gear alltheores:tin_gear
railcraft:tin_ingot alltheores:tin_ingot
railcraft:tin_nugget alltheores:tin_nugget
railcraft:tin_ore alltheores:tin_ore
railcraft:tin_plate alltheores:tin_plate
railcraft:tin_raw alltheores:raw_tin
railcraft:zinc_block alltheores:zinc_block
railcraft:zinc_gear alltheores:zinc_gear
railcraft:zinc_ingot alltheores:zinc_ingot
railcraft:zinc_nugget alltheores:zinc_nugget
railcraft:zinc_ore alltheores:zinc_ore
railcraft:zinc_plate alltheores:zinc_plate
railcraft:zinc_raw alltheores:raw_zinc
tconstruct:knightmetal_block twilightforest:knightmetal_block
tconstruct:knightmetal_ingot twilightforest:knightmetal_ingot
tconstruct:steel_block alltheores:steel_block
tconstruct:steel_ingot alltheores:steel_ingot
tconstruct:steel_nugget alltheores:steel_nugget
thaumaturge:ingot_brass alltheores:brass_ingot
thaumaturge:metal_brass alltheores:brass_block
thaumaturge:nugget_brass alltheores:brass_nugget
thaumaturge:plate_brass alltheores:brass_plate
thaumaturge:plate_iron alltheores:iron_plate
'@
# <<< built-in tables

if ($UpdateBuiltIn) {
    $kjs = Join-Path (Split-Path $PSScriptRoot -Parent) 'kubejs'
    $rows = New-Object 'System.Collections.Generic.SortedDictionary[string,string]'
    $unify = [IO.File]::ReadAllText((Join-Path (Join-Path $kjs 'startup_scripts') 'gspack_unify_table.js'))
    foreach ($m in [regex]::Matches($unify, "\['([^']+)', '([^']+)', \[([^\]]*)\]\]")) {
        foreach ($o in [regex]::Matches($m.Groups[3].Value, "'([^']+)'")) { $rows[$o.Groups[1].Value] = $m.Groups[2].Value }
    }
    $blocks = [IO.File]::ReadAllText((Join-Path (Join-Path $kjs 'server_scripts') 'gspack_zz_unify_blocks.js'))
    $oreBlock = [regex]::Match($blocks, '(?s)const GSPACK_BLOCK_TO = \{(.*?)\n\}').Groups[1].Value
    foreach ($m in [regex]::Matches($oreBlock, "'([a-z0-9_]+:[a-z0-9_/]+)': '([a-z0-9_]+:[a-z0-9_/]+)'")) { $rows[$m.Groups[1].Value] = $m.Groups[2].Value }
    $table = ($rows.Keys | ForEach-Object { "$_ $($rows[$_])" }) -join "`n"
    $self = [IO.File]::ReadAllText($PSCommandPath)
    $self = [regex]::Replace($self, "(?s)(# >>> built-in tables\r?\n\`$BuiltInTable = @').*?(\r?\n'@\r?\n# <<< built-in tables)", { param($m) $m.Groups[1].Value + "`n" + $table + $m.Groups[2].Value })
    [IO.File]::WriteAllText($PSCommandPath, $self, (New-Object Text.UTF8Encoding($false)))
    "Built-in tables updated: $($rows.Count) ids."
    exit 0
}

if ($Interactive) {
    if ($Pick) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Choose the server folder (or a world folder) to convert to GSPack 0.5. Stop the server first.'
        $dialog.ShowNewFolderButton = $false
        $start = $(if ($World) { $World } else { Join-Path $PSScriptRoot 'GSPackServer' })
        if (Test-Path $start) { $dialog.SelectedPath = (Resolve-Path $start).Path }
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { 'Cancelled, nothing changed.'; exit 0 }
        $World = $dialog.SelectedPath
    }
    $common = @{ World = $World }; if ($KubeJS) { $common.KubeJS = $KubeJS }
    & $PSCommandPath @common -DryRun
    if ($LASTEXITCODE) { exit 1 }   # the dry run explained the problem
    ''
    $answer = Read-Host 'Convert the world now? Changed files are backed up first. [y/N]'
    if ($answer -match '^(y|j)') { & $PSCommandPath @common } else { 'Nothing changed.' }
    exit 0
}

if (-not $World) { $World = Join-Path $PSScriptRoot 'GSPackServer' }
if (-not (Test-Path $World)) { throw "Folder not found: $World" }
$World = (Resolve-Path $World).Path.TrimEnd([char]92, [char]47)
# A server folder: use the world named in server.properties (level-name, default "world").
if (-not (Test-Path (Join-Path $World 'level.dat')) -and (Test-Path (Join-Path $World 'server.properties'))) {
    $level = (Get-Content (Join-Path $World 'server.properties') | Where-Object { $_ -match '^level-name=' } | Select-Object -First 1) -replace '^level-name=', ''
    if (-not $level) { $level = 'world' }
    $World = Join-Path $World $level
}
if (-not (Test-Path (Join-Path $World 'level.dat'))) {
    # A server folder that was never started (start.bat but no world), or the world folder named in server.properties.
    if ((Test-Path (Join-Path $World 'start.bat')) -or (Test-Path (Join-Path (Split-Path $World -Parent) 'server.properties'))) {
        throw "This server has no world yet: it was never started, so there is nothing to convert.`nA world that is created with GSPack 0.5 or newer doesn't need converting; only worlds from 0.4 or older do.`n($World has no level.dat)"
    }
    throw "No Minecraft world in $World (there is no level.dat).`nChoose a server folder (the one with server.properties) or a world folder (the one with level.dat)."
}
function Test-GspackKubeJS([string]$dir) {
    $dir -and (Test-Path (Join-Path (Join-Path $dir 'startup_scripts') 'gspack_unify_table.js')) -and
        (Test-Path (Join-Path (Join-Path $dir 'server_scripts') 'gspack_zz_unify_blocks.js'))
}
if ($KubeJS -and -not (Test-GspackKubeJS $KubeJS)) { throw "$KubeJS is not a GSPack 0.5 (or newer) kubejs folder." }
if (-not $KubeJS) {
    # The kubejs folder of the server or instance next to the world, if it has the GSPack 0.5 tables.
    # Otherwise the tables built into this file are used (a world copied on its own, or a server still on 0.4).
    $KubeJS = @((Join-Path (Split-Path $World -Parent) 'kubejs'), (Join-Path (Split-Path (Split-Path $World -Parent) -Parent) 'kubejs'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'kubejs')) | Where-Object { Test-GspackKubeJS $_ } | Select-Object -First 1
}
"World:  $World"
"Tables: $(if ($KubeJS) { $KubeJS } else { 'built into this tool (GSPack 0.5)' })"

# The server must be stopped: Minecraft keeps session.lock open while the world is loaded.
$lock = Join-Path $World 'session.lock'
if (Test-Path $lock) {
    try { $fs = [IO.File]::Open($lock, 'Open', 'ReadWrite', 'None'); $fs.Close() }
    catch { throw "The world is in use ($lock is locked). Stop the server (or close the game) first." }
}

# ---------- id map: from the KubeJS scripts, or the built-in copy ----------
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
if ($KubeJS) {
    $unify = [IO.File]::ReadAllText((Join-Path (Join-Path $KubeJS 'startup_scripts') 'gspack_unify_table.js'))
    foreach ($m in [regex]::Matches($unify, "\['([^']+)', '([^']+)', \[([^\]]*)\]\]")) {
        foreach ($o in [regex]::Matches($m.Groups[3].Value, "'([^']+)'")) { $map[$o.Groups[1].Value] = $m.Groups[2].Value }
    }
    $blocks = [IO.File]::ReadAllText((Join-Path (Join-Path $KubeJS 'server_scripts') 'gspack_zz_unify_blocks.js'))
    $oreBlock = [regex]::Match($blocks, '(?s)const GSPACK_BLOCK_TO = \{(.*?)\n\}').Groups[1].Value
    foreach ($m in [regex]::Matches($oreBlock, "'([a-z0-9_]+:[a-z0-9_/]+)': '([a-z0-9_]+:[a-z0-9_/]+)'")) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
} else {
    foreach ($line in ($BuiltInTable -split "`n")) {
        $from, $to = $line.Trim() -split ' ', 2
        if ($to) { $map[$from] = $to }
    }
}
"$($map.Count) duplicate ids will be replaced."

# ---------- NBT / region rewriting (C#) ----------
# Loaded once per session (the -Interactive mode runs this script again in the same session).
if (-not ('GspackWorld' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Text;
public static class GspackWorld {
    static Dictionary<byte[], byte[]> Map;
    class BytesComparer : IEqualityComparer<byte[]> {
        public bool Equals(byte[] a, byte[] b) { if (a.Length != b.Length) return false; for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false; return true; }
        public int GetHashCode(byte[] a) { int h = 17; foreach (byte x in a) h = h * 31 + x; return h; }
    }
    public static void SetMap(Dictionary<string, string> map) {
        Map = new Dictionary<byte[], byte[]>(new BytesComparer());
        foreach (var kv in map) Map[Encoding.UTF8.GetBytes(kv.Key)] = Encoding.UTF8.GetBytes(kv.Value);
    }
    // Copies an NBT payload from r to w, replacing TAG_String values that are in the map. Returns replacements.
    static int Payload(BinaryReader r, BinaryWriter w, byte type) {
        int n = 0;
        switch (type) {
            case 1: w.Write(r.ReadByte()); break;
            case 2: w.Write(r.ReadBytes(2)); break;
            case 3: case 5: w.Write(r.ReadBytes(4)); break;
            case 4: case 6: w.Write(r.ReadBytes(8)); break;
            case 7: { byte[] l = r.ReadBytes(4); w.Write(l); w.Write(r.ReadBytes(BE(l))); break; }
            case 8: {
                byte[] l = r.ReadBytes(2); int len = (l[0] << 8) | l[1]; byte[] s = r.ReadBytes(len); byte[] to;
                if (Map.TryGetValue(s, out to)) { w.Write((byte)(to.Length >> 8)); w.Write((byte)to.Length); w.Write(to); n++; }
                else { w.Write(l); w.Write(s); }
                break;
            }
            case 9: { byte t = r.ReadByte(); byte[] c = r.ReadBytes(4); w.Write(t); w.Write(c); int cnt = BE(c); for (int i = 0; i < cnt; i++) n += Payload(r, w, t); break; }
            case 10: while (true) { byte t = r.ReadByte(); w.Write(t); if (t == 0) break; byte[] l = r.ReadBytes(2); w.Write(l); w.Write(r.ReadBytes((l[0] << 8) | l[1])); n += Payload(r, w, t); } break;
            case 11: { byte[] l = r.ReadBytes(4); w.Write(l); w.Write(r.ReadBytes(BE(l) * 4)); break; }
            case 12: { byte[] l = r.ReadBytes(4); w.Write(l); w.Write(r.ReadBytes(BE(l) * 8)); break; }
            default: throw new InvalidDataException("Unknown NBT tag " + type);
        }
        return n;
    }
    static int BE(byte[] b) { return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; }
    public static byte[] RewriteNbt(byte[] nbt, out int count) {
        var r = new BinaryReader(new MemoryStream(nbt)); var ms = new MemoryStream(); var w = new BinaryWriter(ms);
        byte t = r.ReadByte(); w.Write(t); count = 0;
        if (t != 0) { byte[] l = r.ReadBytes(2); w.Write(l); w.Write(r.ReadBytes((l[0] << 8) | l[1])); count = Payload(r, w, t); }
        w.Flush(); return ms.ToArray();
    }
    static byte[] Inflate(byte[] data, int off, int len, bool gzip) {
        var src = new MemoryStream(data, off, len); var dst = new MemoryStream();
        if (gzip) { using (var z = new GZipStream(src, CompressionMode.Decompress)) z.CopyTo(dst); }
        else { src.Position += 2; using (var z = new DeflateStream(src, CompressionMode.Decompress)) z.CopyTo(dst); }
        return dst.ToArray();
    }
    static byte[] Deflate(byte[] data, bool gzip) {
        var dst = new MemoryStream();
        if (gzip) { using (var z = new GZipStream(dst, CompressionLevel.Optimal, true)) z.Write(data, 0, data.Length); return dst.ToArray(); }
        dst.WriteByte(0x78); dst.WriteByte(0x9C);
        using (var z = new DeflateStream(dst, CompressionLevel.Optimal, true)) z.Write(data, 0, data.Length);
        uint a = 1, b = 0; foreach (byte x in data) { a = (a + x) % 65521; b = (b + a) % 65521; }
        uint adler = (b << 16) | a; dst.WriteByte((byte)(adler >> 24)); dst.WriteByte((byte)(adler >> 16)); dst.WriteByte((byte)(adler >> 8)); dst.WriteByte((byte)adler);
        return dst.ToArray();
    }
    // A gzipped NBT file (playerdata, data). Returns the new bytes, or null when nothing changed.
    public static byte[] RewriteGzipFile(byte[] file, out int count) {
        byte[] nbt = RewriteNbt(Inflate(file, 0, file.Length, true), out count);
        return count == 0 ? null : Deflate(nbt, true);
    }
    // A region file (.mca). Returns the new file, or null when nothing changed. skipped = chunks left as they were.
    public static byte[] RewriteRegion(byte[] f, out int count, out int skipped) {
        count = 0; skipped = 0;
        if (f.Length < 8192) return null;
        var chunks = new byte[1024][]; bool changed = false;
        for (int i = 0; i < 1024; i++) {
            int loc = (f[i * 4] << 24) | (f[i * 4 + 1] << 16) | (f[i * 4 + 2] << 8) | f[i * 4 + 3];
            int offset = (loc >> 8) & 0xFFFFFF; if (offset == 0) continue;
            int pos = offset * 4096; if (pos + 5 > f.Length) continue;
            int len = (f[pos] << 24) | (f[pos + 1] << 16) | (f[pos + 2] << 8) | f[pos + 3];
            if (len <= 0 || pos + 4 + len > f.Length) continue;
            byte ctype = f[pos + 4];
            var raw = new byte[4 + len]; Array.Copy(f, pos, raw, 0, 4 + len); chunks[i] = raw;
            if (ctype != 1 && ctype != 2 && ctype != 3) { skipped++; continue; }   // LZ4 or an external .mcc chunk
            byte[] nbt = ctype == 3 ? Sub(f, pos + 5, len - 1) : Inflate(f, pos + 5, len - 1, ctype == 1);
            int n; byte[] outNbt = RewriteNbt(nbt, out n);
            if (n == 0) continue;
            byte[] packed = ctype == 3 ? outNbt : Deflate(outNbt, ctype == 1);
            if ((packed.Length + 5 + 4095) / 4096 > 255) { skipped++; continue; }    // would need an external chunk file
            var nc = new byte[5 + packed.Length]; int nl = packed.Length + 1;
            nc[0] = (byte)(nl >> 24); nc[1] = (byte)(nl >> 16); nc[2] = (byte)(nl >> 8); nc[3] = (byte)nl; nc[4] = ctype;
            Array.Copy(packed, 0, nc, 5, packed.Length); chunks[i] = nc; count += n; changed = true;
        }
        if (!changed) return null;
        var o = new MemoryStream(); o.Write(new byte[8192], 0, 8192); var header = new byte[8192];
        Array.Copy(f, 4096, header, 4096, 4096);   // timestamps stay
        int sector = 2;
        for (int i = 0; i < 1024; i++) {
            if (chunks[i] == null) continue;
            int sectors = (chunks[i].Length + 4095) / 4096;
            o.Write(chunks[i], 0, chunks[i].Length); o.Write(new byte[sectors * 4096 - chunks[i].Length], 0, sectors * 4096 - chunks[i].Length);
            int loc = (sector << 8) | sectors; header[i * 4] = (byte)(loc >> 24); header[i * 4 + 1] = (byte)(loc >> 16); header[i * 4 + 2] = (byte)(loc >> 8); header[i * 4 + 3] = (byte)loc;
            sector += sectors;
        }
        byte[] result = o.ToArray(); Array.Copy(header, 0, result, 0, 8192); return result;
    }
    static byte[] Sub(byte[] a, int off, int len) { var r = new byte[len]; Array.Copy(a, off, r, 0, len); return r; }
}
'@
}
[GspackWorld]::SetMap($map)

$backup = Join-Path $World 'gspack-convert-backup'
$total = 0; $files = 0; $skippedChunks = 0
function Save-Changed([IO.FileInfo]$file, [byte[]]$bytes, [int]$n) {
    $script:total += $n; $script:files++
    $rel = $file.FullName.Substring($World.Length + 1)
    '  {0,6}  {1}' -f $n, $rel
    if ($DryRun) { return }
    $dest = Join-Path $backup $rel
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    if (-not (Test-Path $dest)) { Copy-Item $file.FullName $dest }
    $tmp = "$($file.FullName).gspack-tmp"
    [IO.File]::WriteAllBytes($tmp, $bytes)
    Move-Item -Force $tmp $file.FullName
}

# Region files: blocks and block entities (region), and entities (entities) of every dimension.
$regionFiles = Get-ChildItem $World -Recurse -Filter *.mca | Where-Object { $_.FullName -notlike "$backup*" -and $_.Directory.Name -in @('region', 'entities') }
"Scanning $($regionFiles.Count) region files..."
foreach ($f in $regionFiles) {
    $n = 0; $skip = 0
    $out = [GspackWorld]::RewriteRegion([IO.File]::ReadAllBytes($f.FullName), [ref]$n, [ref]$skip)
    $script:skippedChunks += $skip
    if ($out) { Save-Changed $f $out $n }
}
# Players (inventories, ender chests) and saved mod data.
$nbtFiles = @(Get-ChildItem (Join-Path $World 'playerdata') -Filter *.dat -ErrorAction SilentlyContinue) +
    @(Get-ChildItem (Join-Path $World 'data') -Filter *.dat -Recurse -ErrorAction SilentlyContinue)
foreach ($f in $nbtFiles) {
    $n = 0
    try { $out = [GspackWorld]::RewriteGzipFile([IO.File]::ReadAllBytes($f.FullName), [ref]$n) } catch { "  skipped (not gzip NBT): $($f.Name)"; continue }
    if ($out) { Save-Changed $f $out $n }
}

$mode = $(if ($DryRun) { 'Dry run: would replace' } else { 'Replaced' })
"$mode $total ids in $files files."
if ($skippedChunks) { "$skippedChunks chunks were left as they were (LZ4 compression or very large chunks); the in-game converter handles those when they load." }
if (-not $DryRun -and $files) { "Originals of the changed files: $backup (delete it once the world works)." }
