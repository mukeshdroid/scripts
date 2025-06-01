#!/usr/bin/env bash
#
# 03-post-reboot.sh
#
# Run as the ubuntu user after the machine has rebooted. This brings up Docker
# containers via "just bento up" and then runs the RiscZero multi-GPU test.
#
# Usage:
#     chmod +x 03-post-reboot.sh
#     ./03-post-reboot.sh

set -euo pipefail

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  [03] Post-reboot: Spinning up Docker (just bento up) and running test"
echo "────────────────────────────────────────────────────────────────────────"
echo ""

cd "$HOME/boundless"

# 3.a) Start the Bento stack via just (this will pull/build Docker images)
just bento up

echo ""
echo "→ Docker containers are now running."

# 3.b) Run the RiscZero multi-GPU test:
echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  Running the RiscZero multi-GPU test (this may take a few minutes)…"
echo "────────────────────────────────────────────────────────────────────────"
time RUST_LOG=info bento_cli -s -c 4096

echo ""
echo "→ Test completed successfully!"