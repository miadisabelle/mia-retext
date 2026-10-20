#!/usr/bin/env bash
# Ship the built package as a GitHub Release and add it to apt.sanctuaireagentique.com.
#   bash packaging/deb/release.sh
#
# Preconditions: bash packaging/deb/build.sh has produced
# dist/mia-retext_<version>_amd64.deb for DEBIAN/control's Version. This script
# does not build. The tag is v<version>, made at HEAD if it does not exist.
#
# The .deb (about 105 MB) is over the 100 MB the apt Worker accepts, so, as for
# parallel-code, the repository indexes the release asset and redirects to it.
# Publishing uses mia-parallel-code's scripts/apt-publish.sh (APT_PUBLISH to use
# another copy), with APT_PUBLISH_TOKEN from ~/.config/sanctuaire-apt.env and the
# repository's signing key in the local gpg keyring.
#
# Idempotent: when the release exists, it only republishes the apt index.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../.."
publish=${APT_PUBLISH:-/workspace/repos/miadisabelle/mia-parallel-code/scripts/apt-publish.sh}

package=$(sed -n 's/^Package: //p' "$here/mia-retext/DEBIAN/control")
version=$(sed -n 's/^Version: //p' "$here/mia-retext/DEBIAN/control")
arch=$(sed -n 's/^Architecture: //p' "$here/mia-retext/DEBIAN/control")
tag="v$version"
repo_slug=$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#; s#\.git$##')
deb="$here/dist/${package}_${version}_${arch}.deb"

if [[ ! -f "$deb" ]]; then
	echo "Missing $deb: run bash packaging/deb/build.sh first." >&2
	exit 1
fi
built=$(dpkg-deb -f "$deb" Version)
if [[ "$built" != "$version" ]]; then
	echo "$deb is version $built, control says $version: rebuild." >&2
	exit 1
fi
[[ -f "$publish" ]] || { echo "No apt-publish script at $publish (set APT_PUBLISH)." >&2; exit 1; }

publish_to_apt() {
	if [[ -z "${APT_PUBLISH_TOKEN:-}" && ! -f "$HOME/.config/sanctuaire-apt.env" ]]; then
		echo "Skipping apt publish: no APT_PUBLISH_TOKEN (see $publish)." >&2
		return 0
	fi
	url=$(gh release view "$tag" --repo "$repo_slug" --json assets \
		-q ".assets[] | select(.name == \"$(basename "$deb")\") | .url")
	[[ -n "$url" ]] || { echo "Release $tag has no asset $(basename "$deb")." >&2; exit 1; }
	bash "$publish" "$deb" "$url"
}

if gh release view "$tag" --repo "$repo_slug" >/dev/null 2>&1; then
	echo "Release $tag already exists: https://github.com/${repo_slug}/releases/tag/${tag}"
	publish_to_apt
	exit 0
fi

if ! git rev-parse "$tag" >/dev/null 2>&1; then
	git tag -a "$tag" -m "$package $version"
fi
git push origin "$tag"

prev_tag=$(git tag -l 'v*-mia*' --sort=-v:refname | grep -vx "$tag" | head -1 || true)
if [[ -n "$prev_tag" ]]; then
	notes=$(git log --pretty=format:'- %s (%h)' "${prev_tag}..${tag}")
else
	notes="ReText $(sed -n 's/^version = "\(.*\)"$/\1/p' pyproject.toml) with the upstream commits after it, through $(git rev-parse --short "$tag^{commit}"), packaged for apt.sanctuaireagentique.com."
fi
notes="$notes

\`\`\`
sudo apt install $package
\`\`\`
(after adding the repository: https://apt.sanctuaireagentique.com)"

gh release create "$tag" --repo "$repo_slug" --title "$package $version" --notes "$notes" "$deb"
publish_to_apt
echo "Shipped: https://github.com/${repo_slug}/releases/tag/${tag}"
