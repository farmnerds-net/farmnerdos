# FarmNerdOS

**Alpha — Seedling v0.1**

An Arch Linux–based distribution for farm nerds. Dark mode, circuit-green accents,
and the [CachyOS](https://cachyos.org) performance kernel by default.

![wallpaper](packages/farmnerdos-wallpapers/farmnerdos-seedling.png)

## What's in this repo

| Path | Purpose |
|---|---|
| `iso/` | archiso profile **overlay** (applied on top of the stock `releng` profile) |
| `packages/` | PKGBUILDs for FarmNerdOS's own packages (branding, theme, installer config) |
| `scripts/` | Build tooling: package repo builder + ISO builder |
| `repo/` | Output: the `[farmnerdos]` pacman repository (generated, gitignored) |
| `.github/workflows/` | CI: build packages → publish repo → build ISO release |

## Design decisions (v0.1)

- **Base:** stock Arch (`archlinux-2026.07.01` verified as reference), built with `archiso`.
- **Kernel:** `linux-cachyos` from the official CachyOS repository (BORE scheduler,
  x86-64-v3 optimizations available). We do *not* mirror it; it stays current upstream.
- **Desktop:** KDE Plasma (Wayland), Breeze Dark base with the *FarmNerd Seedling*
  color scheme — near-black soil tones with circuit-green accents pulled from the wallpaper.
- **Installer:** Calamares, branded. Live session autologs into user `farmer`.
- **Few extra apps:** Firefox, Konsole, Dolphin, Ark, Spectacle, Kate. That's it for alpha.

## Theme palette (from the wallpaper)

| Role | Hex |
|---|---|
| Background (soil black) | `#0C120C` |
| Surface (dark moss) | `#141C14` |
| Accent (circuit green) | `#5CDB3C` |
| Accent bright (glow) | `#8AFF3A` |
| Highlight (sunset amber) | `#F0A32E` |
| Text | `#DCE8D8` |

## Building

Requires an up-to-date **Arch Linux** build host (or the CI workflow) with:
`archiso`, `base-devel`, `git`.

```sh
# 1. One-time: trust the CachyOS signing key on the build host
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key F3B607488DB35A47

# 2. Build FarmNerdOS packages into ./repo (local [farmnerdos] pacman repo)
./scripts/build-packages.sh

# 3. Build the ISO (root required; uses mkarchiso)
sudo ./scripts/build-iso.sh
# → out/farmnerdos-0.1-seedling-x86_64.iso
```

## Repositories used by the OS

```ini
[farmnerdos]   # our packages — GitHub Pages once published, file:// during local builds
[cachyos]      # kernel + calamares, https://mirror.cachyos.org/repo/$arch/$repo
[core] [extra] # stock Arch
```

## Roadmap

- v0.1 *Seedling* (this): bootable live ISO, branded Calamares, theme, CachyOS kernel
- v0.2: signed `[farmnerdos]` repo, custom SDDM theme, farm-tool app selection
- v0.3: hardware profiles (RTK GPS dongles, CAN interfaces), OTA update channel

## License

Build scripts and configs: MIT. Wallpaper and branding artwork: CC BY-SA 4.0.
Packages retain their upstream licenses.
