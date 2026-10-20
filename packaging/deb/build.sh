#!/usr/bin/env bash
# Build mia-retext from this checkout into packaging/deb/dist/.
#   bash packaging/deb/build.sh   -> dist/mia-retext_<version>_amd64.deb (its path on stdout)
#
# <version> is DEBIAN/control's Version, <upstream>-mia<N>: <upstream> must be
# pyproject.toml's version. The package carries wheels, not a venv: ReText built
# from this checkout, and its dependencies from PyPI resolved once for CPython 3.10
# (Ubuntu 22.04), pinned in wheels/requirements.txt, then fetched for 3.11 to 3.14
# so postinst finds the binary ones for whatever python3 the host has.
#
# Needs: python3 with pip, lrelease (Qt's, for the translations), dpkg-deb.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../.." && pwd)
tree=$here/mia-retext
py=${PYTHON:-python3}
pythons="3.10 3.11 3.12 3.13 3.14"
# Wheels that run on glibc 2.35 (Ubuntu 22.04). pip does not widen a manylinux
# tag to the older ones it covers, so each is named.
platforms=$(for m in $(seq 35 -1 17); do printf -- '--platform manylinux_2_%s_x86_64 ' "$m"; done)
platforms="$platforms --platform manylinux2014_x86_64"
extras=spellcheck,encoding-detection

package=$(sed -n 's/^Package: //p' "$tree/DEBIAN/control")
version=$(sed -n 's/^Version: //p' "$tree/DEBIAN/control")
arch=$(sed -n 's/^Architecture: //p' "$tree/DEBIAN/control")
upstream=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$src/pyproject.toml")
if [ "${version%%-*}" != "$upstream" ]; then
	echo "error: control Version $version does not start with pyproject.toml's $upstream-" >&2
	exit 1
fi

stage=$(mktemp -d)
work=$(mktemp -d)
trap 'rm -rf "$stage" "$work"' EXIT
export PIP_DISABLE_PIP_VERSION_CHECK=1

# setup.py's build_translations runs too late for the wheel to pick up the .qm
# files, so they are compiled first, beside the .ts files (git-ignored there).
lrelease=$(command -v "$(qmake6 -query QT_INSTALL_BINS 2>/dev/null)/lrelease" || command -v lrelease6 || command -v lrelease) || {
	echo "error: no lrelease (Ubuntu: qt6-l10n-tools)" >&2
	exit 1
}
echo "==> translations with $lrelease" >&2
for ts in "$src"/ReText/locale/*.ts; do "$lrelease" -silent "$ts" >&2; done

echo "==> ReText wheel from $src" >&2
"$py" -m pip wheel -q --no-deps --wheel-dir "$work/retext" "$src" >&2
wheel=$(ls "$work"/retext/[Rr]e[Tt]ext-*.whl)
# grep reads all of the listing: -q would close the pipe early and pipefail would fail on unzip.
if ! unzip -Z1 "$wheel" | grep '^ReText/locale/retext_.*\.qm$' >/dev/null; then
	echo "error: $wheel has no translations; is Qt's lrelease on PATH?" >&2
	exit 1
fi

wheels=$stage/usr/share/$package/wheels
mkdir -p "$wheels"
cp "$wheel" "$wheels/"

first=${pythons%% *}
echo "==> dependencies for CPython $first" >&2
"$py" -m pip download -q --dest "$wheels" --only-binary=:all: \
	--python-version "$first" $platforms "$wheel[$extras]" >&2
# One pinned set for every Python: name==version of each wheel, ReText included.
for w in "$wheels"/*.whl; do
	b=$(basename "$w")
	echo "${b%%-*}==$(echo "$b" | cut -d- -f2)"
done | sort -u > "$wheels/requirements.txt"
for v in ${pythons#"$first"}; do
	echo "==> dependencies for CPython $v" >&2
	grep -iv '^retext==' "$wheels/requirements.txt" > "$work/deps.txt"
	"$py" -m pip download -q --dest "$wheels" --only-binary=:all: \
		--python-version "$v" $platforms -r "$work/deps.txt" >&2
done

cp -a "$tree/." "$stage/"
install -D -m 0644 "$src/data/me.mitya57.ReText.desktop" "$stage/usr/share/applications/me.mitya57.ReText.desktop"
install -D -m 0644 "$src/data/me.mitya57.ReText.metainfo.xml" "$stage/usr/share/metainfo/me.mitya57.ReText.metainfo.xml"
install -D -m 0644 "$src/ReText/icons/retext.svg" "$stage/usr/share/icons/hicolor/scalable/apps/retext.svg"
mkdir -p "$stage/usr/share/doc/$package"
{
	printf 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n'
	printf 'Upstream-Name: ReText\nSource: https://github.com/miadisabelle/mia-retext\n\n'
	printf 'Files: *\nCopyright: 2011-2025 Dmitry Shachnev and ReText contributors\nLicense: GPL-2+\n'
	printf ' On Debian systems the full text of the GNU General Public License\n'
	printf ' version 2 is in /usr/share/common-licenses/GPL-2.\n'
	printf '\nFiles: usr/share/%s/wheels/*\nCopyright: their authors\n' "$package"
	printf 'License: various\n Each wheel carries its own license in its .dist-info directory.\n'
} > "$stage/usr/share/doc/$package/copyright"
cp "$src/changelog.md" "$stage/usr/share/doc/$package/"

find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -exec chmod 0644 {} +
chmod 0755 "$stage/usr/bin/retext" "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm"

mkdir -p "$here/dist"
out=$here/dist/${package}_${version}_${arch}.deb
dpkg-deb --root-owner-group -Zxz --build "$stage" "$out" >&2
echo "$out"
