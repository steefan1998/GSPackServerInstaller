#!/usr/bin/env bash
# Bouwt een kant-en-klare Minecraft server uit een CurseForge modpack (GSPack) - Linux/macOS.
# Zelfde werking als Build-ServerPack.ps1:
#   client-zip ophalen -> mods downloaden (client-only eruit) -> overrides -> modloader
#   -> Java (portable Temurin als die ontbreekt) -> start.sh, user_jvm_args.txt, eula.txt
#
# Vereist: bash, curl, unzip, jq   (Debian/Ubuntu: sudo apt install curl unzip jq)
#
# Gebruik:
#   ./build-serverpack.sh --zip GSPack-0.1.zip --accept-eula
#   ./build-serverpack.sh --project 1234567 --accept-eula        # zodra GSPack is goedgekeurd
#
# Opties:
#   --zip PAD            CurseForge export-zip (client pack)
#   --project ID         CurseForge project-ID van het modpack
#   --file ID            specifieke file-ID van het pack (standaard: nieuwste)
#   --out MAP            doelmap (standaard: ./<PackNaam>Server, bijv. ./GSPackServer)
#   --accept-eula        zet eula=true (https://aka.ms/MinecraftEULA)
#   --ram MB             geheugen in MB (standaard 8192 = 8 GB)
#   --java PAD           pad naar java
#   --exclude REGEX      extra mod (bestandsnaam) die niet op de server mag; mag vaker
#   --keep-client-mods   client-only filter overslaan
#   --files-only         alleen de mappen (mods, config, ...) + modloader-installer;
#                        niets installeren, geen Java, geen startscripts
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
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "Onbekende optie: $1" >&2; exit 1 ;;
  esac
done
if [ -z "$ZIP" ] && [ -z "$PROJECT" ]; then echo "Geef --zip of --project op (zie --help)" >&2; exit 1; fi
for bin in curl unzip jq; do
  command -v "$bin" >/dev/null || { echo "'$bin' ontbreekt. Installeer: sudo apt install curl unzip jq" >&2; exit 1; }
done

# Mods die vaak als Client+Server getagd zijn maar alleen client-side werken
KNOWN_CLIENT_ONLY='^(oculus|iris|sodium|embeddium|rubidium|entityculling|fancymenu|drippyloadingscreen|konkrete|legendarytooltips|betterf3|jeresources-client|mousetweaks|appleskin-client|ding|notenoughanimations|citresewn|entity_?texture_?features|entity_?model_?features|skinlayers3d|3dskinlayers|firstperson|cherishedworlds|controlling|searchables|catalogue|configured-client|betterthirdperson|shulkerboxtooltip-client|xaerominimap-client|modernfix-client|immediatelyfast|enhancedvisuals|presencefootsteps|soundphysics|ambientsounds|dynamiclights|lambdynamiclights|sodiumdynamiclights|chat_heads|chatheads|blur|loadmyresources|yeetusexperimentus)'
for e in "${EXCLUDES[@]+"${EXCLUDES[@]}"}"; do KNOWN_CLIENT_ONLY="$KNOWN_CLIENT_ONLY|$e"; done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
dl() { # dl URL DEST  (met retries, volgt redirects)
  curl -fsSL --retry 3 --retry-delay 2 -A "$UA" -o "$2.part" "$1" && mv -f "$2.part" "$2"
}
getjson() { curl -fsSL --retry 3 --retry-delay 2 -A "$UA" "$1"; }

# Cache staat naast het script, zodat de servermap schoon blijft
CACHE="$SCRIPT_DIR/.cache"; MODCACHE="$CACHE/mods"; META="$CACHE/meta"
mkdir -p "$MODCACHE" "$META"

# 1. Client pack ophalen ------------------------------------------------------
if [ -n "$PROJECT" ]; then
  step "Modpack ophalen van CurseForge (project $PROJECT)"
  if [ -z "$FILEID" ]; then
    FILEID="$(getjson "$CF/mods/$PROJECT/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=true" \
      | jq -r '[.data[] | select(.fileName | endswith(".zip"))][0].id // empty')"
    [ -n "$FILEID" ] || { echo "Geen pack-bestand gevonden voor project $PROJECT (al goedgekeurd?)" >&2; exit 1; }
    echo "Nieuwste versie: file $FILEID"
  fi
  ZIP="$CACHE/pack-$FILEID.zip"
  [ -f "$ZIP" ] || dl "$CF/mods/$PROJECT/files/$FILEID/download" "$ZIP"
fi
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"

step "Pack uitpakken: $ZIP"
PACK="$CACHE/pack"
rm -rf "$PACK"; mkdir -p "$PACK"
unzip -q "$ZIP" -d "$PACK"
MANIFEST="$PACK/manifest.json"
[ -f "$MANIFEST" ] || { echo "Geen manifest.json in $ZIP - is dit een CurseForge export?" >&2; exit 1; }

MC="$(jq -r '.minecraft.version' "$MANIFEST")"
LOADER="$(jq -r '(.minecraft.modLoaders | map(select(.primary)) + .minecraft.modLoaders)[0].id' "$MANIFEST")"
TOTAL="$(jq '.files | length' "$MANIFEST")"
echo "$(jq -r '"\(.name) \(.version)"' "$MANIFEST") - Minecraft $MC, $LOADER, $TOTAL mods"
RAM="${RAM:-8192}"
# Schrijf als G als het een heel aantal GB is (8192 -> 8G)
if [ $((RAM % 1024)) -eq 0 ]; then RAMARG="$((RAM / 1024))G"; else RAMARG="${RAM}M"; fi

# Standaard doelmap: <PackNaam>Server naast dit script, bijv. GSPackServer
OUT="${OUT:-$SCRIPT_DIR/$(jq -r '.name' "$MANIFEST" | tr -cd 'A-Za-z0-9_.-')Server}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
echo "Doelmap: $OUT"

# 2. Mods downloaden ----------------------------------------------------------
step 'Mods downloaden'
MODS="$OUT/mods"
rm -rf "$MODS"; mkdir -p "$MODS"
SKIPPED="$CACHE/skipped.tmp"; FAILED="$CACHE/failed.tmp"; KEPT="$CACHE/kept.tmp"
: > "$SKIPPED"; : > "$FAILED"; : > "$KEPT"
# Jar met blocks of server-data (recipes, loot tables, worldgen) moet ook op de server,
# ook al is hij op CurseForge als client-only getagd.
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
      echo "project $pid / file $fid (info niet op te halen) -> https://www.curseforge.com/projects/$pid" >> "$FAILED"
      printf '\033[31m[%s/%s] MISLUKT project %s file %s\033[0m\n' "$n" "$TOTAL" "$pid" "$fid"; continue
    fi
    mv -f "$metaf.part" "$metaf"
  fi
  name="$(jq -r '.fileName' "$metaf")"
  size="$(jq -r '.fileLength' "$metaf")"

  case "$name" in
    *.jar) ;;
    *) # Resource-/shaderpacks horen niet op de server
       echo "$name" >> "$SKIPPED"
       printf '\033[33m[%s/%s] geen mod (resource/shaderpack), overgeslagen: %s\033[0m\n' "$n" "$TOTAL" "$name"; continue ;;
  esac

  cached="$MODCACHE/$fid.jar"
  if [ ! -f "$cached" ] || [ "$(wc -c < "$cached" | tr -d ' ')" != "$size" ]; then
    echo "[$n/$TOTAL] download $name"
    if ! dl "$CF/mods/$pid/files/$fid/download" "$cached"; then
      echo "project $pid / file $fid ($name) -> https://www.curseforge.com/projects/$pid" >> "$FAILED"
      printf '\033[31m[%s/%s] MISLUKT %s\033[0m\n' "$n" "$TOTAL" "$name"; continue
    fi
  else
    printf '\033[90m[%s/%s] cache    %s\033[0m\n' "$n" "$TOTAL" "$name"
  fi

  if [ "$KEEP_CLIENT" = false ]; then
    clientonly="$(jq -r '(.gameVersions | index("Client") != null) and (.gameVersions | index("Server") == null)' "$metaf")"
    if [ "$clientonly" = true ] || printf '%s' "$name" | grep -Eiq "$KNOWN_CLIENT_ONLY"; then
      if has_server_content "$cached"; then
        # Verkeerd getagd (bijv. Equivox): zonder deze mod kan de client niet joinen
        echo "$name" >> "$KEPT"
        printf '\033[32m[%s/%s] client-tag maar bevat blocks/recipes, toch op server: %s\033[0m\n' "$n" "$TOTAL" "$name"
      else
        echo "$name" >> "$SKIPPED"
        printf '\033[33m[%s/%s] client-only, overgeslagen: %s\033[0m\n' "$n" "$TOTAL" "$name"; continue
      fi
    fi
  fi
  cp -f "$cached" "$MODS/$name"
done < <(jq -r '.files[] | "\(.projectID) \(.fileID)"' "$MANIFEST")

# 3. Overrides ----------------------------------------------------------------
step 'Overrides kopieren'
for ov in "$(jq -r '.overrides // "overrides"' "$MANIFEST")" server-overrides; do
  if [ -d "$PACK/$ov" ]; then echo "  $ov/ -> server"; cp -rf "$PACK/$ov/." "$OUT/"; fi
done
# Eigen server-only mods: zet ze in <out>/extra-mods, die blijven bewaard
mkdir -p "$OUT/extra-mods"
for j in "$OUT"/extra-mods/*.jar; do [ -e "$j" ] && { cp -f "$j" "$MODS/"; echo "  extra mod: $(basename "$j")"; }; done
if [ "$KEEP_CLIENT" = false ]; then
  for j in "$MODS"/*.jar; do
    [ -e "$j" ] || continue
    if basename "$j" | grep -Eiq "$KNOWN_CLIENT_ONLY"; then basename "$j" >> "$SKIPPED"; rm -f "$j"; fi
  done
fi

# 4. Java ---------------------------------------------------------------------
JAVA=
if [ "$FILES_ONLY" = false ]; then
step 'Java controleren'
JAVA_NEEDED=21
if vurl="$(getjson https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r --arg v "$MC" '.versions[] | select(.id == $v) | .url' | head -1)" && [ -n "$vurl" ]; then
  JAVA_NEEDED="$(getjson "$vurl" | jq -r '.javaVersion.majorVersion // 21')"
fi
echo "Minecraft $MC vereist Java $JAVA_NEEDED"

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
  echo "Geen Java $JAVA_NEEDED+ gevonden, portable Temurin JRE $JAVA_NEEDED ($os/$arch) downloaden..."
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

# 5. Modloader ----------------------------------------------------------------
step "Modloader installeren: $LOADER"
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
  *) echo "Modloader '$LNAME' wordt niet ondersteund" >&2; exit 1 ;;
esac

if [ "$FILES_ONLY" = true ]; then
  if [ -n "$ARGSDIR" ]; then
    cp -f "$INST" "$OUT/"
    echo "Installer klaargezet: $(basename "$INST")"
    echo "Installeren: java -jar $(basename "$INST") --installServer"
  else
    echo "Fabric server-launcher klaargezet: $SERVERJAR"
  fi
elif [ -n "$ARGSDIR" ]; then
  if [ -f "$OUT/$ARGSDIR/unix_args.txt" ]; then
    echo 'Modloader is al geinstalleerd, overslaan'
  else
    (cd "$OUT" && "$JAVA" -jar "$INST" --installServer "$OUT")
    rm -f "$OUT"/*installer.jar.log
  fi
  if [ ! -f "$OUT/$ARGSDIR/unix_args.txt" ]; then
    # Oude Forge (<1.17) maakt een losse jar
    SERVERJAR="$(cd "$OUT" && ls forge-*.jar 2>/dev/null | grep -v installer | head -1 || true)"
    ARGSDIR=
  fi
fi

# 6. Startscripts + eula ------------------------------------------------------
if [ "$FILES_ONLY" = false ]; then
step 'Startscripts schrijven'
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
  echo "Server gestopt. Herstart over 10 seconden, Ctrl+C om te stoppen."
  sleep 10
done
EOF
chmod +x "$OUT/start.sh"

printf '@echo off\r\ncd /d "%%~dp0"\r\nset JAVA=java\r\nif exist "%%~dp0java\\bin\\java.exe" set "JAVA=%%~dp0java\\bin\\java.exe"\r\n:start\r\n"%%JAVA%%" @user_jvm_args.txt %s %%*\r\necho.\r\necho Server gestopt. Herstart over 10 seconden, druk Ctrl+C om te stoppen.\r\ntimeout /t 10\r\ngoto start\r\n' \
  "$LAUNCH_WIN" > "$OUT/start.bat"

printf '# https://aka.ms/MinecraftEULA\neula=%s\n' "$EULA" > "$OUT/eula.txt"
rm -f "$OUT/run.sh" "$OUT/run.bat"
fi

# Samenvatting ----------------------------------------------------------------
step 'Klaar'
echo "Server staat in: $OUT"
echo "Mods op server:  $(find "$MODS" -name '*.jar' | wc -l | tr -d ' ')   (client-only / resourcepacks overgeslagen: $(sort -u "$SKIPPED" | wc -l | tr -d ' '))"
if [ -s "$SKIPPED" ]; then sort -u "$SKIPPED" > "$OUT/skipped-client-mods.txt"; echo "  lijst: skipped-client-mods.txt"; fi
[ -s "$KEPT" ] && printf '\033[32mToch op server (client-tag, maar met content): %s\033[0m\n' "$(paste -sd, "$KEPT")"
rm -f "$OUT/failed-mods.txt"
if [ -s "$FAILED" ]; then
  printf '\033[31mMISLUKT: %s mods - download deze handmatig naar extra-mods/ en draai opnieuw:\033[0m\n' "$(wc -l < "$FAILED" | tr -d ' ')"
  sed 's/^/  /' "$FAILED"; cp "$FAILED" "$OUT/failed-mods.txt"
fi
rm -f "$SKIPPED" "$FAILED" "$KEPT"
if [ "$FILES_ONLY" = true ]; then
  printf '\033[33mAlleen bestanden: modloader niet geinstalleerd, geen startscripts/eula geschreven.\033[0m\n'
else
  [ "$EULA" = true ] || printf '\033[33mLet op: eula.txt staat op false. Draai opnieuw met --accept-eula of pas eula.txt aan.\033[0m\n'
  printf '\033[32mStarten: %s/start.sh\033[0m\n' "$OUT"
fi
