#!/usr/bin/env bash
# Usage: bash setup.sh

# 0. Autologon and removing sudo password cuz im sick of typing it every 5 seconds (u will still have to type if resuming from sleep or somethin)
sudo mkdir -p /etc/sddm.conf.d
echo -e "[Autologin]\nUser=$USER\nSession=plasma" | sudo tee /etc/sddm.conf.d/autologin.conf  # Auto-login
echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd  # Passwordless sudo

# 1. System Update
echo -e "Updating system packages"
sudo apt update 
sudo apt install -y ntpsec-ntpdate
sudo ntpdate pool.ntp.org
sudo apt update 
sudo apt upgrade -y

# 2. Firmware & Essentials
echo -e "Installing firmware and essentials"
sudo apt install -y firmware-linux firmware-amd-graphics

# 3. Enable Non-Free Repositories, hardcoded so no issue even if script ran multiple times
echo -e "Enabling non-free repositories"
sudo tee /etc/apt/sources.list > /dev/null << 'EOF'
#deb cdrom:[Debian GNU/Linux 13.4.0 _Trixie_ - Official amd64 NETINST with firmware 20260314-11:53]/ trixie contrib main non-free-firmware
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

# trixie-updates, to get updates before a point release is made;
# see https://www.debian.org/doc/manuals/debian-reference/ch02.en.html#_updates_and_backports
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF
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
sudo apt install -y mpv vlc obs-studio unrar curl wget firefox-esr cifs-utils

sudo apt install -y git python3-pip python3-venv pipx build-essential gdb cmake
pipx ensurepath

curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable tailscaled

wget -O jellyfin_client.deb https://github.com/jellyfin/jellyfin-desktop/releases/download/v1.12.0/jellyfin-media-player_1.12.0-trixie.deb  # Have to change to flatpak so no static url
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./jellyfin_client.deb
sudo rm jellyfin_client.deb

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

# HEROIC_DEB_URL=$(curl -s "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" | grep -oP '"browser_download_url":"\K[^"]+linux-amd64\.deb')
# wget -O heroic.deb "$HEROIC_DEB_URL"
wget -O heroic.deb "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.20.1/Heroic-2.20.1-linux-amd64.deb"
sudo DEBIAN_FRONTEND=noninteractive apt install -y ./heroic.deb
sudo rm heroic.deb

# 8. Nightlight settings
kwriteconfig6 --file kwinrc --group NightColor --key Active true
kwriteconfig6 --file kwinrc --group NightColor --key Mode Constant
kwriteconfig6 --file kwinrc --group NightColor --key NightTemperature 5300
qdbus6 org.kde.KWin /KWin reconfigure

sudo rm -- "$0" # delete this script file
sudo reboot