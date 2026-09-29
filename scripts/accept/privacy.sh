#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"
accept_scope "privacy: production API/Store/Writer/Gate in isolated URLProtocol, ephemeral session and synthetic cache; 提醒事项零网络、零落盘; no device, live service or real Keychain access."
accept_swift_tests PrivacyAcceptanceTests
