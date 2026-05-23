{ ... }: {
  flake.modules.nixos.network-watchdog =
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.network-watchdog;
in
{
  options.services.network-watchdog = {
    enable = mkEnableOption "network watchdog that reboots after prolonged outage";

    pingTarget = mkOption {
      type = types.str;
      default = "1.1.1.1";
      description = "Host to ping for connectivity check";
    };

    downtime = mkOption {
      type = types.int;
      default = 3600;
      description = "Seconds of continuous network failure before rebooting";
    };

    interval = mkOption {
      type = types.str;
      default = "*:0/5";
      description = "Systemd calendar expression for check interval";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.network-watchdog = {
      description = "Network watchdog - reboot on prolonged outage";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "network-watchdog" ''
          STAMP=/run/network-watchdog-down-since
          if ${pkgs.iputils}/bin/ping -c1 -W5 ${cfg.pingTarget} >/dev/null 2>&1; then
            rm -f "$STAMP"
            exit 0
          fi
          if [ ! -f "$STAMP" ]; then
            date +%s > "$STAMP"
            echo "Network down, started tracking"
            exit 0
          fi
          DOWN_SINCE=$(cat "$STAMP")
          NOW=$(date +%s)
          ELAPSED=$(( NOW - DOWN_SINCE ))
          echo "Network down for ''${ELAPSED}s (threshold: ${toString cfg.downtime}s)"
          if [ "$ELAPSED" -ge ${toString cfg.downtime} ]; then
            echo "Rebooting due to network outage"
            rm -f "$STAMP"
            systemctl reboot
          fi
        '';
      };
    };

    systemd.timers.network-watchdog = {
      description = "Network watchdog timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };
}
;
}
