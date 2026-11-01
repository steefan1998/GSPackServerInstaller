#!/usr/bin/env bash
# Builds a ready-to-run Minecraft server from a CurseForge modpack (GSPack) - Linux/macOS.
# Works the same as Build-ServerPack.ps1:
#   get client zip -> download mods (client-only left out) -> overrides -> mod loader
#   -> Java (portable Temurin if missing) -> start.sh, user_jvm_args.txt, eula.txt
#
# Requires: bash, curl, unzip, jq   (Debian/Ubuntu: sudo apt install curl unzip jq)
#
# Usage:
#   ./build-serverpack.sh --zip GSPack-0.1.zip --accept-eula
#   ./build-serverpack.sh --project 1234567 --accept-eula        # straight from CurseForge
#
# Options:
#   --zip PATH           CurseForge export zip (client pack)
#   --project ID         CurseForge project ID of the modpack
#   --file ID            specific file ID of the pack (default: latest)
#   --out DIR            output folder (default: ./<PackName>Server, e.g. ./GSPackServer)
#   --accept-eula        set eula=true (https://aka.ms/MinecraftEULA)
#   --ram MB             memory in MB (default 8192 = 8 GB)
#   --java PATH          path to java
#   --exclude REGEX      extra mod (file name) that must not go on the server; repeatable
#   --keep-client-mods   skip the client-only filter
#   --files-only         only the folders (mods, config, ...) + mod loader installer;
#                        installs nothing, no Java, no start scripts
set -euo pipefail

UA='Mozilla/5.0 (GSPack server builder)'
CF='https://www.curseforge.com/api/v1'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ZIP= PROJECT= FILEID= OUT= EULA=false RAM= JAVA_ARG= KEEP_CLIENT=false FILES_ONLY=false
EXCLUDES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --file) FILEID="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --accept-eula) EULA=true; shift ;;
    --ram) RAM="$2"; shift 2 ;;
    --java) JAVA_ARG="$2"; shift 2 ;;
    --exclude) EXCLUDES+=("$2"); shift 2 ;;
    --keep-client-mods) KEEP_CLIENT=true; shift ;;
    --files-only) FILES_ONLY=true; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
if [ -z "$ZIP" ] && [ -z "$PROJECT" ]; then echo "Pass --zip or --project (see --help)" >&2; exit 1; fi
for bin in curl unzip jq; do
  command -v "$bin" >/dev/null || { echo "'$bin' is missing. Install: sudo apt install curl unzip jq" >&2; exit 1; }
done

# Mods often tagged Client+Server that only work client-side
KNOWN_CLIENT_ONLY='^(oculus|iris|sodium|embeddium|rubidium|entityculling|fancymenu|drippyloadingscreen|konkrete|legendarytooltips|betterf3|jeresources-client|mousetweaks|appleskin-client|ding|notenoughanimations|citresewn|entity_?texture_?features|entity_?model_?features|skinlayers3d|3dskinlayers|firstperson|cherishedworlds|controlling|searchables|catalogue|configured-client|betterthirdperson|shulkerboxtooltip-client|xaerominimap-client|modernfix-client|immediatelyfast|enhancedvisuals|presencefootsteps|soundphysics|ambientsounds|dynamiclights|lambdynamiclights|sodiumdynamiclights|chat_heads|chatheads|blur|loadmyresources|yeetusexperimentus)'
for e in "${EXCLUDES[@]+"${EXCLUDES[@]}"}"; do KNOWN_CLIENT_ONLY="$KNOWN_CLIENT_ONLY|$e"; done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
dl() { # dl URL DEST  (with retries, follows redirects)
  curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -o "$2.part" "$1" && mv -f "$2.part" "$2"
}
getjson() { curl -fsSL --retry 3 --retry-delay 2 -A "$UA" "$1"; }

# Cache lives next to the script so the server folder stays clean
CACHE="$SCRIPT_DIR/.cache"; MODCACHE="$CACHE/mods"; META="$CACHE/meta"
mkdir -p "$MODCACHE" "$META"

# 1. Get the client pack -----------------------------------------------------
if [ -n "$PROJECT" ]; then
  step "Fetching modpack from CurseForge (project $PROJECT)"
  if [ -z "$FILEID" ]; then
    FILEID="$(getjson "$CF/mods/$PROJECT/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=true" \
      | jq -r '[.data[] | select(.fileName | endswith(".zip"))][0].id // empty')"
    [ -n "$FILEID" ] || { echo "No pack file found for project $PROJECT (is it approved yet?)" >&2; exit 1; }
    echo "Latest version: file $FILEID"
  fi
  ZIP="$CACHE/pack-$FILEID.zip"
  [ -f "$ZIP" ] || dl "$CF/mods/$PROJECT/files/$FILEID/download" "$ZIP"
fi
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"

step "Extracting pack: $ZIP"
PACK="$CACHE/pack"
rm -rf "$PACK"; mkdir -p "$PACK"
unzip -q "$ZIP" -d "$PACK"
MANIFEST="$PACK/manifest.json"
[ -f "$MANIFEST" ] || { echo "No manifest.json in $ZIP - is this a CurseForge export?" >&2; exit 1; }

MC="$(jq -r '.minecraft.version' "$MANIFEST")"
LOADER="$(jq -r '(.minecraft.modLoaders | map(select(.primary)) + .minecraft.modLoaders)[0].id' "$MANIFEST")"
TOTAL="$(jq '.files | length' "$MANIFEST")"
echo "$(jq -r '"\(.name) \(.version)"' "$MANIFEST") - Minecraft $MC, $LOADER, $TOTAL mods"
RAM="${RAM:-8192}"
# Write as G when it's a whole number of GB (8192 -> 8G)
if [ $((RAM % 1024)) -eq 0 ]; then RAMARG="$((RAM / 1024))G"; else RAMARG="${RAM}M"; fi

# Default output folder: <PackName>Server next to this script, e.g. GSPackServer
OUT="${OUT:-$SCRIPT_DIR/$(jq -r '.name' "$MANIFEST" | tr -cd 'A-Za-z0-9_.-')Server}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
echo "Output folder: $OUT"

# 2. Download mods ------------------------------------------------------------
step 'Downloading mods'
MODS="$OUT/mods"
rm -rf "$MODS"; mkdir -p "$MODS"
SKIPPED="$CACHE/skipped.tmp"; FAILED="$CACHE/failed.tmp"; KEPT="$CACHE/kept.tmp"
: > "$SKIPPED"; : > "$FAILED"; : > "$KEPT"
# A jar with blocks or server data (recipes, loot tables, worldgen) has to be on the
# server too, even if CurseForge tags it client-only.
has_server_content() {
  unzip -Z1 "$1" 2>/dev/null | grep -Eq '^assets/[^/]+/blockstates/|^data/[^/]+/(recipes?|loot_tables?|worldgen)/'
}
n=0
while read -r pid fid; do
  n=$((n + 1))
  metaf="$META/$fid.json"
  if [ ! -s "$metaf" ]; then
    if ! getjson "$CF/mods/$pid/files/$fid" | jq '.data' > "$metaf.part"; then
      rm -f "$metaf.part"
      echo "project $pid / file $fid (couldn't fetch info) -> https://www.curseforge.com/projects/$pid" >> "$FAILED"
      printf '\033[31m[%s/%s] FAILED project %s file %s\033[0m\n' "$n" "$TOTAL" "$pid" "$fid"; continue
    fi
    mv -f "$metaf.part" "$metaf"
  fi
  name="$(jq -r '.fileName' "$metaf")"
  size="$(jq -r '.fileLength' "$metaf")"

  case "$name" in
    *.jar) ;;
    *) # Resource/shader packs don't belong on the server
       echo "$name" >> "$SKIPPED"
       printf '\033[33m[%s/%s] not a mod (resource/shader pack), skipped: %s\033[0m\n' "$n" "$TOTAL" "$name"; continue ;;
  esac

  cached="$MODCACHE/$fid.jar"
  if [ ! -f "$cached" ] || [ "$(wc -c < "$cached" | tr -d ' ')" != "$size" ]; then
    echo "[$n/$TOTAL] download $name"
    if ! dl "$CF/mods/$pid/files/$fid/download" "$cached"; then
      echo "project $pid / file $fid ($name) -> https://www.curseforge.com/projects/$pid" >> "$FAILED"
      printf '\033[31m[%s/%s] FAILED %s\033[0m\n' "$n" "$TOTAL" "$name"; continue
    fi
  else
    printf '\033[90m[%s/%s] cached   %s\033[0m\n' "$n" "$TOTAL" "$name"
  fi

  if [ "$KEEP_CLIENT" = false ]; then
    clientonly="$(jq -r '(.gameVersions | index("Client") != null) and (.gameVersions | index("Server") == null)' "$metaf")"
    if [ "$clientonly" = true ] || printf '%s' "$name" | grep -Eiq "$KNOWN_CLIENT_ONLY"; then
      if has_server_content "$cached"; then
        # Mis-tagged (e.g. Equivox): without this mod clients can't join
        echo "$name" >> "$KEPT"
        printf '\033[32m[%s/%s] client tag but has blocks/recipes, kept on server: %s\033[0m\n' "$n" "$TOTAL" "$name"
      else
        echo "$name" >> "$SKIPPED"
        printf '\033[33m[%s/%s] client-only, skipped: %s\033[0m\n' "$n" "$TOTAL" "$name"; continue
      fi
    fi
  fi
  cp -f "$cached" "$MODS/$name"
done < <(jq -r '.files[] | "\(.projectID) \(.fileID)"' "$MANIFEST")

# 3. Overrides ----------------------------------------------------------------
step 'Copying overrides'
for ov in "$(jq -r '.overrides // "overrides"' "$MANIFEST")" server-overrides; do
  if [ -d "$PACK/$ov" ]; then echo "  $ov/ -> server"; cp -rf "$PACK/$ov/." "$OUT/"; fi
done
# Your own server-only mods: put them in <out>/extra-mods, they're kept
mkdir -p "$OUT/extra-mods"
for j in "$OUT"/extra-mods/*.jar; do [ -e "$j" ] && { cp -f "$j" "$MODS/"; echo "  extra mod: $(basename "$j")"; }; done
# Also remove client-only mods that came in through the overrides
if [ "$KEEP_CLIENT" = false ]; then
  for j in "$MODS"/*.jar; do
    [ -e "$j" ] || continue
    if basename "$j" | grep -Eiq "$KNOWN_CLIENT_ONLY"; then basename "$j" >> "$SKIPPED"; rm -f "$j"; fi
  done
fi

# 4. Java ---------------------------------------------------------------------
JAVA=
if [ "$FILES_ONLY" = false ]; then
  step 'Checking Java'
  JAVA_NEEDED=21
  if vurl="$(getjson https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r --arg v "$MC" '.versions[] | select(.id == $v) | .url' | head -1)" && [ -n "$vurl" ]; then
    JAVA_NEEDED="$(getjson "$vurl" | jq -r '.javaVersion.majorVersion // 21')"
  fi
  echo "Minecraft $MC needs Java $JAVA_NEEDED"

  java_major() {
    [ -n "$1" ] && [ -x "$1" ] || { echo 0; return; }
    "$1" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+)(\.([0-9]+))?.*/\1 \3/' |
      awk '{ if ($1 == "1") print $2; else print $1 }'
  }
  LOCAL_JAVA="$OUT/java/bin/java"
  for c in "$JAVA_ARG" "$LOCAL_JAVA" "${JAVA_HOME:+$JAVA_HOME/bin/java}" "$(command -v java || true)"; do
    [ -n "$c" ] || continue
    m="$(java_major "$c")"
    if [ "${m:-0}" -ge "$JAVA_NEEDED" ] 2>/dev/null; then JAVA="$c"; break; fi
  done
  if [ -z "$JAVA" ]; then
    case "$(uname -s)" in Darwin) os=mac ;; *) os=linux ;; esac
    case "$(uname -m)" in aarch64|arm64) arch=aarch64 ;; *) arch=x64 ;; esac
    echo "No Java $JAVA_NEEDED+ found, downloading portable Temurin JRE $JAVA_NEEDED ($os/$arch)..."
    dl "https://api.adoptium.net/v3/binary/latest/$JAVA_NEEDED/ga/$os/$arch/jre/hotspot/normal/eclipse" "$CACHE/temurin-$JAVA_NEEDED.tar.gz"
    rm -rf "$OUT/java" "$CACHE/jre-extract"; mkdir -p "$CACHE/jre-extract"
    tar -xzf "$CACHE/temurin-$JAVA_NEEDED.tar.gz" -C "$CACHE/jre-extract"
    inner="$(find "$CACHE/jre-extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [ -d "$inner/Contents/Home" ] && inner="$inner/Contents/Home"   # macOS layout
    mv "$inner" "$OUT/java"; rm -rf "$CACHE/jre-extract"
    JAVA="$LOCAL_JAVA"
  fi
  echo "Java: $JAVA"
fi

# 5. Mod loader ---------------------------------------------------------------
step "Installing mod loader: $LOADER"
LNAME="${LOADER%%-*}"; LVER="${LOADER#*-}"
ARGSDIR= SERVERJAR=
case "$LNAME" in
  neoforge)
    INST="$CACHE/neoforge-$LVER-installer.jar"
    [ -f "$INST" ] || dl "https://maven.neoforged.net/releases/net/neoforged/neoforge/$LVER/neoforge-$LVER-installer.jar" "$INST"
    ARGSDIR="libraries/net/neoforged/neoforge/$LVER" ;;
  forge)
    FULL="$MC-$LVER"; INST="$CACHE/forge-$FULL-installer.jar"
    [ -f "$INST" ] || dl "https://maven.minecraftforge.net/net/minecraftforge/forge/$FULL/forge-$FULL-installer.jar" "$INST"
    ARGSDIR="libraries/net/minecraftforge/forge/$FULL" ;;
  fabric)
    FINST="$(getjson https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')"
    SERVERJAR=fabric-server.jar
    dl "https://meta.fabricmc.net/v2/versions/loader/$MC/$LVER/$FINST/server/jar" "$OUT/$SERVERJAR" ;;
  *) echo "Mod loader '$LNAME' is not supported" >&2; exit 1 ;;
esac

if [ "$FILES_ONLY" = true ]; then
  if [ -n "$ARGSDIR" ]; then
    cp -f "$INST" "$OUT/"
    echo "Installer placed: $(basename "$INST")"
    echo "To install: java -jar $(basename "$INST") --installServer"
  else
    echo "Fabric server launcher placed: $SERVERJAR"
  fi
elif [ -n "$ARGSDIR" ]; then
  if [ -f "$OUT/$ARGSDIR/unix_args.txt" ]; then
    echo 'Mod loader already installed, skipping'
  else
    (cd "$OUT" && "$JAVA" -jar "$INST" --installServer "$OUT")
    rm -f "$OUT"/*installer.jar.log
  fi
  if [ ! -f "$OUT/$ARGSDIR/unix_args.txt" ]; then
    # Old Forge (<1.17) produces a standalone jar
    SERVERJAR="$(cd "$OUT" && ls forge-*.jar 2>/dev/null | grep -v installer | head -1 || true)"
    ARGSDIR=
  fi
fi

# 6. Start scripts + eula -----------------------------------------------------
if [ "$FILES_ONLY" = false ]; then
  step 'Writing start scripts'
  printf -- '-Xms%s\n-Xmx%s\n' "$RAMARG" "$RAMARG" > "$OUT/user_jvm_args.txt"
  if [ -n "$ARGSDIR" ]; then
    LAUNCH_UNIX="@$ARGSDIR/unix_args.txt nogui"; LAUNCH_WIN="@$ARGSDIR/win_args.txt nogui"
  else
    LAUNCH_UNIX="-jar $SERVERJAR nogui"; LAUNCH_WIN="$LAUNCH_UNIX"
  fi

  cat > "$OUT/start.sh" <<EOF
#!/usr/bin/env sh
cd "\$(dirname "\$0")"
JAVA=java
[ -x ./java/bin/java ] && JAVA=./java/bin/java
while true; do
  "\$JAVA" @user_jvm_args.txt $LAUNCH_UNIX "\$@"
  echo "Server stopped. Restarting in 10 seconds, Ctrl+C to quit."
  sleep 10
done
EOF
  chmod +x "$OUT/start.sh"

  printf '@echo off\r\ncd /d "%%~dp0"\r\nset JAVA=java\r\nif exist "%%~dp0java\\bin\\java.exe" set "JAVA=%%~dp0java\\bin\\java.exe"\r\n:start\r\n"%%JAVA%%" @user_jvm_args.txt %s %%*\r\necho.\r\necho Server stopped. Restarting in 10 seconds, press Ctrl+C to quit.\r\ntimeout /t 10\r\ngoto start\r\n' \
    "$LAUNCH_WIN" > "$OUT/start.bat"

  printf '# https://aka.ms/MinecraftEULA\neula=%s\n' "$EULA" > "$OUT/eula.txt"
  rm -f "$OUT/run.sh" "$OUT/run.bat"
fi

# Summary ---------------------------------------------------------------------
step 'Done'
echo "Server is in:   $OUT"
echo "Mods on server: $(find "$MODS" -name '*.jar' | wc -l | tr -d ' ')   (client-only / resource packs skipped: $(sort -u "$SKIPPED" | wc -l | tr -d ' '))"
if [ -s "$SKIPPED" ]; then sort -u "$SKIPPED" > "$OUT/skipped-client-mods.txt"; echo "  list: skipped-client-mods.txt"; fi
if [ -s "$KEPT" ]; then printf '\033[32mKept on server (client tag, but has content): %s\033[0m\n' "$(paste -sd, "$KEPT")"; fi
rm -f "$OUT/failed-mods.txt"
if [ -s "$FAILED" ]; then
  printf '\033[31mFAILED: %s mods - download these by hand into extra-mods/ and run again:\033[0m\n' "$(wc -l < "$FAILED" | tr -d ' ')"
  sed 's/^/  /' "$FAILED"; cp "$FAILED" "$OUT/failed-mods.txt"
fi
rm -f "$SKIPPED" "$FAILED" "$KEPT"
if [ "$FILES_ONLY" = true ]; then
  printf '\033[33mFiles only: mod loader not installed, no start scripts/eula written.\033[0m\n'
else
  [ "$EULA" = true ] || printf '\033[33mNote: eula.txt is set to false. Run again with --accept-eula or edit eula.txt.\033[0m\n'
  printf '\033[32mStart with: %s/start.sh\033[0m\n' "$OUT"
fi
