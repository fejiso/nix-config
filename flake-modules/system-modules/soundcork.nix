{ ... }: {
  flake.modules.nixos.soundcork =
# SoundCork — self-hosted replacement for the Bose SoundTouch cloud servers.
#
# Bose shut down the SoundTouch cloud on 2026-05-06, which breaks TuneIn
# presets, preset configuration and most of the SoundTouch app. SoundCork
# (https://github.com/timvw/soundcork) intercepts the four Bose cloud APIs and
# serves every response locally, so the speaker keeps working with no traffic
# leaving the LAN and no risk of unwanted firmware updates.
#
# This only runs the server. To actually "unlock" a speaker you point it at
# this instance once, manually (it is not a netbird peer, just a LAN device):
#   1. Enable SSH: format a USB stick FAT32, create an empty file named
#      `remote_services` (no extension), power the speaker off, insert the USB,
#      power on, wait ~60s. Then `ssh root@<speaker-ip>` (no password, fw 27.x).
#   2. Edit /opt/Bose/etc/SoundTouchSdkPrivateCfg.xml on the speaker, replacing
#      the Bose cloud server URLs with this instance's `baseUrl`.
#   3. The soundcork web UI (at baseUrl) lists discovered speakers and helps
#      extract presets/sources/device info (speaker local API is on :8090).
#
# Note this is orthogonal to services.boseSoundtouch (pa-dlna), which exposes
# the speaker as a local PipeWire sink for casting audio — soundcork instead
# keeps the speaker's own app/preset features alive. Both can run together.
{ config, lib, pkgs, quadlet-nix, ... }:

with lib;

let
  cfg = config.services.soundcork;
in {
  options.services.soundcork = {
    enable = mkEnableOption "SoundCork — local Bose SoundTouch cloud replacement";

    port = mkOption {
      type = types.port;
      default = 8005;
      description = ''
        Host TCP port published for SoundCork's web UI and intercept API
        (mapped to the container's fixed internal port 8000). Must be open and
        reachable from the speaker's LAN — unlike most services here it is not
        behind the netbird mesh, because the SoundTouch speaker is a plain LAN
        device. Defaults to 8005 (8000 is taken by restic-rest-server).
      '';
    };

    baseUrl = mkOption {
      type = types.str;
      default = "http://butthead:${toString cfg.port}";
      defaultText = literalExpression ''"http://butthead:''${toString cfg.port}"'';
      description = ''
        URL the speakers connect to — written verbatim into each speaker's
        SoundTouchSdkPrivateCfg.xml. It must resolve and be reachable from the
        speaker over the LAN, so prefer butthead's LAN IP (e.g.
        "http://192.168.1.x:8005") if mDNS/DHCP hostname resolution of
        "butthead" is unreliable on your network. Plain HTTP on the custom port
        is correct — soundcork does not use DNS interception or TLS.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/soundcork";
      description = "Directory holding SoundCork's persisted speaker data and config.";
    };
  };

  config = mkIf cfg.enable {
    # Dedicated system user for rootless podman (next free uid/gid after
    # openclaw 13108; subuid/subgid range after openclaw's 500000).
    users.users.soundcork = {
      isSystemUser = true;
      group = "soundcork";
      uid = 13109;
      home = cfg.dataDir;
      createHome = true;
      subUidRanges = [{ startUid = 600000; count = 65536; }];
      subGidRanges = [{ startGid = 600000; count = 65536; }];
    };
    users.groups.soundcork.gid = 13109;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 soundcork soundcork -"
      "d /run/user/13109 0700 soundcork soundcork -"
    ];

    # Rootless containers need a persistent login session for the user.
    systemd.services.enable-linger-soundcork = {
      description = "Enable lingering for soundcork user";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger soundcork";
      };
    };

    home-manager.users.soundcork = { pkgs, ... }: {
      imports = [ quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "25.05";
      home.enableNixpkgsReleaseCheck = false;
      home.homeDirectory = cfg.dataDir;
      home.username = "soundcork";

      virtualisation.quadlet.containers.soundcork = {
        autoStart = true;
        containerConfig = {
          image = "ghcr.io/timvw/soundcork:main";
          publishPorts = [ "${toString cfg.port}:8000" ];
          volumes = [
            "${cfg.dataDir}/data:/soundcork/data:rw"
          ];
          environments = {
            base_url = cfg.baseUrl;
            data_dir = "/soundcork/data";
          };
          autoUpdate = "registry";
          logDriver = "journald";
        };
        serviceConfig = {
          Restart = "always";
          RestartSec = "900";
        };
      };
    };

    # Reachable from the LAN (the speaker), not just the netbird mesh.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
;
}
