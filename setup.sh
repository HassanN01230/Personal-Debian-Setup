#!/usr/bin/env bash
# Usage: bash setup.sh

# 0. Autologon and removing sudo password cuz im sick of typing it every 5 seconds (u will still have to type if resuming from sleep or somethin)
sudo mkdir -p /etc/sddm.conf.d
echo -e "[Autologin]\nUser=$USER\nSession=plasma" | sudo tee /etc/sddm.conf.d/autologin.conf  # Auto-login
echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd  # Passwordless sudo

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

wget https://github.com/jellyfin/jellyfin-desktop/releases/download/v1.12.0/jellyfin-media-player_1.12.0-trixie.deb  # Have to change to flatpak so no static url
sudo DEBIAN_FRONTEND=noninteractive apt install ./jellyfin-media-player_1.12.0-trixie.deb
sudo rm jellyfin-media-player_1.12.0-trixie.deb

wget -O discord.deb "https://discord.com/api/download?platform=linux&format=deb"
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./discord.deb
sudo rm discord.deb

wget -O vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./vscode.deb
sudo rm vscode.deb

CURSOR_VER=$(curl -s "https://api2.cursor.sh/updates/latest?platform=linux-x64-deb" | grep -oP '"version":"\K[^"]+')
wget -O cursor.deb "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/$CURSOR_VER"
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./cursor.deb
sudo rm cursor.deb

# 8. Nightlight settings
kwriteconfig6 --file kwinrc --group NightColor --key Active true
kwriteconfig6 --file kwinrc --group NightColor --key Mode Constant
kwriteconfig6 --file kwinrc --group NightColor --key NightTemperature 5300
qdbus6 org.kde.KWin /KWin reconfigure

sudo rm -- "$0" # delete this script file
sudo reboot