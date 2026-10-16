#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/_common.sh"
accept_scope "core tests: all exact production SwiftPM XCTest cases, isolated scratch, shared BuildSlot; no simulator, focus or real user data."
accept_swift_tests DayDeckCoreTests
