flakeArgs: {
  flake.modules.nixos.tdarr-worker =
# Tdarr distributed transcoding — native NixOS services (services.tdarr from
# nixpkgs), replacing the previous rootless-podman/quadlet deployment.
#
# Config/permissions/directories are kept identical to the container setup:
#   - runs as media-podman:media-services (so existing /var/lib/tdarr data,
#     created by the rootless containers, stays owned correctly)
#   - server data dir /var/lib/tdarr (local per host — "local config")
#   - media + transcode cache live on the shared NFS mounts at paths that are
#     IDENTICAL on the server and every node (required for "mapped" nodes).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tdarr-worker;
  mediaPaths = attrValues cfg.mediaDirectories;
  rwPaths = mediaPaths ++ [ cfg.transcodeCache ];
  nodeUnit = "tdarr-node-${cfg.nodeId}";
  
  # Extract mount point from a path (e.g., /mnt/downloadtemp/tdarr-cache -> /mnt/downloadtemp)
  getMountPoint = path:
    let
      parts = lib.strings.splitString "/" (lib.strings.removePrefix "/" path);
      # Take first two components: mnt/<name>
      mountPath = "/" + (lib.concatStringsSep "/" (lib.take 2 parts));
    in
      mountPath;
  
  mountPoints = lib.unique (map getMountPoint rwPaths);

  # DRX-Lab hdr10plus_tool-av1 (vendored next to this file): inject/extract
  # HDR10+ dynamic metadata in AV1 (IVF) files. Used by Tdarr flows to keep
  # native HDR10+ when re-encoding to AV1.
  hdr10plusToolAv1 = pkgs.runCommand "hdr10plus_tool_av1"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      mkdir -p $out/bin
      cp ${./hdr10plus_tool_av1.py} $out/bin/hdr10plus_tool_av1
      chmod +x $out/bin/hdr10plus_tool_av1
      patchShebangs $out/bin/hdr10plus_tool_av1
    '';
  hasAutomount = path:
    lib.any (option: option == "x-systemd.automount")
      (lib.attrByPath [ path "options" ] [ ] config.fileSystems);
  automountUnits = map (p: builtins.replaceStrings ["/"] ["-"] (lib.strings.removePrefix "/" p) + ".automount") (lib.filter hasAutomount mountPoints);
in
{
  imports = [
    flakeArgs.config.flake.modules.nixos.media-podman
  ];

  options.services.tdarr-worker = {
    enable = mkEnableOption "Tdarr worker node (native NixOS service)";

    serverEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Also run the Tdarr server on this host";
    };

    nodeId = mkOption {
      type = types.str;
      default = "${config.networking.hostName}_worker";
      description = "Node ID / display name";
    };

    serverIP = mkOption {
      type = types.str;
      default = "butthead.netbird.cloud";
      description = "Tdarr server address (used when serverEnabled = false)";
    };

    serverPort = mkOption {
      type = types.port;
      default = 8266;
      description = "Tdarr server API port";
    };

    webUIPort = mkOption {
      type = types.port;
      default = 8265;
      description = "Tdarr web UI port (server only)";
    };

    mediaDirectories = mkOption {
      type = types.attrsOf types.str;
      default = {
        tv = "/mnt/Series";
        movies = "/mnt/Movies";
      };
      description = ''
        Media directories the server/node must read and write. Paths MUST be
        identical across the server and every node (Tdarr "mapped" nodes look
        files up by the exact library path stored on the server). They are
        provided here by the shared NFS mounts.
      '';
    };

    transcodeCache = mkOption {
      type = types.str;
      default = "/mnt/downloadtemp/tdarr-cache";
      description = "Shared transcode cache directory (identical path on all nodes)";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = (with pkgs; [ dovi-tool hdr10plus_tool mkvtoolnix-cli ]) ++ [ hdr10plusToolAv1 ];
      defaultText = literalExpression "(with pkgs; [ dovi-tool hdr10plus_tool mkvtoolnix-cli ]) ++ [ hdr10plusToolAv1 ]";
      description = ''
        Extra packages placed on the Tdarr server/node PATH, for plugins and
        flows that shell out to external tools — e.g. Dolby Vision / HDR10+
        handling (dovi_tool, hdr10plus_tool, hdr10plus_tool_av1) and remuxing
        (mkvextract/mkvmerge). The bundled container images shipped these;
        native installs do not, so provide them here. ffmpeg is bundled with
        Tdarr itself.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "media-podman";
      description = "User to run Tdarr as";
    };

    group = mkOption {
      type = types.str;
      default = "media-services";
      description = "Group to run Tdarr as";
    };
  };

  config = mkIf cfg.enable {
    services.tdarr = {
      user = cfg.user;
      group = cfg.group;
      dataDir = "/var/lib/tdarr";

      server = {
        enable = cfg.serverEnabled;
        serverIP = "0.0.0.0";
        serverPort = cfg.serverPort;
        webUIPort = cfg.webUIPort;
        # Firewalling is handled below (netbird interface only).
        openFirewall = false;
      };

      nodes.${cfg.nodeId} = {
        name = cfg.nodeId;
        type = "mapped";
        serverURL =
          if cfg.serverEnabled
          then "http://127.0.0.1:${toString cfg.serverPort}"
          else "http://${cfg.serverIP}:${toString cfg.serverPort}";
      };
    };

    # Shared transcode cache. Match the permissive mode the container used so
    # the server and every node can write transcoded output here.
    systemd.tmpfiles.rules = [
      "d ${cfg.transcodeCache} 0777 ${cfg.user} ${cfg.group} -"
    ];

    # The upstream units harden with ProtectSystem=strict and only allow writes
    # to their own data dir. Grant write access to the media + cache paths, GPU
    # access for hardware transcoding, and order the units after the NFS mounts.
    # Note: We only depend on actual mount points, not subdirectories within mounts.
    systemd.services = mkMerge [
      (mkIf cfg.serverEnabled {
        tdarr-server = {
          path = cfg.extraPackages;
          unitConfig = {
            RequiresMountsFor = rwPaths;
            After = automountUnits;
            Wants = automountUnits;
          };
          serviceConfig = {
            ReadWritePaths = mkAfter rwPaths;
            SupplementaryGroups = [ "render" "video" ];
          };
        };
      })
      {
        ${nodeUnit} = {
          path = cfg.extraPackages;
          unitConfig = {
            RequiresMountsFor = rwPaths;
            After = automountUnits;
            Wants = automountUnits;
          };
          serviceConfig = {
            ReadWritePaths = mkAfter rwPaths;
            SupplementaryGroups = [ "render" "video" ];
          };
        };
      }
    ];

    # Tdarr server/web traffic is between netbird peers only.
    networking.firewall.interfaces.wt0.allowedTCPPorts =
      mkIf cfg.serverEnabled [ cfg.webUIPort cfg.serverPort ];
  };
}
;
}
