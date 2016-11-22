#!/bin/bash

show_usage() {
    echo "Usage: $0 [-d dir] <package>..." >&2
}


if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi


DOWNLOAD_DIR=""

if [ "$1" == "-d" ]; then
    if [ $# -lt 3 ]; then
        show_usage
        exit 1
    fi

    DOWNLOAD_DIR="$2"
    shift 2
fi


# Create download directory
[ -n "${DOWNLOAD_DIR}" ] && mkdir -p "${DOWNLOAD_DIR}"



requires() {
    zypper info --requires "$1" | sed -E '1,/^Requires/d;s/^\s*//;/^(rpmlib.*|)$/d'
}

provides() {
    zypper se --provides -x "$1" | sed -n -E '1,/--/d;0,/./s/^.[ |]+([^ ]+) .*/\1/p'
}

depends() {
    requires "$1" | while read -r req; do provides "$req"; done | sort -u | sed "/^$1\$/d"
}


# Queue of packages to be scanned
REMAINING=("$@")

# Packages already scanned
DEPENDENCIES=()


while [ ${#REMAINING[@]} -ne 0 ]; do
    package="${REMAINING[0]}"
    echo "Scanning dependencies for: $package" >&2

    for dep in $(depends "${package}"); do
        not_found=1

        # Check if the dependency was already scanned
        for e in "${DEPENDENCIES[@]}"; do
            if [ "$e" == "$dep" ]; then
                echo "  Already scanned: $dep" >&2
                not_found=0
                break
            fi
        done

        # If not found in the list of dependencies scanned, check if it
        # is already queued to be scanned.
        if [ $not_found -eq 1 ]; then
            for e in "${REMAINING[@]}"; do
                if [ "$e" == "$dep" ]; then
                    echo "  Already queued: $dep" >&2
                    not_found=0
                    break
                fi
            done
        fi

        if [ $not_found -eq 1 ]; then
            echo "  Queueing: $dep" >&2
            REMAINING+=("$dep")
        fi
    done

    REMAINING=("${REMAINING[@]:1}")
    DEPENDENCIES+=("$package")
done

echo >&2

echo "${DEPENDENCIES[@]}"


if [ -n "${DOWNLOAD_DIR}" ]; then
    zypper -n -C "${DOWNLOAD_DIR}" download "${DEPENDENCIES[@]}"
fi
