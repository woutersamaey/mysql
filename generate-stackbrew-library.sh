#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	[5.7]='5'
	[8.0]='8 latest'
)

defaultDefaultVariant='oracle'
declare -A defaultVariants=(
	[5.7]='debian'
	[8.0]='debian'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

# sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "dir/dockerfile" or any file COPY'd from it
dirCommit() {
	local dir="$1"; shift
	local df="$1"; shift
	(
		cd "$dir"
		local files; files="$(
			git show "HEAD:./$df" | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			'
		)"
		fileCommit "$df" $files
	)
}

cat <<-EOH
# this file is generated via https://github.com/docker-library/mysql/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/mysql.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version; do
	export version

	defaultVariant="${defaultVariants[$version]:-$defaultDefaultVariant}"
	fullVersion="$(jq -r '.[env.version].version' versions.json)"

	versionAliases=()
	while [ "$fullVersion" != "$version" -a "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		versionAliases+=( $fullVersion )
		fullVersion="${fullVersion%[.-]*}"
	done
	versionAliases+=(
		$version
		${aliases[$version]:-}
	)

	for variant in oracle debian; do
		df="Dockerfile.$variant"
		commit="$(dirCommit "$version" "$df")"

		variantAliases=( "${versionAliases[@]/%/-$variant}" )
		variantAliases=( "${variantAliases[@]//latest-/}" )
		if [ "$variant" = "$defaultVariant" ]; then
			variantAliases=( "${versionAliases[@]}" "${variantAliases[@]}" )
		fi

		# TODO if the list of architectures supported by MySQL ever is greater than that of the base image it's FROM, this list will need to be filtered
		export variant
		variantArches="$(jq -r '.[env.version][env.variant].architectures | join(", ")' versions.json)"

		echo
		cat <<-EOE
			Tags: $(join ', ' "${variantAliases[@]}")
			Architectures: $variantArches
			GitCommit: $commit
			Directory: $version
			File: $df
		EOE
	done
done
