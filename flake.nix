{
  description = "INCY - Fast and private proxy/VPN client for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.callPackage ./package.nix { };
          incy = self.packages.${system}.default;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/incy";
        };
        incy = self.apps.${system}.default;
      });

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.incy;
        in
        {
          options.programs.incy = {
            enable = lib.mkEnableOption "INCY VPN / Proxy Client";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The INCY package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            # Enable PolKit
            security.polkit.enable = true;

            # Automatically authorize members of group wheel to run incy-helper without password prompts
            security.polkit.extraConfig = ''
              polkit.addRule(function(action, subject) {
                var prog = action.lookup("program");
                var cmd = action.lookup("command_line");
                if (
                  (action.id === "cc.incy.vpn.run-helper" ||
                   (action.id === "org.freedesktop.policykit.exec" &&
                    ((prog && (prog === "/usr/lib/incy/incy-helper-linux.sh" || prog.indexOf("incy-helper-linux.sh") >= 0)) ||
                     (cmd && cmd.indexOf("incy-helper-linux.sh") >= 0)))) &&
                  subject.isInGroup("wheel")
                ) {
                  return polkit.Result.YES;
                }
              });
            '';

            # Passwordless sudo fallback if invoked via sudo
            security.sudo.extraRules = [
              {
                groups = [ "wheel" ];
                commands = [
                  {
                    command = "/usr/lib/incy/incy-helper-linux.sh";
                    options = [ "NOPASSWD" ];
                  }
                  {
                    command = "${cfg.package}/lib/incy/lib/app/resources/bin/incy-helper-linux.sh";
                    options = [ "NOPASSWD" ];
                  }
                ];
              }
            ];

            # Install incy package into system packages (including .desktop file and polkit action)
            environment.systemPackages = [ cfg.package ];

            # Ensure TUN network device is available and traffic is not dropped
            boot.kernelModules = [ "tun" ];
            networking.firewall.trustedInterfaces = [ "tun_incy" ];
            networking.firewall.checkReversePath = "loose";

            # Provide the privileged helper script at /usr/lib/incy/incy-helper-linux.sh,
            # polkit policy at /usr/share/polkit-1/actions/cc.incy.vpn.policy,
            # and binary symlink at /usr/bin/incy (for MIME handler and autostart registration)
            systemd.tmpfiles.rules = [
              "d /usr/lib/incy 0755 root root -"
              "L+ /usr/lib/incy/incy-helper-linux.sh - - - - ${cfg.package}/lib/incy/lib/app/resources/bin/incy-helper-linux.sh"
              "d /usr/share/polkit-1/actions 0755 root root -"
              "L+ /usr/share/polkit-1/actions/cc.incy.vpn.policy - - - - ${cfg.package}/lib/incy/lib/app/resources/cc.incy.vpn.policy"
              "L+ /usr/bin/incy - - - - ${cfg.package}/bin/incy"
            ];
          };
        };

      nixosModules.incy = self.nixosModules.default;
    };
}
