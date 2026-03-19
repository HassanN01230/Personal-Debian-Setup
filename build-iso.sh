#!/usr/bin/env bash
#
# build-iso.sh — Repack a Debian netinst/DVD ISO with the preseed.cfg
# and setup.sh baked in, so the installer auto-loads the preseed on boot.
#
# Usage:
#   ./build-iso.sh debian-12.x.x-amd64-netinst.iso
#
# Output:
#   debian-autounattend.iso  (in current directory)
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-debian.iso>"
    echo "Example: $0 debian-12.9.0-amd64-netinst.iso"
    exit 1
fi

SOURCE_ISO="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRESEED="$SCRIPT_DIR/preseed.cfg"
SETUP_SH="$SCRIPT_DIR/setup.sh"
WORKDIR=$(mktemp -d)
OUTPUT_ISO="$SCRIPT_DIR/debian-autounattend.iso"

# Check and install dependencies
for pkg in xorriso isolinux; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "Installing missing dependency: $pkg"
        sudo apt install -y "$pkg"
    fi
done

if [[ ! -f "$PRESEED" ]]; then
    echo "Error: preseed.cfg not found at $PRESEED"
    exit 1
fi

if [[ ! -f "$SETUP_SH" ]]; then
    echo "Error: setup.sh not found at $SETUP_SH"
    exit 1
fi

echo "==> Extracting ISO to $WORKDIR/iso ..."
mkdir -p "$WORKDIR/iso"
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$WORKDIR/iso" 2>/dev/null
chmod -R u+w "$WORKDIR/iso"

echo "==> Copying preseed.cfg and setup.sh into ISO root ..."
cp "$PRESEED" "$WORKDIR/iso/preseed.cfg"
cp "$SETUP_SH" "$WORKDIR/iso/setup.sh"

echo "==> Patching GRUB boot config to auto-load preseed ..."
# For UEFI boot (grub.cfg)
GRUB_CFG="$WORKDIR/iso/boot/grub/grub.cfg"
if [[ -f "$GRUB_CFG" ]]; then
    # Add preseed to the default "Install" menu entry
    sed -i 's|--- quiet|--- quiet file=/cdrom/preseed.cfg auto=true priority=high|g' "$GRUB_CFG"
    echo "    Patched: $GRUB_CFG"
fi

# For legacy BIOS boot (isolinux/txt.cfg or isolinux/gtk.cfg)
for cfg in "$WORKDIR/iso/isolinux/txt.cfg" "$WORKDIR/iso/isolinux/gtk.cfg"; do
    if [[ -f "$cfg" ]]; then
        sed -i 's|--- quiet|--- quiet file=/cdrom/preseed.cfg auto=true priority=high|g' "$cfg"
        echo "    Patched: $cfg"
    fi
done

# Also patch the main isolinux.cfg timeout to auto-boot quickly
ISOLINUX_CFG="$WORKDIR/iso/isolinux/isolinux.cfg"
if [[ -f "$ISOLINUX_CFG" ]]; then
    # Set timeout to 3 seconds (30 = 3 sec in isolinux units of 1/10s)
    sed -i 's/^timeout .*/timeout 30/' "$ISOLINUX_CFG"
    echo "    Patched timeout: $ISOLINUX_CFG"
fi

echo "==> Rebuilding ISO ..."
# Detect if source ISO has EFI
EFI_IMG=""
if [[ -f "$WORKDIR/iso/boot/grub/efi.img" ]]; then
    EFI_IMG="$WORKDIR/iso/boot/grub/efi.img"
elif [[ -d "$WORKDIR/iso/EFI" ]]; then
    # Extract EFI image from original ISO
    EFI_IMG="$WORKDIR/efi.img"
    xorriso -indev "$SOURCE_ISO" -extract /boot/grub/efi.img "$EFI_IMG" 2>/dev/null || true
fi

if [[ -n "$EFI_IMG" && -f "$EFI_IMG" ]]; then
    # Hybrid BIOS + UEFI ISO
    xorriso -as mkisofs \
        -r -J \
        -V "Debian AutoUnattend" \
        -o "$OUTPUT_ISO" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$WORKDIR/iso"
else
    # BIOS-only ISO
    xorriso -as mkisofs \
        -r -J \
        -V "Debian AutoUnattend" \
        -o "$OUTPUT_ISO" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        "$WORKDIR/iso"
fi

echo "==> Cleaning up ..."
rm -rf "$WORKDIR"

echo ""
echo "Done! Output ISO: $OUTPUT_ISO"
echo ""
echo "Write it to a USB drive with:"
echo "  sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress && sync"
echo ""
echo "The installer will ask you:"
echo "  1. Language"
echo "  2. Location / Country"
echo "  3. Keyboard layout"
echo "  4. WiFi credentials (if no ethernet)"
echo "  5. Hostname"
echo "  6. Full name + username + password"
echo "  7. Disk partitioning (free space vs entire disk)"
echo "  8. Desktop environment (GNOME/KDE/Xfce/Cinnamon/MATE/LXDE/LXQt)"
echo ""
echo "Everything else is fully automated."
