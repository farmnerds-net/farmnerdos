# Building and testing FarmNerdOS on Proxmox VE

Tailored for **farmlab** (PVE 9.2.3, host `10.30.2.2`, ISO storage `iso-storage`).
The stock `archlinux-2026.07.01-x86_64.iso` is already uploaded there.

> The `farmnerdos-2026.07.12-x86_64.iso` already on iso-storage predates the
> security review — installed systems from it recreate a passwordless-sudo
> `farmer` user at every boot. Rebuild before installing anywhere real, then
> `Remove` the old ISO in the UI.

## Automatic mode (recommended) — one command

From this PC (PowerShell, in `Downloads\claude-project`):

```powershell
scp -r .\farmnerdos root@10.30.2.2:/root/
```

On the PVE host (`ssh root@10.30.2.2`):

```sh
chmod +x /root/farmnerdos/scripts/proxmox/*.sh
DISK_STORAGE=bigdisk_storage /root/farmnerdos/scripts/proxmox/auto-build.sh
```

(Swap `bigdisk_storage` if your VM disks live elsewhere — the script validates
the name against `pvesm status` and lists options if wrong. `iso-storage` is
already the default ISO storage in all scripts.)

The orchestrator, with zero console interaction (~20–40 min):

1. extracts kernel/initrd from the stock Arch ISO for direct kernel boot
2. serves the repo + build payload over HTTP from the PVE host (port 8199)
3. boots build VM **9001**; the live env auto-runs the payload via the
   `script=` kernel parameter — scratch disk, packages, `mkarchiso`
4. receives `farmnerdos-0.1-seedling-x86_64.iso` back over HTTP, verifies
   sha256, installs it to `iso-storage`
5. destroys VM 9001 and boots FarmNerdOS in test VM **9000** (UEFI, virtio,
   guest agent, Secure Boot keys absent — required for the unsigned kernel)

Your existing VMs 100/101 are untouched (scripts refuse existing VMIDs).

Requirements: DHCP on `vmbr0`, VM→host traffic allowed on port 8199.
On failure: build VM stays up for console inspection, log tail printed.
Useful flags: `SKIP_TEST_VM=1` (stop after ISO lands), `TIMEOUT_MIN`,
`BUILD_VMID`/`TEST_VMID`, `BRIDGE`, `HOST_IP` (multi-homed hosts).

## Manual mode (fallback)

```sh
DISK_STORAGE=bigdisk_storage ./create-build-vm.sh      # VM 9001, boots stock ISO
```

Open VM 9001's console at the root prompt:

```sh
passwd && ip -4 addr show                              # enable SSH, note IP
```

From this PC: `scp -r .\farmnerdos root@<build-vm-ip>:/root/`, then in the VM:

```sh
bash /root/farmnerdos/scripts/proxmox/bootstrap-build.sh
```

It prints the scp command that pushes the finished ISO to iso-storage. Then:

```sh
DISK_STORAGE=bigdisk_storage ./create-test-vm.sh       # VM 9000 boots newest ISO
qm stop 9001 && qm destroy 9001 --purge                # build VM is disposable
```

## First-boot checklist (test VM)

| Check | Expect |
|---|---|
| SDDM → autologin | user `farmer`, Plasma Wayland |
| Theme | dark + green (FarmNerd Seedling), wallpaper set |
| `uname -r` | ends in `-cachyos` |
| Desktop icon | "Install FarmNerdOS" launches Calamares |
| `qm agent 9000 ping` (from PVE) | responds (guest agent shipped) |
| After Calamares install + reboot | no `farmer` user, no autologin, sddm + NetworkManager enabled |

Test `FIRMWARE=bios` on a second test VM before calling the alpha done —
that exercises the syslinux boot path. Snapshot before installing so you can
retest repeatedly: `qm snapshot 9000 pre-install`.

## Notes

- Scripts use `qm`/`pvesm` on the host (homelab-appropriate). For remote
  automation later, use the REST API with a privilege-separated token, not
  root@pam.
- Build VM RAM: 12G default; below 8G expect mkarchiso failures.
- `create-test-vm.sh` auto-picks the **newest** farmnerdos ISO by file mtime;
  pass `FARM_ISO=<name>` to pin one explicitly.
