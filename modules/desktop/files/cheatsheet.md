## Desktop module (everyday apps, no background network)

| App | What was switched off | Where |
|---|---|---|
| LibreOffice | online update check | `~/.config/libreoffice/4/user/registrymodifications.xcu` |
| KeePassXC | update check, third-party website-icon downloads | `~/.config/keepassxc/keepassxc.ini` |
| VLC | metadata / album-art lookups, first-run network dialog | `~/.config/vlc/vlcrc` |
| GIMP | update check | `~/.config/GIMP/<version>/gimprc` |
| Déjà Dup | backend limited to a local folder / external disk | GNOME settings (`org.gnome.DejaDup`) |
| Firefox, Thunderbird | telemetry, studies, Pocket, accounts, updates, sponsored content, Safe Browsing, captive-portal probes | `/etc/firefox/policies/policies.json`, `/etc/thunderbird/policies/policies.json` |

Inkscape has no automatic network features. Apps are Debian packages from the
Ubuntu archive; no snaps or Flatpaks are installed by this setup.

Traffic you start yourself (opening a website, fetching mail from your own
server) is fine. Everything automatic is off. **Safe Browsing is disabled in
Firefox** because it contacts Google in the background; be careful with
downloads and links.

Check that Firefox picked up the policy: open `about:policies`.
GNOME Online Accounts (Settings > Online Accounts) should stay empty; the
self-test warns if an account is set up.

Languages: set `DESKTOP_LANGUAGES="de fr"` in your profile or environment and
re-run `./setup.sh` to install dictionaries and LibreOffice language packs.
