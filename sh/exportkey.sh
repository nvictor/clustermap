#!/usr/bin/env bash
set -euo pipefail

security export -t identities -f pkcs12 -k ~/Library/Keychains/login.keychain-db -o DeveloperID.p12
