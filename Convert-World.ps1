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
# The id tables come from the KubeJS scripts: by default the kubejs folder next to the world (a server or
# instance), otherwise the GSPack repository's kubejs folder; -KubeJS <folder> picks another one.
# This same file ships with the GSPack repository (tools/) and the GSPack Server Installer.
# PowerShell 7 runs it on Linux too:  pwsh -File convert-world.ps1 -World ./server
param([string]$World = '', [string]$KubeJS = '', [switch]$DryRun, [switch]$Interactive, [switch]$Pick)
$ErrorActionPreference = 'Stop'
# Problems are shown as one plain message (not a PowerShell error with a stack trace) and exit with code 1.
trap { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; exit 1 }

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
if (-not $KubeJS) {
    $KubeJS = @((Join-Path (Split-Path $World -Parent) 'kubejs'), (Join-Path (Split-Path (Split-Path $World -Parent) -Parent) 'kubejs'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'kubejs')) | Where-Object { Test-Path (Join-Path (Join-Path $_ 'startup_scripts') 'gspack_unify_table.js') } | Select-Object -First 1
    if (-not $KubeJS) { throw 'No GSPack kubejs folder found next to the world. Pass -KubeJS <folder> (it needs GSPack 0.5 or newer).' }
}
$Scripts = Join-Path $KubeJS 'server_scripts'
"World:  $World"
"KubeJS: $KubeJS"

# The server must be stopped: Minecraft keeps session.lock open while the world is loaded.
$lock = Join-Path $World 'session.lock'
if (Test-Path $lock) {
    try { $fs = [IO.File]::Open($lock, 'Open', 'ReadWrite', 'None'); $fs.Close() }
    catch { throw "The world is in use ($lock is locked). Stop the server (or close the game) first." }
}

# ---------- id map from the KubeJS scripts ----------
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$unify = [IO.File]::ReadAllText((Join-Path (Join-Path $KubeJS 'startup_scripts') 'gspack_unify_table.js'))
foreach ($m in [regex]::Matches($unify, "\['([^']+)', '([^']+)', \[([^\]]*)\]\]")) {
    foreach ($o in [regex]::Matches($m.Groups[3].Value, "'([^']+)'")) { $map[$o.Groups[1].Value] = $m.Groups[2].Value }
}
$blocks = [IO.File]::ReadAllText((Join-Path $Scripts 'gspack_zz_unify_blocks.js'))
$oreBlock = [regex]::Match($blocks, '(?s)const GSPACK_BLOCK_TO = \{(.*?)\n\}').Groups[1].Value
foreach ($m in [regex]::Matches($oreBlock, "'([a-z0-9_]+:[a-z0-9_/]+)': '([a-z0-9_]+:[a-z0-9_/]+)'")) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
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
