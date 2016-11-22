#!/bin/bash

show_usage() {
	echo >&2 "Usage: $0 [-o url_file] <package>..."
}


if [ $# -lt 1 ]; then
	show_usage
	exit 1
fi

URL_FILE=
if [ "$1" == "-o" ]; then
	if [ $# -lt 3 ]; then
		show_usage
		exit 1
	fi

	URL_FILE="$2"
	truncate -s 0 "${URL_FILE}"
	shift 2
fi


export http{,s}_proxy=http://16.85.88.10:8088/

echo "Building repository URL cache..."
declare -A REPOSITORIES
while read -r -a args; do
	repo_name=""
	for ((i = 4; i < ${#args[@]}; i++)); do
		if [ "${args[$i]}" == "|" ]; then
			repo_name="${args[@]:4:$[i-4]}"
			break
		fi
	done

	if [ -z "$repo_name" ]; then
		echo >&2 "ERRO: Failed to parse repository name"
		exit 5
	fi

	repo_url="${args[$[${#args[@]}-1]]}"
	datadir=$(curl "${repo_url}/content" 2> /dev/null | sed -n -E '/^DATADIR/s/^[^ ]+ +(.*)$/\1/p')
	
	if [ -n "${datadir}" ]; then
		repo_url="${repo_url%%/}/${datadir}/"
	fi

	echo "  ${repo_name}: ${repo_url%%/}/"
	REPOSITORIES["${repo_name}"]="${repo_url%%/}/"
done < <(zypper repos -u | sed '1,/^--/d')
echo


search_providers() {
	echo "Searching providers for '$1'..."
	zypper search --provides -x -s "$1" | sed '1,/^--/d;s/| //g' | while read -r -a args; do
		repo_name="${args[@]:4}"
		repo_url="${REPOSITORIES[${repo_name}]}"
		package="${args[0]}"
		version="${args[2]}"
		arch="${args[3]}"

		pkg_url="${repo_url%%/}/${arch}/${package}-${version}.${arch}.rpm"
		echo "  ${pkg_url}"

		[ -n "${URL_FILE}" ] && echo "${pkg_url}" >> "${URL_FILE}"
	done
}


for pkg in "${@}"; do
	search_providers "${pkg}"
done
