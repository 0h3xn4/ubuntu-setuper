# shellcheck shell=bash
# =============================================================================
#  modules/desktop/module.sh — code of the "desktop" module
#
#  Everyday desktop apps for personal machines, each with its background
#  network features switched off. See modules/embedded/module.sh for the list
#  of hooks a module can provide, and module.conf for the rules of this one.
# =============================================================================
DESKTOP_DIR="$MODULE_DIR"

LO_PROFILE_XCU="${XDG_CONFIG_HOME:-$HOME/.config}/libreoffice/4/user/registrymodifications.xcu"
FIREFOX_POLICY=/etc/firefox/policies/policies.json
THUNDERBIRD_POLICY=/etc/thunderbird/policies/policies.json

mod_desktop_pkg_groups() {
  if on "$DESKTOP_LIBREOFFICE"; then echo PKGS_DESKTOP_LIBREOFFICE; fi
  if on "$DESKTOP_KEEPASSXC";   then echo PKGS_DESKTOP_KEEPASSXC; fi
  if on "$DESKTOP_VLC";         then echo PKGS_DESKTOP_VLC; fi
  if on "$DESKTOP_GIMP";        then echo PKGS_DESKTOP_GIMP; fi
  if on "$DESKTOP_INKSCAPE";    then echo PKGS_DESKTOP_INKSCAPE; fi
  if on "$DESKTOP_DEJADUP";     then echo PKGS_DESKTOP_DEJADUP; fi
}

mod_desktop_home_files() {
  if on "$DESKTOP_KEEPASSXC"; then echo .config/keepassxc/keepassxc.ini; fi
  if on "$DESKTOP_VLC"; then echo .config/vlc/vlcrc; fi
}

mod_desktop_manifest_tools() {
  printf '%s\n' libreoffice keepassxc vlc gimp inkscape deja-dup
}

mod_desktop_check() {
  if [[ -n $DESKTOP_LANGUAGES ]]; then log "Languages (dictionaries, LibreOffice packs): $DESKTOP_LANGUAGES"
  else log "Languages: none beyond English (set DESKTOP_LANGUAGES, e.g. \"de fr\")"; fi
  if on "$DESKTOP_LIBREOFFICE"; then
    if python3 -I "$DESKTOP_DIR/files/lo_update_check.py" check "$LO_PROFILE_XCU" 2>/dev/null; then
      echo "    LibreOffice: update check already off in your profile"
    else echo "    LibreOffice: switch update check off in $LO_PROFILE_XCU"; fi
  fi
  if on "$DESKTOP_BROWSER_POLICIES"; then
    local f
    for f in "$FIREFOX_POLICY" "$THUNDERBIRD_POLICY"; do
      if [[ ! -e $f ]]; then echo "    new file $f (browser/mail policy)"
      else echo "    keep $f (exists; never overwritten)"; fi
    done
  fi
  if on "$DESKTOP_DEJADUP"; then echo "    GNOME: Déjà Dup backend restricted to a local folder or external disk"; fi
}

mod_desktop_steps() {
  step "Desktop apps"                      desktop_apps
  step "Desktop languages"                 desktop_languages
  step "Desktop app settings (no network)" desktop_app_settings
  if on "$DESKTOP_BROWSER_POLICIES"; then step "Browser and mail policies" desktop_browser_policies; fi
}

desktop_apps() {
  local g
  local -a pk
  while IFS= read -r g; do
    mapfile -t pk < <(array_items "$g")
    apt_install "${pk[@]}"
  done < <(mod_desktop_pkg_groups)
}

desktop_languages() {
  if [[ -z $DESKTOP_LANGUAGES ]]; then ok "No extra languages requested (DESKTOP_LANGUAGES is empty)"; return 0; fi
  if ! have check-language-support; then apt_install language-selector-common; fi
  have check-language-support || { warn "check-language-support is not available"; return 1; }
  local l pkgs=() out p
  for l in $DESKTOP_LANGUAGES; do
    if [[ ! $l =~ ^[a-z]{2,3}([_-][A-Za-z]+)?$ ]]; then warn "Ignoring invalid language code: $l"; continue; fi
    # Offline: resolved from the local package lists. Prints the packages
    # (language pack, dictionaries, LibreOffice l10n and help) still missing.
    out="$(check-language-support -l "$l" 2>/dev/null || true)"
    for p in $out; do pkgs+=("$p"); done
  done
  if (( ${#pkgs[@]} )); then apt_install "${pkgs[@]}"; else ok "Nothing missing for: $DESKTOP_LANGUAGES"; fi
}

# Append a line to a settings file once (backing it up first), or create it.
ensure_setting_line() {
  local file="$1" pattern="$2" line="$3"
  if [[ -f $file ]]; then
    if grep -Eq "$pattern" "$file"; then ok "Unchanged: $file"; return 0; fi
    cp -a "$file" "$file.bak.$TIMESTAMP"
    printf '%s\n' "$line" >> "$file"
    record_undo "mv -f $(printf %q "$file.bak.$TIMESTAMP") $(printf %q "$file")"
    ok "Added '$line' to $file (backup kept)"
  else
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$line" > "$file"
    record_undo "rm -f $(printf %q "$file")"
    ok "Wrote $file"
  fi
}

gimp_config_dir() {
  local v
  v="$(gimp --version 2>/dev/null | awk '{ print $NF }')"
  if [[ $v =~ ^([0-9]+\.[0-9]+) ]]; then echo "${XDG_CONFIG_HOME:-$HOME/.config}/GIMP/${BASH_REMATCH[1]}"; fi
}

desktop_app_settings() {
  # --- LibreOffice: no online update check ---
  if on "$DESKTOP_LIBREOFFICE"; then
    local xcu="$LO_PROFILE_XCU"
    mkdir -p "$(dirname "$xcu")"
    if [[ -f $xcu ]]; then cp -a "$xcu" "$xcu.bak.$TIMESTAMP"; fi
    if python3 -I "$DESKTOP_DIR/files/lo_update_check.py" set "$xcu"; then
      if [[ -f $xcu.bak.$TIMESTAMP ]]; then record_undo "mv -f $(printf %q "$xcu.bak.$TIMESTAMP") $(printf %q "$xcu")"
      else record_undo "rm -f $(printf %q "$xcu")"; fi
      ok "LibreOffice: online update check off ($xcu)"
    else
      warn "Could not update $xcu (is LibreOffice running? close it and re-run)"
    fi
  fi

  # --- KeePassXC and VLC: settings files (kept if the user already has one) ---
  if on "$DESKTOP_KEEPASSXC"; then install_file .config/keepassxc/keepassxc.ini; fi
  if on "$DESKTOP_VLC"; then install_file .config/vlc/vlcrc; fi

  # --- GIMP: no update check ---
  if on "$DESKTOP_GIMP" && have gimp; then
    local gdir; gdir="$(gimp_config_dir)"
    if [[ -n $gdir ]]; then ensure_setting_line "$gdir/gimprc" '^\(check-updates no\)' '(check-updates no)'
    else warn "Could not determine the GIMP version; set (check-updates no) in its gimprc yourself"; fi
  fi

  # --- Déjà Dup: local folder or external disk only, never a cloud backend ---
  if on "$DESKTOP_DEJADUP" && have gsettings; then
    if have_desktop_session; then
      local range val=""
      range="$(gsettings range org.gnome.DejaDup backend 2>/dev/null || true)"
      if grep -q "'local'" <<<"$range"; then val=local
      elif grep -q "'file'" <<<"$range"; then val='file'; fi
      if [[ -n $val ]]; then gset org.gnome.DejaDup backend "$val"
      else warn "Déjà Dup: could not find a local backend value; choose a local folder in its settings"; fi
    else
      warn "No desktop session: run setup.sh from a logged-in desktop to restrict Déjà Dup to local backups"
    fi
  fi
}

desktop_browser_policies() {
  # Firefox and Thunderbird read enterprise policies from /etc. Both are
  # snaps on Ubuntu; whether the snap honours these files must be checked in
  # the browser (about:policies). Existing policy files are never touched.
  install_system_file "$DESKTOP_DIR/files/system/firefox-policies.json" "$FIREFOX_POLICY"
  install_system_file "$DESKTOP_DIR/files/system/thunderbird-policies.json" "$THUNDERBIRD_POLICY"
  log "Verify after the first start: open about:policies in Firefox (Thunderbird: Help > Troubleshooting)."
}

# ----------------------------------------------------------------------------
# Self-tests
# ----------------------------------------------------------------------------
mod_desktop_selftests() {
  run_test "Desktop apps installed"                t_desk_packages  desktop
  run_test "LibreOffice settings helper"           t_desk_lo_helper desktop
  run_test "Browser/mail policy files are valid"   t_desk_policies  desktop
}

t_desk_packages() {
  local g missing=() pkg
  while IFS= read -r g; do
    pkg="$(array_items "$g" | head -n1)"
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then missing+=("$pkg"); fi
  done < <(mod_desktop_pkg_groups)
  if (( ${#missing[@]} )); then echo "not installed: ${missing[*]}"; return 1; fi
  echo "all enabled desktop apps are installed"
}

t_desk_lo_helper() {
  needs python3
  local py="$DESKTOP_DIR/files/lo_update_check.py"
  python3 -I "$py" check missing.xcu && return 1     # no file: not disabled
  python3 -I "$py" set missing.xcu
  python3 -I "$py" check missing.xcu
  python3 -I "$py" set missing.xcu                   # idempotent
  [[ "$(grep -c AutoCheckEnabled missing.xcu)" == 1 ]]
}

t_desk_policies() {
  needs_on DESKTOP_BROWSER_POLICIES
  python3 -I - "$DESKTOP_DIR/files/system/firefox-policies.json" \
    "$DESKTOP_DIR/files/system/thunderbird-policies.json" <<'EOT'
import json, sys
for path in sys.argv[1:]:
    pol = json.load(open(path))["policies"]
    for key in ("DisableTelemetry", "DisableAppUpdate"):
        assert pol.get(key) is True, f"{path}: {key} must be true"
print("policy templates are valid JSON and disable telemetry and updates")
EOT
}

# Lines printed here are no-cloud policy problems (they fail the self-test).
mod_desktop_nocloud_problems() {
  local gdir f backend
  if on "$DESKTOP_LIBREOFFICE" && have libreoffice \
     && ! python3 -I "$DESKTOP_DIR/files/lo_update_check.py" check "$LO_PROFILE_XCU" 2>/dev/null; then
    echo "LibreOffice online update check is not disabled in $LO_PROFILE_XCU"
  fi
  f="${XDG_CONFIG_HOME:-$HOME/.config}/keepassxc/keepassxc.ini"
  if on "$DESKTOP_KEEPASSXC" && have keepassxc; then
    if ! grep -q '^CheckForUpdates=false' "$f" 2>/dev/null; then echo "KeePassXC update check is not disabled ($f)"; fi
    if ! grep -q '^IconDownloadFallback=false' "$f" 2>/dev/null; then echo "KeePassXC may download website icons from a third party ($f)"; fi
  fi
  f="${XDG_CONFIG_HOME:-$HOME/.config}/vlc/vlcrc"
  if on "$DESKTOP_VLC" && have vlc; then
    if ! grep -q '^metadata-network-access=0' "$f" 2>/dev/null; then echo "VLC may fetch metadata/album art from the internet ($f)"; fi
    if ! grep -q '^qt-privacy-ask=0' "$f" 2>/dev/null; then echo "VLC would ask about network access on first start ($f)"; fi
  fi
  if on "$DESKTOP_GIMP" && have gimp; then
    gdir="$(gimp_config_dir)"
    if [[ -z $gdir ]] || ! grep -q '^(check-updates no)' "$gdir/gimprc" 2>/dev/null; then
      echo "GIMP update check is not disabled (${gdir:-unknown version}/gimprc)"
    fi
  fi
  if on "$DESKTOP_DEJADUP" && have deja-dup && have gsettings && have_desktop_session; then
    backend="$(gsettings get org.gnome.DejaDup backend 2>/dev/null || true)"
    case $backend in
      "'local'"|"'file'"|"'drive'") ;;
      *) echo "Déjà Dup backend is $backend, not a local folder or external disk" ;;
    esac
  fi
  if on "$DESKTOP_BROWSER_POLICIES"; then
    for f in "$FIREFOX_POLICY" "$THUNDERBIRD_POLICY"; do
      if [[ ! -f $f ]]; then echo "browser/mail policy file missing: $f"; continue; fi
      if ! python3 -I - "$f" <<'EOT'
import json, sys
pol = json.load(open(sys.argv[1])).get("policies", {})
sys.exit(0 if pol.get("DisableTelemetry") is True and pol.get("DisableAppUpdate") is True else 1)
EOT
      then echo "$f does not disable telemetry and updates"; fi
    done
  fi
}

# Lines printed here are warnings (the self-test reports WARN, not FAIL).
mod_desktop_nocloud_warnings() {
  if have snap; then
    local s
    for s in firefox thunderbird; do
      if snap list "$s" >/dev/null 2>&1; then
        echo "$s is a snap: snapd refreshes it from the Snap Store in the background. Keep it only if IT/you accept that."
      fi
    done
  fi
}
