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
          homeSite = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional home site name ('pinto' or 'dublin') for directional zeroHopChannels.";
          };
        };
      });

      siteSubmodule = { defaultName, defaultAdvertName, defaultRemote, defaultKissPort, defaultWebPort, defaultScope, defaultPathHashSize, defaultFreqMHz }:
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = defaultName;
            };
            advertName = lib.mkOption {
              type = lib.types.str;
              default = defaultAdvertName;
              description = "Signed REPEATER advert name emitted for this site's tunnel hop (empty string disables adverts).";
            };
            directAdvertMins = lib.mkOption {
              type = lib.types.int;
              default = 120;
              description = "0-hop DIRECT repeater advert interval in minutes (MeshCore default: 120m / 2h; <0 disables).";
            };
            floodAdvertMins = lib.mkOption {
              type = lib.types.int;
              default = 720;
              description = "Scoped FLOOD repeater advert interval in minutes (MeshCore default: 720m / 12h; <0 disables).";
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
            pathHashSize = lib.mkOption {
              type = lib.types.int;
              default = defaultPathHashSize;
              description = "Default MeshCore path hash size in bytes (1, 2, or 3).";
            };
            freqMHz = lib.mkOption {
              type = lib.types.float;
              default = defaultFreqMHz;
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
            channels = lib.mkOption {
              type = lib.types.listOf channelType;
              default = cfg.bridgedChannels ++ cfg.zeroHopChannels ++ cfg.extraChannels;
              description = "Channels declaratively ensured on every OwlShack companion at this site.";
            };
          };
        };

      normalizeCompanion = c:
        if builtins.isString c then { pubKey = c; }
        else { inherit (c) pubKey; } // lib.optionalAttrs (c.name != "") { inherit (c) name; };

      normalizeHashtagName = name:
        if name == "Public" || lib.hasPrefix "#" name then name else "#${name}";

      normalizeChannel = ch:
        if builtins.isString ch then { name = normalizeHashtagName ch; }
        else
          ({
            name = if ch.pskBase64 != "" then ch.name else normalizeHashtagName ch.name;
          }
          // lib.optionalAttrs (ch.pskBase64 != "") { inherit (ch) pskBase64; }
          // lib.optionalAttrs (ch.homeSite != "") { inherit (ch) homeSite; });

      dedupChannels = chs:
        lib.foldl' (acc: ch:
          if builtins.any (x: x.name == ch.name) acc then acc else acc ++ [ ch ]
        ) [ ] (map normalizeChannel chs);

      mkSiteBridgeJson = s: {
        inherit (s) name advertName directAdvertMins floodAdvertMins pathHashSize remoteAddr defaultScope freqMHz bwKHz sf cr txPower;
        listenAddr = "127.0.0.1:${toString s.virtualKissPort}";
      };

      bridgeConfigFile = pkgs.writeText "owlstack-bridge.json" (builtins.toJSON ({
        stateDir = "/var/lib/owlstack-bridge";
        metricsAddr = "0.0.0.0:${toString cfg.metricsPort}";
        allowedCompanions = map normalizeCompanion cfg.allowedCompanions;
        bridgedChannels = dedupChannels cfg.bridgedChannels;
        zeroHopChannels = dedupChannels cfg.zeroHopChannels;
        ackWindowSecs = cfg.ackWindowSecs;
        maxFloodHops = cfg.maxFloodHops;
        siteA = mkSiteBridgeJson cfg.pinto;
        siteB = mkSiteBridgeJson cfg.dublin;
      } // lib.optionalAttrs (cfg.allowlistFile != null) {
        allowlistFile = cfg.allowlistFile;
      }));

      mkOwlshackService = s:
        let
          stateDirName = "owlshack-${s.name}";
          bareScope = lib.removePrefix "#" s.defaultScope;
          isScoped = bareScope != "" && bareScope != "*";
          floodScopeStr = if isScoped then "region:${bareScope}" else "everywhere";
          regionsList = lib.optional isScoped { name = bareScope; parent = "*"; };
          kissUrl = "tcp://127.0.0.1:${toString s.virtualKissPort}";
          siteChannelsJson = pkgs.writeText "owlshack-${s.name}-channels.json" (
            builtins.toJSON (dedupChannels s.channels)
          );

          regionsPayload = pkgs.writeText "owlshack-${s.name}-regions.json" (builtins.toJSON {
            regions = regionsList;
            floodScope = floodScopeStr;
          });

          settingsOverride = pkgs.writeText "owlshack-${s.name}-settings.json" (builtins.toJSON {
            connectionType = "kiss";
            connection = kissUrl;
            baudRate = 115200;
            freq = s.freqMHz;
            bw = s.bwKHz;
            inherit (s) sf cr pathHashSize;
            tx = s.txPower;
            listenAddr = "0.0.0.0:${toString s.webPort}";
            setupComplete = true;
          });

          postStartScript = pkgs.writeShellScript "configure-${stateDirName}" ''
            set -euo pipefail
            api="http://127.0.0.1:${toString s.webPort}"
            jq_bin="${pkgs.jq}/bin/jq"
            curl_bin="${pkgs.curl}/bin/curl"

            cur=""
            for _ in $(seq 1 50); do
              if cur=$($curl_bin -fsS "$api/api/config/settings" 2>/dev/null); then
                break
              fi
              sleep 0.2
            done
            if [ -z "$cur" ]; then
              echo "Timed out waiting for OwlShack HTTP API on $api" >&2
              exit 1
            fi

            needs_update=$(printf '%s' "$cur" | $jq_bin -r --slurpfile want "${settingsOverride}" --arg scope "${floodScopeStr}" '
              ($want[0]) as $w |
              if (.connection != $w.connection)
                 or (.setupComplete != true)
                 or (((.freq // 0) - $w.freq) | fabs > 0.0001)
                 or (((.bw // 0) - $w.bw) | fabs > 0.01)
                 or (.sf != $w.sf)
                 or (.cr != $w.cr)
                 or (.tx != $w.tx)
                 or (.pathHashSize != $w.pathHashSize)
                 or (.floodScope != $scope)
              then "yes" else "no" end
            ')

            if [ "$needs_update" = "yes" ]; then
              $curl_bin -fsS -X PUT -H 'Content-Type: application/json' \
                --data @"${regionsPayload}" "$api/api/config/regions" >/dev/null
              merged=$(printf '%s' "$cur" | $jq_bin -c --slurpfile want "${settingsOverride}" '
                . * $want[0] | .packetRetentionDays = (.packetRetentionDays // 7)
              ')
              $curl_bin -fsS -X PUT -H 'Content-Type: application/json' \
                --data "$merged" "$api/api/config/settings" >/dev/null
            fi

            # Declaratively ensure configured channels exist on every companion (via OwlShack's
            # config API so app_config + companion_channels stay in sync across restarts).
            comps=$($curl_bin -fsS "$api/api/config/companions" 2>/dev/null || echo "[]")
            existing_ch=$($curl_bin -fsS "$api/api/config/channels" 2>/dev/null || echo "[]")

            for cid in $(printf '%s' "$comps" | $jq_bin -r '.[].id'); do
              $jq_bin -c '.[]' "${siteChannelsJson}" | while IFS= read -r ch_obj; do
                ch_name=$(printf '%s' "$ch_obj" | $jq_bin -r '.name')
                has_ch=$(printf '%s' "$existing_ch" | $jq_bin -r --argjson cid "$cid" --arg name "$ch_name" '
                  any(.[]; .companionId == $cid and .name == $name)
                ')
                if [ "$has_ch" != "true" ]; then
                  psk_b64=$(printf '%s' "$ch_obj" | $jq_bin -r '.pskBase64 // ""')
                  if [ -n "$psk_b64" ]; then
                    psk_hex=$(printf '%s' "$psk_b64" | ${pkgs.coreutils}/bin/base64 -d | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')
                    body=$($jq_bin -nc --arg name "$ch_name" --arg pk "$psk_hex" '{name: $name, privateKey: $pk, floodScope: "inherit"}')
                  else
                    body=$($jq_bin -nc --arg name "$ch_name" '{name: $name, floodScope: "inherit"}')
                  fi
                  $curl_bin -fsS -X POST -H 'Content-Type: application/json' \
                    --data "$body" "$api/api/config/companions/$cid/channels" >/dev/null || true
                fi
              done
            done
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
            ExecStart = "${owlshackPkg}/bin/owlshack";
            ExecStartPost = postStartScript;
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
          description = "Companions whose signed ADVERTs and private messages/path discovery (whenever either src or dst matches) are bridged across Pinto<->Dublin.";
        };

        bridgedChannels = lib.mkOption {
          type = lib.types.listOf channelType;
          default = [ "#maddub" ];
          description = "Channels bridged full-mesh across Pinto<->Dublin (all participants, hashtag or custom base64 PSK) and declaratively joined on OwlShack companions.";
        };

        zeroHopChannels = lib.mkOption {
          type = lib.types.listOf channelType;
          default = [
            { name = "#ireland"; homeSite = "dublin"; }
            { name = "#dublin"; homeSite = "dublin"; }
            { name = "#madrid"; homeSite = "pinto"; }
          ];
          description = "Non-overlapping city channels bridged asymmetrically: transmissions heard at the away site (even multi-hop via local repeaters) flood onto homeSite's mesh (write), while homeSite mesh floods are clamped to 0-hop DIRECT at the peer site (read without repeater re-broadcast).";
        };

        extraChannels = lib.mkOption {
          type = lib.types.listOf channelType;
          default = [ "#ioi" ];
          description = "Additional local channels declaratively joined on OwlShack companions without cross-site bridging.";
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
            defaultAdvertName = "MAD-DUB-TUNNEL";
            defaultRemote = "hispanas.netbird.cloud:7620";
            defaultKissPort = 17620;
            defaultWebPort = 8620;
            defaultScope = "*";
            defaultPathHashSize = 3;
            # XTAL calibration (-10.1 kHz / +11.6 ppm on hispanas TTGO LoRa32) for 869.618 MHz on-air
            defaultFreqMHz = 869.608;
          };
          default = { };
        };

        dublin = lib.mkOption {
          type = siteSubmodule {
            defaultName = "dublin";
            defaultAdvertName = "DUB-MAD-TUNNEL";
            defaultRemote = "lenovix.netbird.cloud:7620";
            defaultKissPort = 17621;
            defaultWebPort = 8621;
            defaultScope = "#ioi";
            defaultPathHashSize = 3;
            # XTAL calibration (-16.2 kHz / +18.6 ppm on lenovix TTGO LoRa32) for 869.618 MHz on-air
            defaultFreqMHz = 869.602;
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
