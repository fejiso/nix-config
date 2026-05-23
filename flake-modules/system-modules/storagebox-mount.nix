{ ... }: {
  flake.modules.nixos.storagebox-mount =
{ config, lib, pkgs, inputs, ... }:

with lib;

{
  options = {
    services.storagebox-mount = {
      enable = mkEnableOption "Hetzner Storage Box CIFS mount at /mnt/box";
    };
  };

  config = mkIf config.services.storagebox-mount.enable {
    sops.secrets.storagebox-username = {
      sopsFile = "${inputs.self}/secrets/storagebox.yaml";
      key = "username";
    };
    sops.secrets.storagebox-password = {
      sopsFile = "${inputs.self}/secrets/storagebox.yaml";
      key = "password";
    };
    sops.secrets.storagebox-share = {
      sopsFile = "${inputs.self}/secrets/storagebox.yaml";
      key = "share";
    };

    # Credentials file assembled from decrypted secrets
    sops.templates."storagebox-credentials".content = "username=${config.sops.placeholder.storagebox-username}\npassword=${config.sops.placeholder.storagebox-password}\n";
    sops.templates."storagebox-credentials".mode = "0600";

    environment.systemPackages = [ pkgs.cifs-utils ];

    systemd.tmpfiles.rules = [
      "d /mnt/box 0755 root root -"
    ];

    # Use a systemd mount service so device path comes from sops at runtime
    systemd.services.mount-storagebox = {
      description = "Mount Hetzner Storage Box";
      after = [ "network-online.target" "sops-nix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.cifs-utils pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        SHARE="$(cat ${config.sops.secrets.storagebox-share.path})"
        if mountpoint -q /mnt/box; then
          echo "/mnt/box already mounted"
        else
          mount -t cifs "$SHARE" /mnt/box \
            -o credentials=${config.sops.templates."storagebox-credentials".path},uid=0,gid=0,file_mode=0660,dir_mode=0770,_netdev,iocharset=utf8,vers=3.0
        fi
      '';
      preStop = ''
        umount /mnt/box || true
      '';
    };
  };
}
;
}
