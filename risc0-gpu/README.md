# Setting up RISC0 multi GPU

 1. Spin up your AWS Ubuntu 22.04 instance (with ≥100 GB root volume, multi‐GPU type).
 2. SSH in as the ubuntu user.
 3. Upload all three scripts (01-sudo-setup.sh, 02-user-setup.sh, 03-post-reboot.sh) into ~/scripts/ (or wherever you prefer).
 4. Make them executable:

 ```bash
 chmod +x 01-sudo-setup.sh 02-user-setup.sh 03-post-reboot.sh
 ```
