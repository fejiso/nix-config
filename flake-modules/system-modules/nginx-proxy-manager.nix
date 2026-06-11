{ ... }: {
  flake.modules.nixos.nginx-proxy-manager =
# Nginx Proxy Manager in a rootless podman container under a dedicated user.
# Extracted from hosts/butthead/nixos. Expects virtualisation.podman to be
# enabled by the host. Web UI on :8102, proxied HTTP/HTTPS on :8002/:44302.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.nginx-proxy-manager;
in
{
  options.services.nginx-proxy-manager = {
    enable = mkEnableOption "Nginx Proxy Manager (rootless podman)";
  };

  config = mkIf cfg.enable {
    # Dedicated user for nginx-proxy-manager
    users.users.nginx-proxy-manager = {
      isSystemUser = true;
      group = "nginx-proxy-manager";
      uid = 13200;
      home = "/var/lib/nginx-proxy-manager";
      createHome = true;
      subUidRanges = [{ startUid = 100000; count = 65536; }];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
    };
    users.groups.nginx-proxy-manager = {
      gid = 13200;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/nginx-proxy-manager 0755 nginx-proxy-manager nginx-proxy-manager -"
      "d /var/lib/npm-storage 0755 100000 100000 -"
      "Z /var/lib/npm-storage/data 0755 100000 100000 -"
      "Z /var/lib/npm-storage/letsencrypt 0755 100000 100000 -"
      "d /run/user/13200 0700 nginx-proxy-manager nginx-proxy-manager -"
    ];

    # Nginx Proxy Manager container (still using systemd service for rootless)
    systemd.services.nginx-proxy-manager = {
      description = "Nginx Proxy Manager";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.podman pkgs.slirp4netns ];

      unitConfig = {
        StartLimitIntervalSec = 0;
      };

      serviceConfig = {
        Restart = "always";
        RestartSec = "15min";
        Type = "simple";
        User = "nginx-proxy-manager";
        Group = "nginx-proxy-manager";
        TimeoutStartSec = "5min";

        Environment = [
          "HOME=/var/lib/nginx-proxy-manager"
          "XDG_RUNTIME_DIR=/run/user/13200"
          "PATH=${pkgs.slirp4netns}/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        ];

        ExecStartPre = [
          "-${pkgs.podman}/bin/podman rm -f nginx-proxy-manager"
          "${pkgs.podman}/bin/podman pull docker.io/jc21/nginx-proxy-manager:latest"
        ];

        ExecStart = "${pkgs.bash}/bin/bash -c 'set -x; ${pkgs.podman}/bin/podman run --rm --name nginx-proxy-manager --label io.containers.autoupdate=registry --log-driver=journald --memory=1G --network=slirp4netns:allow_host_loopback=true -p 8102:81 -p 8002:80 -p 44302:443 -v /var/lib/npm-storage/data:/data:rw -v /var/lib/npm-storage/letsencrypt:/etc/letsencrypt:rw -e DB_SQLITE_FILE=/data/database.sqlite docker.io/jc21/nginx-proxy-manager:latest'";

        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 nginx-proxy-manager";
      };
    };

    # Enable lingering for nginx-proxy-manager user
    systemd.services.enable-linger-nginx-proxy-manager = {
      description = "Enable lingering for nginx-proxy-manager user";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger nginx-proxy-manager";
      };
    };
  };
}
;
}
