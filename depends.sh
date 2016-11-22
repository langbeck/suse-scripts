#!/bin/bash

show_usage() {
    echo >&2 "Usage: $0 [options...] <package>..."
    echo >&2 "Options:"
    echo >&2 "  -c <cache_dir>      Set directory used as cache by zypper"
    echo >&2 "  -d <dest_dir>       Set destination directory to downloaded RPMs"
    echo >&2 "  -h --help           Display this message"
    echo >&2 "  -q --quiet          Quiet mode"
    echo >&2 "  -v --verbose        Set verbose mode"
    echo >&2 "  -vv -vvv            Set increased verbose mode"
}


CACHE_DIR="/var/cache/zypp"
DEST_DIR="${PWD}"
VERBOSE=0

while true; do
    [ "${1::1}" != "-" ] && break

    case "${1}" in
        "-c" | "--cache")   CACHE_DIR="$2"; shift 2;;
        "-d" | "--dest")    DEST_DIR="$2"; shift 2;;
        "-h" | "--help")    show_usage; exit 0;;
        "-q" | "--quiet")   VERBOSE=-1; shift;;
        "-v" | "--verbose") VERBOSE=1; shift;;
        "-vv")              VERBOSE=2; shift;;
        "-vvv")             VERBOSE=3; shift;;
        *)                  echo >&2 "Unknow option: $1"; show_usage; exit 1
    esac
done

if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

if [ -z "${DEST_DIR}" ]; then
    echo >&2 "Empty destination directory. Using: $PWD"
    DEST_DIR="${PWD}"
fi


_log() { [ "${VERBOSE}" -ge "$1" ] && echo >&2 "${@:2}"; }



ZYPPER=(zypper -n)


if [ -n "${CACHE_DIR}" ]; then
    _log 3 ">> Using cache folder: ${CACHE_DIR}"
    mkdir -p "${CACHE_DIR}"
    ZYPPER+=(-C "${CACHE_DIR}")
fi


_log 3 ">> Default zypper flags: ${ZYPPER[@]}"
_log 3 ">> Creating destination folder: ${DEST_DIR}"
mkdir -p "${DEST_DIR}"




_zypper() {
    # Wrapper to enable easier debug
    _log 3 ">> RUN: ${ZYPPER[@]} $@"
    "${ZYPPER[@]}" "$@"
}

requires() {
    _zypper info --requires "$1" | sed -E '1,/^Requires/d;s/^\s*//;/^(rpmlib.*|)$/d'
}

provides() {
    _zypper search --provides -x "$1" | sed -n -E '1,/--/d;0,/./s/^.[ |]+([^ ]+) .*/\1/p'
}

depends() {
    requires "$1" | while read -r req; do provides "$req"; done | sort -u | sed "/^$1\$/d"
}


# Queue of packages to be scanned
REMAINING=("$@")

# Packages already scanned
DEPENDENCIES=()


_log 0 "Refreshing repositories..."
_zypper refresh > /dev/null


while [ ${#REMAINING[@]} -ne 0 ]; do
    package="${REMAINING[0]}"
    _log 0 "Scanning dependencies for ${package}..."

    for dep in $(depends "${package}"); do
        not_found=1

        # Check if the dependency was already scanned
        for e in "${DEPENDENCIES[@]}"; do
            if [ "$e" == "$dep" ]; then
                _log 2 "  Already scanned: $dep"
                not_found=0
                break
            fi
        done

        # If not found in the list of dependencies scanned, check if it
        # is already queued to be scanned.
        if [ $not_found -eq 1 ]; then
            for e in "${REMAINING[@]}"; do
                if [ "$e" == "$dep" ]; then
                    _log 2 "  Already queued: $dep"
                    not_found=0
                    break
                fi
            done
        fi

        if [ $not_found -eq 1 ]; then
            _log 1 "  Queueing: $dep"
            REMAINING+=("$dep")
        fi
    done

    REMAINING=("${REMAINING[@]:1}")
    DEPENDENCIES+=("$package")
done

_log 0 "Selected packages: ${DEPENDENCIES[@]}"

_log 0 "Starting packages download..."
_zypper download "${DEPENDENCIES[@]}"

_log 0 "Copying packages from cache..."
find "${CACHE_DIR}" -name '*.rpm' -exec cp {} "${DEST_DIR}" \;
