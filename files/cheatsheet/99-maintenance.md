## Workstation maintenance

Run these from the setup folder. The profile chosen at install time
(`~/.config/workstation/profile`) is remembered; `--profile NAME` overrides it.

```bash
./setup.sh --check       # preview what setup would do (changes nothing)
./setup.sh --self-test   # verify toolchains and the no-cloud policy
./setup.sh --manifest    # list all installed software and versions
./setup.sh --lock        # pin current versions (locks/<profile>.lock)
./setup.sh --upgrade     # move to the newest stable versions, then --lock again
./setup.sh --list-profiles
```

Each install run leaves `~/workstation-undo-<timestamp>.sh` (reverses changes),
`~/workstation-manifest-latest.txt` and a log file in your home directory.
Installed APT packages can be reverted with `apt history-list` and
`sudo apt history-undo <ID>` (APT 3 and later; otherwise see
/var/log/apt/history.log).
