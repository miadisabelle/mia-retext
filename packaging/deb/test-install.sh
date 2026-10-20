#!/usr/bin/env bash
# Install a built mia-retext in a clean container and check it runs.
#   bash packaging/deb/test-install.sh dist/mia-retext_<version>_amd64.deb [image ...]
# Images default to ubuntu:22.04 and ubuntu:24.04. In each: the distribution's
# retext is installed first and must be replaced; the venv is built; every library
# the Qt xcb platform plugin needs resolves; ReText opens a file under Xvfb and is
# still running after 8 seconds; a reinstalled python3 rebuilds the venv through the
# trigger; removing the package removes the venv.
set -euo pipefail
deb=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
shift
images=${*:-ubuntu:22.04 ubuntu:24.04}

for image in $images; do
	echo "==> $image"
	docker run --rm -v "$deb:/tmp/$(basename "$deb"):ro" "$image" bash -euc '
		export DEBIAN_FRONTEND=noninteractive
		deb=/tmp/'"$(basename "$deb")"'
		apt-get update -qq
		apt-get install -y -qq --no-install-recommends retext xvfb xauth >/dev/null
		apt-get install -y -qq --no-install-recommends "$deb" >/dev/null
		! dpkg -s retext >/dev/null 2>&1 || { echo "FAIL: retext still installed"; exit 1; }
		echo "    replaced retext: $(dpkg-query -W -f="\${Package} \${Version}" mia-retext)"
		plugin=$(ls /usr/lib/mia-retext/venv/lib/python3*/site-packages/PyQt6/Qt6/plugins/platforms/libqxcb.so)
		if ldd "$plugin" | grep "not found"; then echo "FAIL: libraries missing for $plugin"; exit 1; fi
		echo "    xcb plugin: every library resolves"
		printf "# Test\n\nSome *Markdown*.\n" > /tmp/test.md
		set +e
		HOME=/tmp xvfb-run -a timeout 8 retext /tmp/test.md 2>/tmp/retext.err
		rc=$?
		set -e
		[ "$rc" = 124 ] || { echo "FAIL: retext exited $rc"; cat /tmp/retext.err; exit 1; }
		echo "    retext ran under Xvfb until stopped"
		before=$(stat -c %Y /usr/lib/mia-retext/venv/pyvenv.cfg)
		sleep 1
		apt-get install -y -qq --reinstall python3-minimal >/dev/null
		after=$(stat -c %Y /usr/lib/mia-retext/venv/pyvenv.cfg)
		[ "$after" != "$before" ] || { echo "FAIL: reinstalling python3-minimal did not rebuild the venv"; exit 1; }
		echo "    python3-minimal reinstalled: venv rebuilt"
		apt-get remove -y -qq mia-retext >/dev/null
		[ ! -e /usr/lib/mia-retext/venv ] || { echo "FAIL: venv left after remove"; exit 1; }
		echo "    removed: venv gone"
	'
done
echo "==> all passed"
