# mia-retext (apt package)

`sudo apt install mia-retext` installs this fork's ReText from
`https://apt.sanctuaireagentique.com`, the repository that also serves
`parallel-code` and the `miadi-*` packages. Add the repository first:

```bash
curl -fsSL https://apt.sanctuaireagentique.com/sanctuaire-agentique.gpg \
  | sudo tee /usr/share/keyrings/sanctuaire-agentique.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/sanctuaire-agentique.gpg] https://apt.sanctuaireagentique.com stable main" \
  | sudo tee /etc/apt/sources.list.d/sanctuaire-agentique.list
sudo apt update && sudo apt install mia-retext
```

| | |
|---|---|
| replaces | the distribution's `retext` (`Provides`, `Conflicts`, `Replaces`): installing one removes the other |
| runs | `/usr/bin/retext` → `/usr/lib/mia-retext/venv/bin/retext` |
| venv | built by `postinst` from `/usr/share/mia-retext/wheels` with `--no-index`, for the host's `python3` (3.10 to 3.14); rebuilt when a package installs `/usr/bin/python3`; removed by `prerm` |
| wheels | ReText built from this checkout, and PyQt6, Markups, Markdown, docutils, Pygments, pyenchant, chardet pinned in `wheels/requirements.txt` |
| not included | the WebEngine preview (`PyQt6-WebEngine`) |

Ubuntu 22.04 has no PyQt6 and only Markups 3, so ReText 8 cannot use the
distribution's Python packages there.

## Version

`Version:` in `mia-retext/DEBIAN/control` is `<upstream>-mia<N>`. `<upstream>`
must equal `pyproject.toml`'s version, or `build.sh` stops. Bump `N` for a change
of ours; after merging an upstream release, set `<upstream>` to it and `N` to 1.

## Build, test, release

```bash
bash packaging/deb/build.sh                          # -> packaging/deb/dist/mia-retext_<version>_amd64.deb
bash packaging/deb/test-install.sh packaging/deb/dist/mia-retext_<version>_amd64.deb   # docker: ubuntu:22.04, ubuntu:24.04
bash packaging/deb/release.sh                        # GitHub Release v<version>, then the apt index
```

`build.sh` needs `python3` with pip, Qt's `lrelease` (Ubuntu: `qt6-l10n-tools`)
and `dpkg-deb`. The package is about 105 MB, over the 100 MB the apt Worker
accepts, so `release.sh` attaches it to the GitHub Release and publishes it with
mia-parallel-code's `scripts/apt-publish.sh` and that release asset's URL: the
apt pool redirects there, as it does for `parallel-code`. Publishing needs
`APT_PUBLISH_TOKEN` in `~/.config/sanctuaire-apt.env` and the signing key
`43AEC70665D2B71FC9B53C7DB936F575CFCBE635` in the local gpg keyring.
