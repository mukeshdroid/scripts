#!/usr/bin/env bash

################################################################################
# setup_risczero_multi_gpu.sh
#
# Automates the installation and configuration steps for RiscZero multi-GPU
# support on an AWS Ubuntu 22.04 instance with ≥100 GB storage.
#
# USAGE:
#   1) First run (pre-reboot): 
#        sudo ./setup_risczero_multi_gpu.sh
#      → Installs everything up to NVIDIA drivers and then reboots.
#
#   2) After reboot finishes and you SSH back in, run:
#        sudo ./setup_risczero_multi_gpu.sh post-reboot
#      → Continues in the 'boundless' directory: spins up Docker + runs test.
#
# NOTES:
#   • The script assumes Ubuntu 22.04 LTS. It will abort if the OS is not 22.04.
#   • It checks for at least 100 GB free space on "/"—if you attached a larger EBS
#     volume as root, this should pass. Otherwise it will warn and exit.
#   • If you want to tweak versions (Rust, risczero, bento_cli, branch names, etc.),
#     see the comments in each section below.
#   • You can modify any of the "VERSION" variables near the top to pin to a
#     different release.
#
#   • Before running, ensure you are already on an AWS instance with:
#       – Ubuntu 22.04 LTS AMI
#       – A multi-GPU instance type (e.g., g6.12xlarge, p4d.24xlarge, etc.)
#       – At least 100 GB of root (/) storage attached (or a separate mount with ≥100 GB)
#
#   • This script should be run as root (or via sudo). It will refuse to run otherwise.
#
################################################################################

set -euo pipefail

#───────────────────────────────────────────────────────────────────────────#
#  Configuration Variables (edit these if you need different versions)     #
#───────────────────────────────────────────────────────────────────────────#
RUSTUP_INIT_URL="https://sh.rustup.rs"        # Rust installer (defaults to latest stable)
JUST_VERSION="latest"                         # If you want a specific Just version, replace "latest" with, e.g., "1.14.0"
RISCZERO_CLI_INSTALLER="https://risczero.com/install"
# Pin which Cargo RiscZero plugin version you want:
CARGO_RISCZERO_PLUGIN_VERSION="2.0.2"
# bento_cli repo details:
BENTO_REPO="https://github.com/alpenlabs/risc0"
BENTO_BRANCH="mukesh/add_bento_to_v2.0"
# Boundless repo details:
BOUNDLESS_REPO="https://github.com/alpenlabs/boundless"
BOUNDLESS_BRANCH="mukesh/multiple_gpu"
# Minimum free space (in GB) required on '/'
MIN_FREE_GB=100

#───────────────────────────────────────────────────────────────────────────#
#  Helper Functions                                                        #
#───────────────────────────────────────────────────────────────────────────#

# Print an error message and exit
err() {
  echo "ERROR: $*" >&2
  exit 1
}

# Check that we are running as root (script uses apt, snap, reboot, etc.)
ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root (or via sudo)."
  fi
}

# Check that the OS is Ubuntu 22.04
check_os() {
  # /etc/os-release contains lines like: VERSION_ID="22.04"
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ "$NAME" != "Ubuntu" ] || [ "$VERSION_ID" != "22.04" ]; then
      err "This script is designed for Ubuntu 22.04. Detected: $NAME $VERSION_ID"
    fi
  else
    err "/etc/os-release not found. Cannot verify OS version."
  fi
}

# Check that / has at least MIN_FREE_GB free, otherwise exit.
check_disk_space() {
  # Use df to check free space on '/'
  local free_kb
  free_kb=$(df --output=avail / | tail -n1)
  # Convert to GB (use integer division)
  local free_gb=$(( free_kb / 1024 / 1024 ))
  if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
    err "Not enough free space on '/'. Required: ≥${MIN_FREE_GB} GB. Found: ${free_gb} GB."
  fi
  echo "→ Free space check passed: ${free_gb} GB available on '/'."
}

#───────────────────────────────────────────────────────────────────────────#
#  Main Script Logic                                                       #
#───────────────────────────────────────────────────────────────────────────#

## Determine whether we are in "pre-reboot" mode or "post-reboot" mode.
## The user should explicitly pass "post-reboot" as $1 after reboot.
MODE="pre-reboot"
if [ "${1:-}" = "post-reboot" ]; then
  MODE="post-reboot"
fi

#───────────────────────────────────────────────────────────────────────────#
#  Pre-Reboot Phase                                                        #
#───────────────────────────────────────────────────────────────────────────#
if [ "$MODE" = "pre-reboot" ]; then
  echo "===================================================================="
  echo "          RiscZero Multi-GPU Setup: PRE-REBOOT PHASE"
  echo "===================================================================="
  echo ""

  ensure_root
  check_os
  check_disk_space

  ##############################################################################
  # 2. Install Rust (via rustup) — but AS ubuntu, not root
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 2: Install Rust (via rustup) as ubuntu"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  # Run the rustup installer as ubuntu. This places ~/.cargo in /home/ubuntu/.cargo
  sudo -u ubuntu bash -lc "curl --proto '=https' --tlsv1.2 -sSf \"$RUSTUP_INIT_URL\" | sh -s -- -y"
  
  # Now ensure the ubuntu user’s ~/.cargo/bin is on PATH for the rest of the ubuntu‐commands.
  # We’ll reload ubuntu’s ~/.bashrc (or ~/.zshrc) so that PATH="$HOME/.cargo/bin" takes effect.
  sudo -u ubuntu bash -lc "source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null"
  
  # (Optional) Verify under ubuntu that rustc is installed:
  sudo -u ubuntu bash -lc "rustc --version"
  
  # For the remainder of any echo/logging under root, you can still print a confirmation:
  echo "→ Rust installed under /home/ubuntu/.cargo (user: ubuntu)."

  . "$HOME/.cargo/env"

  ##############################################################################
  # 3. Install build dependencies and Just
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 3: Update & install build-essential + Just"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  apt update

  # build-essential provides gcc, g++, make, etc.
  apt install -y build-essential

  # Snap should already be present on Ubuntu 22.04, but ensure it's up to date:
  snap install core || true
  snap refresh core || true

  # Install Just (task runner). If you want a specific version, see https://github.com/casey/just/releases
  if [ "$JUST_VERSION" = "latest" ]; then
    snap install just --classic
  else
    snap install just --classic --channel="$JUST_VERSION"
  fi
  echo "→ build-essential and Just installed."

  ##############################################################################
  # 4. Install nvtop (NVIDIA GPU monitoring tool)
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 4: Install nvtop"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  apt install -y nvtop
  echo "→ nvtop installed."

  ##############################################################################
  # 5. Install risczero (under ubuntu, not root)
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 5: Install RiscZero (rzup + cargo-risczero) as ubuntu"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""

  # 5.a) Use sudo -u ubuntu so that RiscZero is placed into /home/ubuntu/.risc0, not /root/.risc0.
  #     The ubuntu user must already exist (it does by default on standard EC2 Ubuntu AMIs).
  sudo -u ubuntu bash -c "curl -L \"$RISCZERO_CLI_INSTALLER\" | bash"

  # 5.b) Now force ubuntu’s login shell to re‐load ~/.bashrc or ~/.zshrc (whatever got updated),
  #      so that $HOME/.risc0/bin appears in ubuntu’s PATH immediately.
  sudo -u ubuntu bash -lc "source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null"

  # 5.c) Next, invoke rzup (as ubuntu) to install the cargo-risczero plugin:
  sudo -u ubuntu bash -lc "rzup install cargo-risczero \"$CARGO_RISCZERO_PLUGIN_VERSION\""

  # 5.d) Optionally install the recommended Rust toolchain via rzup (still as ubuntu):
  sudo -u ubuntu bash -lc "rzup install rust"

  echo "→ risczero installed for ubuntu (cargo-risczero v${CARGO_RISCZERO_PLUGIN_VERSION})."

  ##############################################################################
  # 6. Install bento_cli (via Cargo) as ubuntu
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 6: Install bento_cli via Cargo (as ubuntu)"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  sudo -u ubuntu bash -lc "cargo install --git \"$BENTO_REPO\" \
                            --branch \"$BENTO_BRANCH\" \
                            bento-client --bin bento_cli"
  echo "→ bento_cli installed for ubuntu (branch '$BENTO_BRANCH')."

  ##############################################################################
  # 7. Clone Boundless repo + checkout branch (as ubuntu)
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 7: Clone Boundless repo + checkout branch (as ubuntu)"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  BOUNDLESS_DIR=\"\$UBUNTU_HOME/boundless\"

  sudo -u ubuntu bash -lc "
    if [ -d \"$BOUNDLESS_DIR\" ]; then
      echo \"→ '$BOUNDLESS_DIR' already exists. Skipping clone. Checking out branch...\"
      cd \"$BOUNDLESS_DIR\"
      git fetch
      git checkout \"$BOUNDLESS_BRANCH\"
      git pull origin \"$BOUNDLESS_BRANCH\"
    else
      git clone \"$BOUNDLESS_REPO\" \"$BOUNDLESS_DIR\"
      cd \"$BOUNDLESS_DIR\"
      git checkout \"$BOUNDLESS_BRANCH\"
    fi
  "
  echo "→ Boundless cloned into '/home/ubuntu/boundless' (branch '$BOUNDLESS_BRANCH')."

  ##############################################################################
  # 8. Install NVIDIA drivers and Docker & then REBOOT
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 8: Install NVIDIA drivers & Docker (via boundless/scripts/setup.sh)"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  echo "Note: This step will install the NVIDIA driver stack, nvidia-docker, "
  echo "      and configure Docker to use the NVIDIA runtime. It will then reboot."
  echo ""

  # The boundless repo includes a setup.sh that installs drivers + nvidia-docker
  chmod +x scripts/setup.sh
  yes | ./scripts/setup.sh

  echo ""
  echo "→ NVIDIA drivers, Docker, and nvidia-docker should now be installed."
  echo "→ The system must reboot to finish the driver install."
  echo "→ After reboot, SSH back in and run:"
  echo ""
  echo "     sudo $0 post-reboot"
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "Rebooting now..."
  echo "────────────────────────────────────────────────────────────────────────"
  sleep 5
  exec sudo reboot
  # The script will exit here, machine reboots, and user must re-run with 'post-reboot'
  exit 0
fi


#───────────────────────────────────────────────────────────────────────────#
#  Post-Reboot Phase                                                        #
#───────────────────────────────────────────────────────────────────────────#
if [ "$MODE" = "post-reboot" ]; then
  echo "===================================================================="
  echo "        RiscZero Multi-GPU Setup: POST-REBOOT PHASE"
  echo "===================================================================="
  echo ""

  ensure_root

  # Verify that boundless directory still exists
  BOUNDLESS_DIR="$HOME/boundless"
  if [ ! -d "$BOUNDLESS_DIR" ]; then
    err "Directory '$BOUNDLESS_DIR' not found. Did you clone it earlier? Exiting."
  fi

  cd "$BOUNDLESS_DIR"

  ##############################################################################
  # 9. Spin up Docker images via 'just bento up'
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 9: Spin up Docker images (just bento up)"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  # Just will read the Justfile in this directory and bring up the Bento stack
  # If you need to pass additional flags (e.g. -d for detached), update this line.
  just bento up
  echo "→ Docker containers are now running."

  ##############################################################################
  # 10. Run the RiscZero multi-GPU test
  ##############################################################################
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo "  STEP 10: Run the test (RUST_LOG=info bento_cli -s -c 4096)"
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
  echo "Logging output as RUST_LOG=info; this may take a few minutes the first time."
  time RUST_LOG=info bento_cli -s -c 4096 || {
    echo ""
    echo "WARNING: bento_cli test exited with a non-zero status."
    echo "You may want to inspect logs or rerun manually."
    exit 1
  }
  echo ""
  echo "→ RiscZero multi-GPU test completed successfully."

  echo ""
  echo "===================================================================="
  echo "  Setup complete! You now have RiscZero multi-GPU support running.   "
  echo "===================================================================="
  exit 0
fi
