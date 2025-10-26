#!/usr/bin/env bash
set -euo pipefail

# ============================================
# GreenKasse – BUNDLE-ERZEUGER fuer Ubuntu/Linux
# Baut PWA (Quasar) unter Linux und published .NET als win-x64 self-contained.
# Erzeugt BundleRoot mit:
#  - app/        (.NET Publish + appsettings.json aus Repo-Root)
#  - pwa/        (PWA Build-Ausgabe)
#  - db/mariadb/ (MariaDB ZIP fuer Windows entpackt)
#  - db/data/    (leer; wird auf Zielsystem initialisiert)
#  - db/schemas/ (schema.sql/seed.sql falls vorhanden)
#  - scripts/    (install.ps1 – wird auf Windows ausgefuehrt)
# ============================================

# --- Konfiguration ---
APP_VERSION="1.0.0"
RUNTIME_ID="win-x64"          # Zielplattform fuer .NET Publish
SELF_CONTAINED=true
SINGLE_FILE=true
TRIMMED=false

# Repo-Root 
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Haupt-App (Web)
CSPROJ="$REPO_ROOT/GreenKasse.App/GreenKasse.App.csproj"
APPSETTINGS_SRC="$REPO_ROOT/appsettings.json"

# Updater (optional)
UPDATER_CSPROJ="$REPO_ROOT/GreenKasse.Updater/GreenKasse.Updater.csproj"

# PWA / Quasar
PWA_DIR="$REPO_ROOT/pwa"
USE_QUASAR_BUILD=true        # true: "quasar build -m pwa", false: "npm run build"
QUASAR_MODE="pwa"
PWA_DIST_REL="dist/pwa"      # Ausgabepfad innerhalb von pwa/

# MariaDB (Windows x64 ZIP)
MARIADB_VERSION="10.6.22"    # LTS-Zweig
MARIADB_ARCH="winx64"
MARIADB_FILENAME="mariadb-${MARIADB_VERSION}-${MARIADB_ARCH}.zip"
MARIADB_BASEURL="https://archive.mariadb.org/mariadb-${MARIADB_VERSION}/${MARIADB_ARCH}-packages/"

# Schema-Quelle
SCHEMAS_SRC="$REPO_ROOT/db/schemas"

# Bundle-Ausgabe
BUNDLE_ROOT="$REPO_ROOT/BundleRoot"

# ZIP-Option
MAKE_ZIPS=true

# --- Hilfsfunktionen ---
ensure_dir() { mkdir -p "$1"; }
clean_dir()  { rm -rf "$1"; mkdir -p "$1"; }

info() { echo ">> $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# --- Voraussetzungen pruefen ---
command -v dotnet >/dev/null 2>&1 || die "dotnet SDK fehlt (sudo snap install dotnet-sdk --classic oder apt/dotnet)."
command -v unzip  >/dev/null 2>&1 || die "unzip fehlt (sudo apt install unzip)."
command -v curl   >/dev/null 2>&1 || die "curl fehlt (sudo apt install curl)."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum fehlt (coreutils)."
# Node ist fuer PWA/Quasar erforderlich:
if ! command -v node >/dev/null 2>&1; then
  warn "Node ist nicht in PATH. PWA-Build wird vermutlich fehlschlagen."
fi

# --- 0) Bundle-Struktur vorbereiten ---
info "Vorbereitung BundleRoot: $BUNDLE_ROOT"
clean_dir "$BUNDLE_ROOT"
ensure_dir "$BUNDLE_ROOT/app"
ensure_dir "$BUNDLE_ROOT/app/pwa"          
ensure_dir "$BUNDLE_ROOT/app/updater"
ensure_dir "$BUNDLE_ROOT/db/mariadb"
ensure_dir "$BUNDLE_ROOT/db/data"          # leer lassen – init auf Zielsystem
ensure_dir "$BUNDLE_ROOT/db/schemas"
ensure_dir "$BUNDLE_ROOT/scripts"

# --- 1) .NET Publish (win-x64, self-contained, single-file) ---
info "dotnet publish ($RUNTIME_ID) - self-contained=$SELF_CONTAINED single-file=$SINGLE_FILE trimmed=$TRIMMED"
PUBDIR="$(mktemp -d)"
dotnet publish "$CSPROJ" \
  -c Release \
  -r "$RUNTIME_ID" \
  --self-contained "$SELF_CONTAINED" \
  -p:PublishSingleFile="$SINGLE_FILE" \
  -p:PublishTrimmed="$TRIMMED" \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -o "$PUBDIR" || die "dotnet publish fehlgeschlagen."

# Dateien uebernehmen
cp -R "$PUBDIR"/. "$BUNDLE_ROOT/app/"

# publizierte appsettings*.json entfernen, dann Root-appsettings reinkopieren
find "$BUNDLE_ROOT/app" -maxdepth 1 -type f -name 'appsettings*.json' -print0 | xargs -0 -r rm -f
cp "$APPSETTINGS_SRC" "$BUNDLE_ROOT/app/appsettings.json"

# App ZIP 
if [ "$MAKE_ZIPS" = true ]; then
  (cd "$BUNDLE_ROOT" && zip -rq "App_${APP_VERSION}.zip" "app")
  info "App ZIP erstellt: $BUNDLE_ROOT/App_${APP_VERSION}.zip"
fi

# --- 1.1) Updater separat publishen  ---
if [ -f "$UPDATER_CSPROJ" ]; then
  info "Updater publish: $UPDATER_CSPROJ"
  UPD_PUBDIR="$(mktemp -d)"
  dotnet publish "$UPDATER_CSPROJ" -c Release -r "$RUNTIME_ID" --self-contained "$SELF_CONTAINED" -o "$UPD_PUBDIR"
  cp -R "$UPD_PUBDIR"/. "$BUNDLE_ROOT/app/updater/"
else
  info "Updater-Projekt nicht gefunden (optional) - uebersprungen."
fi

# --- 2) PWA Build (Quasar optional) ---
PWA_DIST=""
if [ "$USE_QUASAR_BUILD" = true ]; then
  info "Quasar Build startet: $PWA_DIR (quasar -m $QUASAR_MODE)"
  [ -f "$PWA_DIR/package.json" ] || die "package.json nicht gefunden in $PWA_DIR"

  pushd "$PWA_DIR" >/dev/null
  # Node-Module vorbereiten
  if [ ! -d "node_modules" ]; then
    if [ -f "package-lock.json" ]; then npm ci; else npm install; fi
  fi

  BUILD_OK=0
  if command -v npx >/dev/null 2>&1; then
    npx --yes quasar build -m "$QUASAR_MODE" && BUILD_OK=1 || true
  fi
  if [ $BUILD_OK -eq 0 ]; then
    npm exec -- quasar build -m "$QUASAR_MODE" && BUILD_OK=1 || true
  fi
  if [ $BUILD_OK -eq 0 ] && [ -x "node_modules/.bin/quasar" ]; then
    node node_modules/.bin/quasar build -m "$QUASAR_MODE" && BUILD_OK=1 || true
  fi
  if [ $BUILD_OK -eq 0 ]; then
    warn "Quasar konnte nicht gestartet werden (npx/npm exec/.bin). Fallback auf 'npm run build'."
    npm run build || die "PWA Build fehlgeschlagen."
  fi
  popd >/dev/null

  PWA_DIST="$PWA_DIR/$PWA_DIST_REL"
  [ -d "$PWA_DIST" ] || die "Quasar-Build Ausgabe fehlt: $PWA_DIST"
else
  info "PWA Build ueber npm: $PWA_DIR (Befehl: $PWA_DIST_REL)"
  pushd "$PWA_DIR" >/dev/null
  if [ -f "package-lock.json" ]; then npm ci; else npm install; fi
  npm run build || die "PWA Build fehlgeschlagen."
  popd >/dev/null
  PWA_DIST="$PWA_DIR/$PWA_DIST_REL"
  [ -d "$PWA_DIST" ] || die "PWA Build-Ausgabe fehlt: $PWA_DIST"
fi

# PWA ins Bundle uebernehmen
cp -R "$PWA_DIST"/. "$BUNDLE_ROOT/app/pwa/"

# PWA ZIP (optional)
if [ "$MAKE_ZIPS" = true ]; then
  (cd "$BUNDLE_ROOT/app" && zip -rq "Pwa_${APP_VERSION}.zip" "pwa")
  info "PWA ZIP erstellt: $BUNDLE_ROOT/app/Pwa_${APP_VERSION}.zip"
fi

# --- 3) MariaDB fuer Windows laden und pruefen ---
info "MariaDB ${MARIADB_VERSION} (${MARIADB_ARCH}) wird heruntergeladen..."
TMPDIR="$(mktemp -d)"
ZIP_PATH="$TMPDIR/$MARIADB_FILENAME"
SHA_PATH="$TMPDIR/$MARIADB_FILENAME.sha256"
curl -fsSL "${MARIADB_BASEURL}${MARIADB_FILENAME}" -o "$ZIP_PATH"

EXPECTED=""
# Versuch A: per-file .sha256
if curl -fsSL "${MARIADB_BASEURL}${MARIADB_FILENAME}.sha256" -o "$SHA_PATH"; then
  EXPECTED="$(cut -d' ' -f1 "$SHA_PATH" | head -n1)"
else
  # Versuch B: sha256sums.txt
  SHA_LIST="$TMPDIR/sha256sums.txt"
  curl -fsSL "${MARIADB_BASEURL}sha256sums.txt" -o "$SHA_LIST"
  EXPECTED="$(grep -F "$MARIADB_FILENAME" "$SHA_LIST" | awk '{print $1}' | head -n1 || true)"
fi
[ -n "$EXPECTED" ] || die "Konnte erwartete SHA256 nicht ermitteln."

ACTUAL="$(sha256sum "$ZIP_PATH" | awk '{print $1}')"
if [ "${EXPECTED^^}" != "${ACTUAL^^}" ]; then
  die "MariaDB ZIP SHA256 mismatch! expected=$EXPECTED actual=$ACTUAL"
fi
info "SHA256 OK"

# Entpacken nach BundleRoot/db/mariadb
UNZIP_DIR="$(mktemp -d)"
unzip -q "$ZIP_PATH" -d "$UNZIP_DIR"
# Falls eine zusaetzliche Wurzelmappe existiert, Inhalte herausheben
if [ "$(find "$UNZIP_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]; then
  ROOT_SUB="$(find "$UNZIP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  cp -R "$ROOT_SUB"/. "$BUNDLE_ROOT/db/mariadb/"
else
  cp -R "$UNZIP_DIR"/. "$BUNDLE_ROOT/db/mariadb/"
fi

# Minimal-Check
if [ ! -f "$BUNDLE_ROOT/db/mariadb/bin/mysql.exe" ]; then
  die "MariaDB-Binaries fehlen (mysql.exe)."
fi

# 4) my.ini generieren (falls nicht vorhanden)
MYINI="$BUNDLE_ROOT/db/my.ini"
if [ ! -f "$MYINI" ]; then
  cat >"$MYINI" <<'INI'
[mysqld]
basedir={app}\db\mariadb
datadir={app}\db\data
port=3306
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
secure-file-priv={app}\db\data\export
innodb_flush_log_at_trx_commit=1
sync_binlog=1
sql_mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION
INI
fi

# 5) Schemas uebernehmen
if [ -d "$SCHEMAS_SRC" ]; then
  cp -R "$SCHEMAS_SRC"/. "$BUNDLE_ROOT/db/schemas/"
  info "Schemas nach db/schemas kopiert."
else
  warn "Schema-Quelle nicht gefunden – Bundle wird ohne schema.sql erzeugt."
fi

# 6) Installer ins Bundle kopieren (Windows PowerShell)
if [ -f "$REPO_ROOT/scripts/install.ps1" ]; then
  cp "$REPO_ROOT/scripts/init_db.bat" "$BUNDLE_ROOT/scripts/init_db.bat"
  cp "$REPO_ROOT/scripts/stop_db.bat" "$BUNDLE_ROOT/scripts/stop_db.bat"
  cp "$REPO_ROOT/scripts/install.ps1" "$BUNDLE_ROOT/scripts/install.ps1"
  cp "$REPO_ROOT/scripts/installer.md" "$BUNDLE_ROOT/scripts/installer.md"
  info "install.ps1 + info nach BundleRoot/scripts kopiert."
else
  warn "install.ps1 nicht gefunden – lege es unter scripts/ ab."
fi

# 7) Zusammenfassung
echo
echo "=== BUNDLE FERTIG ==="
echo "BundleRoot: $BUNDLE_ROOT"
echo " - app/ (self-contained Build + appsettings.json aus Repo-Root)"
echo " - pwa/ (PWA-Build fuer WebRoot)"
echo " - app/updater/ (falls vorhanden)"
echo " - db/mariadb/bin/*, share/*"
echo " - db/data/ (leer)"
echo " - db/my.ini"
echo " - db/schemas/schema.sql (falls vorhanden)"
echo " - scripts/install.ps1"
if [ "$MAKE_ZIPS" = true ]; then
  echo " - App_${APP_VERSION}.zip"
  echo " - Pwa_${APP_VERSION}.zip"
fi
echo
echo "Weiter: BundleRoot auf Windows kopieren und als Admin ausfuehren:"
echo "  PowerShell:  .\\scripts\\install.ps1"
