#!/usr/bin/env bash
set -euo pipefail

xcodebuild clean build -scheme Clustermap -project /Users/victor/Developer/clustermap/Clustermap/Clustermap.xcodeproj
echo "📦 Build completed successfully."
