#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

accept_scope 'recovery: exact production API/Store/Writer; isolated URLSession and temporary cache; 云端失败时提醒小节独立、保存失败不标已加入; no real service, Keychain, device or UI acceptance.'
accept_swift_tests 'RecoveryAcceptanceTests|CloudContractTests.testBadJSONAndOfflineKeepLastReadableCacheAndTimestamp|CloudContractTests.testStoreOfflineErrorIsVisibleAlongsideOldData|CloudContractTests.testForceCancelsOldRequestAndCannotOverwriteNewValueOrDisk'
