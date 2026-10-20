#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
sources="Shared/Station.swift Shared/Favourites.swift App/StreamConfiguration.swift App/ProgrammeMetadata.swift"
swiftc -module-cache-path "$check_dir/cache" $sources Tests/main.swift -o "$check_dir/catalogue"
"$check_dir/catalogue"
swiftc -module-cache-path "$check_dir/cache" $sources Tests/ScheduleTests.swift -o "$check_dir/schedules"
"$check_dir/schedules"
swiftc -module-cache-path "$check_dir/cache" $sources Tests/ListeningCheckpointTests.swift -o "$check_dir/listening"
"$check_dir/listening"
