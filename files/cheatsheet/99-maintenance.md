## Workstation maintenance

Run these from the setup folder. The profile chosen at install time
(`~/.config/workstation/profile`) is remembered; `--profile NAME` overrides it.

```bash
./setup.sh --explain     # plain-language tour of every step; what is on/off (changes nothing)
./setup.sh --full        # the FULL setup: also every opt-in system change (add --explain to preview)
./setup.sh --check       # preview what setup would do, down to packages (changes nothing)
./setup.sh --self-test   # verify toolchains and the no-cloud policy
./setup.sh --manifest    # list all installed software and versions
./setup.sh --lock        # pin current versions (locks/<profile>.lock)
./setup.sh --upgrade     # move to the newest stable versions, then --lock again
./setup.sh --undo        # take back an install run (lists every command first, asks before running)
ws-doctor                # quick, read-only health check (no repository needed)
./setup.sh --list-profiles
```

Each install run leaves `~/workstation-undo-<timestamp>.sh` (reverses changes),
`~/workstation-manifest-latest.txt` and a log file in your home directory.
Installed APT packages can be reverted with `apt history-list` and
`sudo apt history-undo <ID>` (APT 3 and later; otherwise see
/var/log/apt/history.log).
