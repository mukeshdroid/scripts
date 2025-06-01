#!/usr/bin/env bash
#
# 02-user-setup.sh
#
# Run as the ubuntu user (no leading sudo). Installs Rust, RiscZero, bento_cli,
# and clones the Boundless repo. Then installs NVIDIA drivers and reboots.
#
# Usage:
#     chmod +x 02-user-setup.sh
#     ./02-user-setup.sh

set -euo pipefail

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  [02] Installing Rust, RiscZero, bento_cli, and cloning Boundless"
echo "────────────────────────────────────────────────────────────────────────"
echo ""

# 2.a) Install Rust (via rustup) into /home/ubuntu/.cargo
curl --proto '=https' --tlsv1.2 -sSf "https://sh.rustup.rs" | sh -s -- -y

# 2.b) Immediately load ~/.cargo/env so that rustc/cargo are on PATH in this shell
source "$HOME/.cargo/env"

# 2.c) Verify that rustc is available
echo "→ $(rustc --version)"

# 2.d) Install RiscZero (rzup + cargo-risczero):
curl -L "https://risczero.com/install" | bash

# 2.e) Make sure rzup is on PATH in this shell right now
export PATH="$HOME/.risc0/bin:$PATH"

# 2.f) Install RiscZero toolchain (rust for RiscZero) via rzup
rzup install rust

# 2.g) Install the Cargo RiscZero plugin at version 2.0.2
rzup install cargo-risczero 2.0.2

echo ""
echo "→ RiscZero installed: "
echo "   • rzup at $(which rzup)"
echo "   • RiscZero toolchain at $HOME/.risc0/toolchains/"
echo "   • cargo‐risczero plugin v2.0.2"

# 2.h) Install bento_cli from the GitHub fork/branch
cargo install \
  --git "https://github.com/alpenlabs/risc0" \
  --branch "mukesh/add_bento_to_v2.0" \
  bento-client --bin bento_cli

echo ""
echo "→ bento_cli installed at $HOME/.cargo/bin/bento_cli"

# 2.i) Clone the Boundless repository and checkout the multi-GPU branch
if [ -d "$HOME/boundless" ]; then
  echo "→ Boundless already cloned at ~/boundless. Updating branch..."
  cd "$HOME/boundless"
  git fetch
  git checkout mukesh/multiple_gpu
  git pull origin mukesh/multiple_gpu
else
  git clone https://github.com/alpenlabs/boundless "$HOME/boundless"
  cd "$HOME/boundless"
  git checkout mukesh/multiple_gpu
fi
echo "→ Boundless is now at ~/boundless (branch: mukesh/multiple_gpu)"

# 2.j) Install NVIDIA drivers and Docker (via the repo’s setup.sh). Requires sudo.
echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  Installing NVIDIA drivers & nvidia-docker (this may take a few minutes)"
echo "────────────────────────────────────────────────────────────────────────"
sudo chmod +x "$HOME/boundless/scripts/setup.sh"
sudo env PATH="$HOME/.risc0/bin:$PATH" "$HOME/boundless/scripts/setup.sh"

echo ""
echo "→ NVIDIA drivers and docker packages installed."

# 2.k) Reboot the machine to finalize driver installation
echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  Rebooting now to activate NVIDIA drivers…"
echo "────────────────────────────────────────────────────────────────────────"
sleep 3
sudo reboot