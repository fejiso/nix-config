{ inputs, ... }:
# polystack trading bot fleet module (2026-09).
#
# Dendritic layout, one config file: every host runs the section declared for
# it in `config/fleet.toml` (in the polystack repo — branch soaks carry their
# own copy). This module only imports the upstream NixOS module; host wiring
# lives in hosts/<name>/nixos/polystack.nix:
#
#   services.polystack.instances.main = {
#     mode = "trade";                  # or "observe" for leaves/soaks
#     configFile = "${inputs.polystack}/config/fleet.toml";
#     host = "<hostname>";             # the [hosts.<name>] section to run
#   };
#
# Branch soaks (different code than live): add a flake input pinned at the
# branch — polystack-soak.url = "git+ssh://…/fer/polystack.git?ref=<branch>" —
# and set the soak instance's `package` to its default package. Keep soak
# hosts on env = "sim" (fleet.toml) so the keyspace never collides with live.
{
  flake.modules.nixos.polystack = {
    imports = [ inputs.polystack.nixosModules.polystack ];
  };

  # zenoh router daemon — the fleet's inter-site transport hub (hierro).
  # Mesh-only: firewall opens the port on the netbird interface (wt0) only.
  # Leaves point fleet.toml `zenoh_routers` at tcp/<this-host>:<port>.
  flake.modules.nixos.polystack-zenohd =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.polystack-zenohd;
    in
    {
      options.services.polystack-zenohd = {
        enable = lib.mkEnableOption "zenoh router (polystack fleet hub)";
        port = lib.mkOption {
          type = lib.types.port;
          default = 7447;
          description = "zenoh TCP listen port (mesh interface only).";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.polystack-zenohd = {
          description = "zenoh router (polystack fleet hub)";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.zenoh}/bin/zenohd -l tcp/0.0.0.0:${toString cfg.port}";
            Restart = "always";
            RestartSec = 5;
            DynamicUser = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };
        # nats.nix pattern: mesh interface only.
        networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.port ];
      };
    };
}
