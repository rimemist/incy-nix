{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, unzip
, wrapGAppsHook3
, gobject-introspection
, python3
, gtk3
, libayatana-appindicator
, alsa-lib
, fontconfig
, freetype
, glibc
, libGL
, libx11
, libxext
, libxi
, libxrender
, libxtst
, libxcb
, libxau
, libxdmcp
, zlib
, iproute2
, iptables
, systemd
, coreutils
}:

let
  version = "3.9.1";

  sources = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-7E7ePptYSjhqD2LlncCGxQrjGsJmxgcEPNBVf/YC2Zc=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-3+A9VYNilvIyNazuny3CRqDAJrysVz8g7OBRaDVKfSA=";
    };
  };

  srcInfo = sources.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  pythonEnv = python3.withPackages (ps: [
    ps.pygobject3
  ]);

  helperPath = lib.makeBinPath [
    iproute2
    iptables
    systemd
    coreutils
    pythonEnv
  ];

in
stdenv.mkDerivation rec {
  pname = "incy";
  inherit version;

  src = fetchurl {
    url = "https://github.com/INCY-DEV/incy-platforms/releases/download/desktop-v${version}/incy-linux-${srcInfo.arch}-portable.zip";
    hash = srcInfo.hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    unzip
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    glibc
    libGL
    libx11
    libxext
    libxi
    libxrender
    libxtst
    libxcb
    libxau
    libxdmcp
    fontconfig
    freetype
    alsa-lib
    zlib
    gtk3
    libayatana-appindicator
    pythonEnv
  ];

  dontWrapGApps = true;
  dontStrip = true;

  sourceRoot = "incy";

  postPatch = ''
    # Remove config/.portable so INCY uses standard XDG paths (~/.config/incy, ~/.local/share/incy, ~/.cache/incy)
    # instead of trying to write to the read-only Nix store.
    rm -rf config

    # Patch incy-helper-linux.sh so it finds ip, iptables, resolvectl even if PATH is sanitized
    sed -i '2i export PATH="${helperPath}:\$PATH"' lib/app/resources/bin/incy-helper-linux.sh

    # Allow active users in PolKit without repeated password prompts
    sed -i 's|<allow_active>auth_admin_keep</allow_active>|<allow_active>yes</allow_active>|g' lib/app/resources/cc.incy.vpn.policy
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/incy
    cp -r bin lib $out/lib/incy/

    chmod +x $out/lib/incy/bin/incy
    chmod +x $out/lib/incy/lib/app/resources/bin/incy-worker
    chmod +x $out/lib/incy/lib/app/resources/bin/incy-helper-linux.sh

    # PolKit action file
    mkdir -p $out/share/polkit-1/actions
    cp $out/lib/incy/lib/app/resources/cc.incy.vpn.policy $out/share/polkit-1/actions/

    # Desktop entry & Icon
    mkdir -p $out/share/icons/hicolor/256x256/apps
    cp $out/lib/incy/lib/incy.png $out/share/icons/hicolor/256x256/apps/incy.png

    mkdir -p $out/share/applications
    cat > $out/share/applications/incy.desktop <<EOF
[Desktop Entry]
Name=INCY
Comment=Fast and private proxy/VPN client
Exec=incy %u
Icon=incy
Terminal=false
Type=Application
Categories=Network;VPN;
StartupWMClass=llc.itdev.incy.MainKt
MimeType=x-scheme-handler/incy;
EOF

    runHook postInstall
  '';

  postFixup = ''
    # Wrap the internal binary directly so that any invocation (including via
    # ProcessHandle.current().info().command() or custom desktop entries) is wrapped.
    mv $out/lib/incy/bin/incy $out/lib/incy/bin/.incy-unwrapped
    makeWrapper $out/lib/incy/bin/.incy-unwrapped $out/lib/incy/bin/incy \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${helperPath}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"

    mkdir -p $out/bin
    ln -sf $out/lib/incy/bin/incy $out/bin/incy
  '';

  meta = with lib; {
    description = "Fast and private proxy/VPN client";
    homepage = "https://incy.cc";
    license = licenses.unfree;
    maintainers = [ ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "incy";
  };
}
