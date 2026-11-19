# INCY on NixOS

[![Nix Flake](https://img.shields.io/badge/Nix-Flake-blue.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Platform](https://img.shields.io/badge/Platform-x86__64--linux%20%7C%20aarch64--linux-lightgrey.svg)](https://github.com/rimemist/incy-nix)
[![License: Unfree](https://img.shields.io/badge/License-Unfree-orange.svg)](https://incy.cc)

A ready-to-use **Nix Flake** for running and integrating the [INCY](https://github.com/INCY-DEV/incy-platforms) desktop client on **NixOS**.

INCY is a fast, modern, and versatile proxy/VPN desktop client with native support for **VLESS** (Reality / XTLS Vision), **VMess**, **Trojan**, **Shadowsocks**, **Hysteria2**, **WireGuard**, and **AmneziaWG**.

---

## ✨ Features

- **Zero-Friction TUN Mode**: No password spam! Connect, reconnect, and disconnect without repeated sudo/polkit authorization dialogs.
- **Native System Tray Integration**: Full support for system tray / StatusNotifierItem on Wayland and X11 (KDE Plasma, GNOME, etc.) via Ayatana AppIndicator, enabling *Minimize to Tray* and *Hide to Tray*.
- **XDG-Compliant**: Gracefully stores databases and configurations in standard user directories (`~/.config/incy`, `~/.local/share/incy`, `~/.cache/incy`) rather than attempting to write to the read-only Nix store.
- **Desktop Ready**: Automatically provides high-resolution application icons, MIME protocol handlers (`incy://`), and desktop menu entries.
- **Multi-Architecture**: Supports both `x86_64-linux` and `aarch64-linux`.

---

## 🚀 Quick Run (Ad-hoc)

Launch INCY directly from GitHub without modifying your system configuration:

```bash
nix run github:rimemist/incy-nix
```

---

## 🛠️ NixOS Installation (Recommended)

To use TUN (VPN) mode and system-wide routing, INCY requires root privileges to manage network interfaces (`tun_incy`, `ip`, `iptables`, `resolvectl`). 

The provided NixOS module configures all required system services, kernel modules, firewall rules, and Polkit permissions automatically.

### 1. Add `incy-nix` to your system `flake.nix`

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    incy-nix = {
      url = "github:rimemist/incy-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, incy-nix, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        incy-nix.nixosModules.default
      ];
    };
  };
}
```

### 2. Enable INCY in `configuration.nix`

```nix
{ config, pkgs, ... }:

{
  programs.incy.enable = true;
}
```

### 3. Apply your configuration

```bash
sudo nixos-rebuild switch --flake .#your-hostname
```

---

## 📦 Standalone Package (Home Manager / Non-Root)

If you only use proxy mode (SOCKS5 / HTTP) or prefer managing user packages through Home Manager without system routing services:

```nix
# home.nix
{ pkgs, inputs, ... }:

{
  home.packages = [
    inputs.incy-nix.packages.${pkgs.system}.default
  ];
}
```

---

## 🔄 Updating INCY

Whenever a new version or fix is pushed to this repository, update your system lock file and rebuild:

```bash
# Update the flake input
nix flake update incy-nix

# Rebuild your NixOS system
sudo nixos-rebuild switch --flake .#your-hostname
```

---

## ⚠️ Coexistence with Zapret (DPI Bypass Tools)

If you are running **Zapret** (such as `zapret-discord-youtube`, Flowseal's zapret, or standalone `nfqws` / `tpws`), you might experience connection issues or certificate validation errors in INCY:

### Why Does This Happen?
Zapret uses Linux `iptables` / `nftables` with `NFQUEUE` to intercept and fragment TCP/TLS packets on ports 80 and 443 (e.g. injecting fake SNI or splitting TLS ClientHello). When INCY connects over encrypted protocols (such as VLESS, Trojan, or Hysteria2) or establishes a system-wide TUN tunnel, Zapret's packet mangling rules can inadvertently corrupt INCY's outbound TLS handshakes. This leads to:
- `Certificate verification failed` or SSL handshake errors.
- Inability to establish or maintain the VPN/proxy connection.

### Built-in Detection & Warning
This package comes with an automatic, lightweight startup check:
- If Zapret (`nfqws`, `tpws`, or `zapret` services) is actively running when INCY starts, a desktop warning dialog appears advising you of potential conflicts.
- The check runs asynchronously in the background and will never block or delay the startup of INCY.
- To prevent spam, the warning features a 30-minute cooldown period per session.

### Recommended Workaround
If you encounter errors when connecting INCY, temporarily stop the Zapret service:

```bash
# For zapret-discord-youtube:
sudo systemctl stop zapret-discord-youtube

# Or use your shell alias if configured:
stopz
```

Once INCY is connected in TUN mode, all your traffic is securely routed through the tunnel, making Zapret redundant while INCY is active.

---

## 🔧 Technical Highlights (Under the Hood)

- **Patched Dynamic Linker & Libraries**: All binaries and shared libraries (`libskiko`, `libincycore`, `libxray_ffi`, OpenJDK) are automatically patched with `autoPatchelfHook` against Nixpkgs libraries (`glibc`, `libGL`, `libX11`, `freetype`, `alsa-lib`, etc.).
- **AppIndicator Tray Bridge**: Wrapped with GObject Introspection (`wrapGAppsHook3`), GTK 3, and Python bindings (`libayatana-appindicator`, `pygobject3`), allowing the tray helper script to register a D-Bus `StatusNotifierItem` across modern Wayland and X11 compositors.
- **Polkit Automation**: Deploys a dedicated Polkit JavaScript rule authorizing users in the `wheel` group with `polkit.Result.YES` for INCY's privileged helper script, preventing authentication popups on connect and disconnect.
- **Routing & DNS**: Injects Nix store paths (`iproute2`, `iptables`, `systemd`) directly into `incy-helper-linux.sh` and ensures the `tun` kernel module is loaded with loose reverse-path filtering.
