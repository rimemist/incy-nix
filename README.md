# INCY on NixOS (Flake)

Nix Flake for running and seamlessly integrating the [INCY](https://github.com/INCY-DEV/incy-platforms) client on **NixOS** — a fast, modern, and cross-platform proxy/VPN client with support for VLESS (Reality / XTLS Vision), VMess, Trojan, Shadowsocks, Hysteria2, WireGuard, and AmneziaWG.

---

## 🚀 Quick Run Without Installation

Run the application directly using Nix Flakes:

```bash
# Locally from this repository directory:
nix run .

# Or directly from GitHub:
nix run github:rimemist/incy-nix
```

---

## 🛠️ NixOS Configuration Integration (Recommended)

For full TUN (VPN) mode and system routing, the client requires root privileges via Polkit to configure network interfaces (`ip`, `iptables`, `resolvectl`).

This flake includes a ready-to-use NixOS module that configures everything out of the box:
1. Installs the `incy` package with its desktop entry (`.desktop`) and application icons.
2. Loads the `tun` kernel module.
3. Automatically authorizes members of the `wheel` group in Polkit for the privileged helper script without repeated password prompts on connect, reconnect, or disconnect.
4. Provides fallback `NOPASSWD` sudo rules.
5. Sets up systemd tmpfiles symlinks for `/usr/lib/incy/incy-helper-linux.sh` and `/usr/share/polkit-1/actions/cc.incy.vpn.policy` to satisfy the application's internal file integrity checks.
6. Configures firewall settings for the `tun_incy` interface.

### 1. Add the flake input to your system `flake.nix`

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

> [!TIP]
> If your repository is private or you use SSH keys with GitHub, you can use `url = "git+ssh://git@github.com/rimemist/incy-nix.git";`.

### 2. Enable the module in `configuration.nix`

```nix
{ config, pkgs, ... }:

{
  programs.incy.enable = true;
}
```

### 3. Rebuild your system

```bash
sudo nixos-rebuild switch --flake .#your-hostname
```

---

## 📦 Standalone Package Usage (Without NixOS Module)

If you only want to install INCY as a user package (e.g. via Home Manager or directly in `environment.systemPackages` without system routing privileges):

### Via `environment.systemPackages`:
```nix
environment.systemPackages = [
  inputs.incy-nix.packages.${pkgs.system}.default
];
```

### Via Home Manager:
```nix
home.packages = [
  inputs.incy-nix.packages.${pkgs.system}.default
];
```

> [!NOTE]
> In standalone System Proxy mode (SOCKS5 / HTTP), INCY runs without root privileges. For full TUN (VPN) mode, the NixOS module (`programs.incy.enable = true;`) is required.

---

## 🔍 How It Works & NixOS Fixes

INCY Desktop is developed with Kotlin / Compose Multiplatform (Skiko) and bundled using `jpackage` alongside native Go/C binaries for Xray and VPN routing. On NixOS, several adaptations were made:

1. **Dynamic Linker & Shared Libraries (ELF Patching)**:
   - The upstream binaries (`bin/incy`, `incy-worker`, `libskiko-linux-x64.so`, `libincycore.so`, OpenJDK runtime) contain hardcoded paths to `/lib64/ld-linux-x86-64.so.2`, which does not exist on standard NixOS.
   - `autoPatchelfHook` automatically patches all binaries and shared objects to use Nixpkgs `glibc` and links graphical/audio libraries (`libGL`, `libX11`, `libXext`, `libXi`, `libXrender`, `libXtst`, `fontconfig`, `freetype`, `alsa-lib`, `libstdc++`).

2. **Read-Only Nix Store Compatibility (Portable vs XDG)**:
   - The portable distribution includes `config/.portable`. When present, INCY attempts to write its SQLite database (`incy.db`), routing configurations, and logs directly adjacent to the executable. In the read-only `/nix/store`, this causes permission errors.
   - The build process strips `config/`, causing INCY to gracefully fall back to standard XDG paths (`~/.config/incy`, `~/.local/share/incy`, `~/.cache/incy`).

3. **Privileged Helper & Zero Password Prompts**:
   - In TUN mode, INCY invokes `/usr/lib/incy/incy-helper-linux.sh` via `pkexec` multiple times (to clear stale killswitch rules, set up routes/DNS, and cleanup upon disconnection).
   - The helper script is patched to inject Nix store paths for `ip`, `iptables`, `resolvectl`, and `systemd` tools into its `PATH`.
   - The NixOS module installs Polkit rules authorizing users in the `wheel` group with `polkit.Result.YES`, removing password prompts.
   - `systemd.tmpfiles` maintains symlinks at `/usr/lib/incy/incy-helper-linux.sh` and `/usr/share/polkit-1/actions/cc.incy.vpn.policy`, satisfying INCY's internal file integrity checks.

---

## 🔄 Updating to New Upstream Releases

When a new version of INCY is released upstream:

### 1. Check for the new version tag
Check [INCY Releases](https://github.com/INCY-DEV/incy-platforms/releases) for the new version number (e.g., `3.9.2`).

### 2. Calculate the SRI hashes for the portable archives
Run the following commands to get the new SHA256 hashes:

```bash
# x86_64-linux:
nix store prefetch-file "https://github.com/INCY-DEV/incy-platforms/releases/download/desktop-v<VERSION>/incy-linux-x64-portable.zip"

# aarch64-linux:
nix store prefetch-file "https://github.com/INCY-DEV/incy-platforms/releases/download/desktop-v<VERSION>/incy-linux-arm64-portable.zip"
```

### 3. Update `package.nix`
Update `version` and the hashes in [package.nix](file:///home/yukifjord/Documents/incy-nix/package.nix):

```nix
  version = "<VERSION>";

  sources = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-...";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-...";
    };
  };
```

### 4. Test the build and push
```bash
nix build .#default
./result/bin/incy

# Commit and push to GitHub:
git commit -am "chore: bump version to <VERSION>"
git push origin main
```

### 5. Update your NixOS system
In your system configuration directory:

```bash
nix flake update incy-nix
sudo nixos-rebuild switch --flake .#your-hostname
```
