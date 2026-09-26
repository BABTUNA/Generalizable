#!/bin/zsh
# DEMO ONLY. Compile App/Core with the self-test for macOS, then run it on every bundle in App/Cases.
set -euo pipefail
cd "${0:A:h}/.."
out=build/core_selftest
mkdir -p build
xcrun swiftc -O -o "$out" App/Core/*.swift scripts/selftest/main.swift
"$out" App/Cases
