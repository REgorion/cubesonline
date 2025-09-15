#!/usr/bin/env bash
set -eu

VERSION_FILE="assets/version.txt"

mkdir -p "$(dirname "$VERSION_FILE")"

if [ -f "$VERSION_FILE" ]; then
    # ищем формат вида: x.y.z build N
    ver=$(grep -m1 -Eo '^[0-9]+\.[0-9]+\.[0-9]+( build [0-9]+)?' "$VERSION_FILE" || true)
    if [ -n "$ver" ]; then
        if [[ "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(\ build\ ([0-9]+))?$ ]]; then
            major="${BASH_REMATCH[1]}"
            minor="${BASH_REMATCH[2]}"
            patch="${BASH_REMATCH[3]}"
            build="${BASH_REMATCH[5]:-0}"
            build=$((build + 1))
            new_ver="$major.$minor.$patch build $build"

            # заменим только первую строку с версией
            awk -v old="$ver" -v new="$new_ver" 'NR==1 {sub(old,new)} {print}' \
                "$VERSION_FILE" > "$VERSION_FILE.tmp" && mv "$VERSION_FILE.tmp" "$VERSION_FILE"

            echo "$new_ver"
        fi
    else
        echo "0.0.1 build 1" > "$VERSION_FILE"
        echo "0.0.1 build 1"
    fi
else
    echo "0.0.1 build 1" > "$VERSION_FILE"
    echo "0.0.1 build 1"
fi
