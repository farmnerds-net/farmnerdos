#!/usr/bin/env bash
# shellcheck disable=SC2034
# FarmNerdOS archiso profile definition (overlays releng)

iso_name="farmnerdos"
iso_label="FARMNERDOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="FarmNerdOS <https://github.com/farmnerds-net/farmnerdos>"
iso_application="FarmNerdOS Seedling Live/Installer"
iso_version="0.1-seedling"
install_dir="arch"          # keep default so mkinitcpio-archiso hooks Just Work
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.systemd-boot.esp' 'uefi-x64.systemd-boot.esp'
           'uefi-ia32.systemd-boot.eltorito' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd over xz: ~5x faster builds and faster live boot; ISO ~10% larger. Alpha
# iteration speed wins; revisit for stable releases.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/00-farmnerdos-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/local/bin/farmnerdos-install"]="0:0:755"
)
