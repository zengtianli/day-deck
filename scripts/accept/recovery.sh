#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

accept_scope 'recovery: exact production API/Store/Writer; isolated URLSession and temporary cache; no real service, Keychain, device or UI acceptance.'
accept_swift_tests 'RecoveryAcceptanceTests|CloudContractTests.testBadJSONAndOfflineKeepLastReadableCacheAndTimestamp|CloudContractTests.testStoreOfflineErrorIsVisibleAlongsideOldData|CloudContractTests.testForceCancelsOldRequestAndCannotOverwriteNewValueOrDisk'
