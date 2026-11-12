{ lib, ... }:
let
  mkOwlshackPkg = pkgs:
    let
      version = "1.6.1";
      assets = {
        x86_64-linux = {
          name = "OwlShack-linux-amd64";
          hash = "sha256-XwsTJkdLoFiFg9FNt3ayjX+SlkUmrmVYNph/2Fp8Jss=";
        };
        aarch64-linux = {
          name = "OwlShack-linux-arm64";
          hash = "sha256-HGoNgE6bCkcVhXRV7OYIg+Gbp+4+rd+1W9HJ8trbGDE=";
        };
      };
      asset = assets.${pkgs.stdenv.hostPlatform.system}
        or (throw "Unsupported platform for OwlShack: ${pkgs.stdenv.hostPlatform.system}");
      src = pkgs.fetchurl {
        url = "https://github.com/OwlShack/OwlShack/releases/download/v${version}/${asset.name}";
        inherit (asset) hash;
      };
    in
    pkgs.runCommand "owlshack-${version}" { } ''
      mkdir -p $out/bin
      cp ${src} $out/bin/owlshack
      chmod 0755 $out/bin/owlshack
    '';

  mkOwlstackBridgePkg = pkgs:
    pkgs.buildGoModule {
      pname = "owlstack-bridge";
      version = "0.1.0";
      src = ../../pkgs/owlstack-bridge;
      vendorHash = "sha256-hAHXPwWzTSTeu8IeX5HRtLvUNOlDQzXiYcf/GiYJBJw=";
    };
in
{
  perSystem = { pkgs, ... }: {
    packages = lib.optionalAttrs pkgs.stdenv.isLinux ({
      owlstack-bridge = mkOwlstackBridgePkg pkgs;
    } // lib.optionalAttrs (builtins.elem pkgs.stdenv.hostPlatform.system [ "x86_64-linux" "aarch64-linux" ]) {
      owlshack = mkOwlshackPkg pkgs;
    });
  };

  flake.modules.nixos.owlstack =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.owlstack;
      owlshackPkg = mkOwlshackPkg pkgs;
      bridgePkg = mkOwlstackBridgePkg pkgs;

      companionType = lib.types.either lib.types.str (lib.types.submodule {
        options = {
          pubKey = lib.mkOption {
            type = lib.types.str;
            description = "Hex Ed25519 public key (64 hex chars, or non-empty hex prefix).";
          };
          name = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional companion display name before its signed ADVERT is observed.";
          };
        };
      });

      channelType = lib.types.either lib.types.str (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Channel name (e.g. '#ioi' or custom PSK channel).";
          };
          pskBase64 = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional base64 16/32-byte PSK (omit for '#hashtag' channels).";
          };
        };
      });

      siteSubmodule = { defaultName, defaultRemote, defaultKissPort, defaultWebPort, defaultScope }:
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = defaultName;
            };
            remoteAddr = lib.mkOption {
              type = lib.types.str;
              default = defaultRemote;
              description = "Remote NetBird ser2net KISS TCP endpoint (host:port).";
            };
            virtualKissPort = lib.mkOption {
              type = lib.types.port;
              default = defaultKissPort;
              description = "Loopback TCP port exposed to this site's OwlShack instance.";
            };
            webPort = lib.mkOption {
              type = lib.types.port;
              default = defaultWebPort;
              description = "OwlShack web UI listen port (exposed on wt0).";
            };
            defaultScope = lib.mkOption {
              type = lib.types.str;
              default = defaultScope;
              description = "'*' for unscoped flood, or '#region' (e.g. '#ioi').";
            };
            freqMHz = lib.mkOption {
              type = lib.types.float;
              default = 869.618;
            };
            bwKHz = lib.mkOption {
              type = lib.types.float;
              default = 62.5;
            };
            sf = lib.mkOption {
              type = lib.types.int;
              default = 8;
            };
            cr = lib.mkOption {
              type = lib.types.int;
              default = 8;
            };
            txPower = lib.mkOption {
              type = lib.types.int;
              default = 20;
              description = "LoRa TX power in dBm (max 20 dBm on SX1276 PA_BOOST).";
            };
          };
        };

      normalizeCompanion = c:
        if builtins.isString c then { pubKey = c; }
        else { inherit (c) pubKey; } // lib.optionalAttrs (c.name != "") { inherit (c) name; };

      normalizeChannel = ch:
        if builtins.isString ch then { name = ch; }
        else { inherit (ch) name; } // lib.optionalAttrs (ch.pskBase64 != "") { inherit (ch) pskBase64; };

      mkSiteBridgeJson = s: {
        inherit (s) name remoteAddr defaultScope freqMHz bwKHz sf cr txPower;
        listenAddr = "127.0.0.1:${toString s.virtualKissPort}";
      };

      bridgeConfigFile = pkgs.writeText "owlstack-bridge.json" (builtins.toJSON ({
        stateDir = "/var/lib/owlstack-bridge";
        metricsAddr = "0.0.0.0:${toString cfg.metricsPort}";
        allowedCompanions = map normalizeCompanion cfg.allowedCompanions;
        extraChannels = map normalizeChannel cfg.extraChannels;
        ackWindowSecs = cfg.ackWindowSecs;
        maxFloodHops = cfg.maxFloodHops;
        siteA = mkSiteBridgeJson cfg.pinto;
        siteB = mkSiteBridgeJson cfg.dublin;
      } // lib.optionalAttrs (cfg.allowlistFile != null) {
        allowlistFile = cfg.allowlistFile;
      }));

      mkOwlshackSeed = s:
        let
          bareScope = lib.removePrefix "#" s.defaultScope;
          isScoped = bareScope != "" && bareScope != "*";
        in
        pkgs.writeText "owlshack-${s.name}-seed.json" (builtins.toJSON ({
          connection = "tcp://127.0.0.1:${toString s.virtualKissPort}";
          freq = s.freqMHz;
          bw = s.bwKHz;
          inherit (s) sf cr;
          tx = s.txPower;
          floodScope = if isScoped then "region:${bareScope}" else "everywhere";
          floodRegions = lib.optional isScoped { name = bareScope; };
          listenAddr = "0.0.0.0:${toString s.webPort}";
          setupComplete = true;
          companions = [ ];
        }));

      mkOwlshackService = s:
        let
          stateDirName = "owlshack-${s.name}";
          seedFile = mkOwlshackSeed s;
          startScript = pkgs.writeShellScript "start-${stateDirName}" ''
            set -euo pipefail
            if [ ! -f /var/lib/${stateDirName}/meshcore.db ]; then
              exec ${owlshackPkg}/bin/owlshack -c ${seedFile}
            else
              exec ${owlshackPkg}/bin/owlshack
            fi
          '';
        in
        {
          description = "OwlShack MeshCore Web UI & Node (${s.name})";
          after = [ "network-online.target" "owlstack-bridge.service" ];
          wants = [ "network-online.target" "owlstack-bridge.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            HOST = "0.0.0.0";
            PORT = toString s.webPort;
          };
          serviceConfig = {
            ExecStart = startScript;
            StateDirectory = stateDirName;
            WorkingDirectory = "/var/lib/${stateDirName}";
            Restart = "always";
            RestartSec = 5;
            DynamicUser = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };
    in
    {
      options.services.owlstack = {
        enable = lib.mkEnableOption "OwlShack + selective Pinto<->Dublin MeshCore KISS bridge";

        allowedCompanions = lib.mkOption {
          type = lib.types.listOf companionType;
          default = [ ];
          description = "Companions allowed to flood across the Pinto<->Dublin link (all others are clamped to 0-hop DIRECT).";
        };

        extraChannels = lib.mkOption {
          type = lib.types.listOf channelType;
          default = [ "#ioi" ];
          description = "Channels (in addition to Public) decrypted to match verified companion names on GRP_TXT.";
        };

        allowlistFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional runtime file path (JSON or newline-separated hex pubkeys, e.g. from sops-nix).";
        };

        ackWindowSecs = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Window in seconds after an allowlisted DM/REQ during which ACKs may flood across the bridge.";
        };

        maxFloodHops = lib.mkOption {
          type = lib.types.int;
          default = 16;
          description = "Maximum flood hop count accepted for cross-site flooding.";
        };

        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = 9620;
          description = "HTTP port for /healthz and Prometheus /metrics (wt0 only).";
        };

        pinto = lib.mkOption {
          type = siteSubmodule {
            defaultName = "pinto";
            defaultRemote = "hispanas.netbird.cloud:7620";
            defaultKissPort = 17620;
            defaultWebPort = 8620;
            defaultScope = "*";
          };
          default = { };
        };

        dublin = lib.mkOption {
          type = siteSubmodule {
            defaultName = "dublin";
            defaultRemote = "lenovix.netbird.cloud:7620";
            defaultKissPort = 17621;
            defaultWebPort = 8621;
            defaultScope = "#ioi";
          };
          default = { };
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.owlstack-bridge = {
          description = "MeshCore KISS Arbiter & Selective Pinto<->Dublin Bridge";
          after = [ "network-online.target" "netbird.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${bridgePkg}/bin/owlstack-bridge --config ${bridgeConfigFile}";
            ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
            StateDirectory = "owlstack-bridge";
            Restart = "always";
            RestartSec = 3;
            DynamicUser = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        systemd.services."owlshack-${cfg.pinto.name}" = mkOwlshackService cfg.pinto;
        systemd.services."owlshack-${cfg.dublin.name}" = mkOwlshackService cfg.dublin;

        networking.firewall.interfaces.wt0.allowedTCPPorts = [
          cfg.pinto.webPort
          cfg.dublin.webPort
          cfg.metricsPort
        ];
      };
    };
}
