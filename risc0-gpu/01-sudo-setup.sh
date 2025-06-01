#!/usr/bin/env bash
#
# 01-sudo-setup.sh
#
# Run as root (via sudo). Installs build-essential, Just, and nvtop on Ubuntu 22.04.
# Usage:
#     sudo ./01-sudo-setup.sh

set -euo pipefail

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  [01] Installing system dependencies (build-essential, Just, nvtop)"
echo "────────────────────────────────────────────────────────────────────────"
echo ""

# 1) Update package lists, upgrade any existing packages
apt update
apt upgrade -y

# 2) Install build-essential (gcc/g++, make, etc.) and xz-utils (required later to unpack .tar.xz)
apt install -y build-essential xz-utils

# 3) Install Just (task runner) via snap
snap install core || true
snap refresh core || true
snap install just --classic

# 4) Install nvtop (GPU‐monitoring tool)
apt install -y nvtop

echo ""
echo "→ System dependencies installed:"
echo "   • build-essential"
echo "   • xz-utils"
echo "   • just (via snap)"
echo "   • nvtop"
echo ""
echo "--------------------------------------------------------------------"
echo "  Now switch to the ubuntu user and run 02-user-setup.sh"
echo "--------------------------------------------------------------------"