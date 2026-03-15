#!/usr/bin/env bash
# Usage: bash debian-setup.sh

# 1. System Update
echo -e "Updating system packages"
sudo apt update && sudo apt upgrade -y

# 2. Firmware & Essentials
echo -e "Installing firmware and essentials"
sudo apt install -y firmware-linux firmware-amd-graphics

# 3. Enable Non-Free Repositories
echo -e "Enabling non-free repositories"
sudo sed -i 's/^deb \(.*\) main\(.*\)$/deb \1 main contrib non-free non-free-firmware\2/' /etc/apt/sources.list
sudo apt update

# 4. Fish Shell
echo -e "Installing Fish shell"
sudo apt install -y fish
sudo chsh -s /usr/bin/fish
echo -e "Fish is now your default shell. It takes effect on next login/restart."

# 5. AMD GPU / Vulkan
echo -e "Installing AMD GPU / Vulkan drivers"
sudo apt install -y mesa-vulkan-drivers libvulkan1 vulkan-tools mesa-utils

# 6. 32-bit libraries
echo -e "32-bit Vulkan libraries"
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y steam-installer
sudo apt install -y mesa-vulkan-drivers libglx-mesa0:i386 mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386

# 7. Installing Apps 
sudo apt install -y pipewire pipewire-audio pipewire-pulse wireplumber bluetooth bluez
sudo systemctl enable --now bluetooth
sudo apt install -y libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly ffmpeg
sudo apt install -y mpv vlc obs-studio unrar wget firefox-esr

sudo apt install -y git python3-pip python3-venv pipx build-essential gdb cmake
pipx ensurepath

curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable tailscaled

wget https://github.com/jellyfin/jellyfin-desktop/releases/download/v1.12.0/jellyfin-media-player_1.12.0-trixie.deb
sudo apt install ./jellyfin-media-player_1.12.0-trixie.deb
sudo rm jellyfin-media-player_1.12.0-trixie.deb

wget -O discord.deb "https://discord.com/api/download?platform=linux&format=deb"
sudo apt install -y ./discord.deb
sudo rm discord.deb

# # --- OnlyOffice ---------------------------------------------------------------
# echo -e "Installing OnlyOffice Desktop Editors"
# mkdir -p -m 700 ~/.gnupg
# gpg --no-default-keyring \
#     --keyring gnupg-ring:/tmp/onlyoffice.gpg \
#     --keyserver hkp://keyserver.ubuntu.com:80 \
#     --recv-keys CB2DE8E5
# chmod 644 /tmp/onlyoffice.gpg
# sudo chown root:root /tmp/onlyoffice.gpg
# sudo mv /tmp/onlyoffice.gpg /usr/share/keyrings/onlyoffice.gpg
# echo 'deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main' \
#   | sudo tee -a /etc/apt/sources.list.d/onlyoffice.list
# sudo apt update && sudo apt install -y onlyoffice-desktopeditors

# # --- Lutris -------------------------------------------------------------------
# echo -e "Installing Lutris"
# echo -e "Types: deb\nURIs: https://download.opensuse.org/repositories/home:/strycore/Debian_12/\nSuites: ./\nComponents: \nSigned-By: /etc/apt/keyrings/lutris.gpg" \
#   | sudo tee /etc/apt/sources.list.d/lutris.sources > /dev/null
# wget -q -O- https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key \
#   | sudo gpg --dearmor -o /etc/apt/keyrings/lutris.gpg
# sudo apt update && sudo apt install -y lutris

sudo rm -- "$0" # delete this script file
sudo reboot
# echo "Remaining:"
# echo "  - Reboot to apply shell change (Fish) and any kernel updates"
# echo "  - Multi-monitor layout: System Settings → Display and Monitor"
# echo "  - Git identity: git config --global user.name / user.email"
# echo "  - Tailscale auth: sudo tailscale up"