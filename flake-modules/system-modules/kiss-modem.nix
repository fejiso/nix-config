{ ... }: {
  # Export a local MeshCore USB KISS modem (e.g. TTGO LoRa32 pre-1.0 / V1.0)
  # over NetBird TCP via ser2net, with HUPCL disabled so TCP reconnects do not
  # toggle DTR/RTS and reset the ESP32.
  flake.modules.nixos.kiss-modem =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.kiss-modem;

      ser2netConfig = pkgs.writeText "kiss-modem-ser2net.yaml" ''
        %YAML 1.1
        ---
        connection: &kiss0
          accepter: tcp(nodelay),0.0.0.0,${toString cfg.port}
          enable: on
          options:
            kickolduser: true
          connector: serialdev,${cfg.device},${toString cfg.baudRate}n81,local,nobreak,hangup-when-done=false
      '';

      ensureDeviceScript = pkgs.writeShellScript "ensure-kiss-modem-device" ''
        set -euo pipefail
        export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.psmisc pkgs.systemd ]}:$PATH"
        dev=${lib.escapeShellArg cfg.device}
        has_serial_pin=${if cfg.usbSerial != null then "1" else "0"}

        probe_kiss_ping() {
          local cand="$1"
          stty -F "$cand" ${toString cfg.baudRate} raw -echo -echoe -echok -hupcl min 0 time 2 2>/dev/null || return 1
          exec 3<>"$cand" || return 1
          dd <&3 bs=256 count=4 status=none >/dev/null 2>&1 || true
          printf '\xc0\x06\x17\xc0' >&3 2>/dev/null || { exec 3>&-; return 1; }
          sleep 0.2
          local hex
          hex=$(dd <&3 bs=64 count=1 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n' || true)
          exec 3>&-
          [[ "$hex" == *"c00697c0"* ]]
        }

        if [ "$dev" = "/dev/kiss-modem" ]; then
          udevadm trigger --subsystem-match=tty --action=change || true
          udevadm settle --timeout=3 || true

          if [ "$has_serial_pin" = "0" ]; then
            shopt -s nullglob
            cands=(/dev/ttyUSB* /dev/ttyACM*)
            free_cands=()
            for cand in "''${cands[@]}"; do
              if ! fuser -s "$cand" 2>/dev/null; then
                free_cands+=("$cand")
              fi
            done

            matched=""
            # Probe free serial ports for MeshCore KISS HW_CMD_PING -> HW_RESP_PING
            # so hosts with multiple CP210x boards (e.g. ESP32-S3 + ESP32 TTGO) pick
            # the actual KISS modem automatically.
            for attempt in 1 2; do
              for cand in "''${free_cands[@]}"; do
                if probe_kiss_ping "$cand"; then
                  matched="$cand"
                  break 2
                fi
              done
              [ "''${#free_cands[@]}" -gt 0 ] && [ "$attempt" -eq 1 ] && sleep 0.5 || true
            done

            if [ -n "$matched" ]; then
              echo "Selected KISS modem on $matched (verified via HW_CMD_PING)"
              ln -sfn "$matched" "$dev"
            elif [ ! -e "$dev" ] && [ "''${#free_cands[@]}" -eq 1 ]; then
              ln -sfn "''${free_cands[0]}" "$dev"
            fi
          fi
        fi

        if [ -e "$dev" ]; then
          real_dev=$(readlink -f "$dev")
          chgrp dialout "$real_dev" || true
          chmod 0660 "$real_dev" || true
          stty -F "$real_dev" -hupcl || true
        else
          echo "WARNING: $dev not present yet; check USB cable / lsusb" >&2
        fi
      '';

      udevRules =
        if cfg.usbSerial != null then ''
          SUBSYSTEM=="tty", ATTRS{serial}=="${cfg.usbSerial}", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
        ''
        else if (cfg.usbVendor != null && cfg.usbProduct != null) then ''
          SUBSYSTEM=="tty", ATTRS{idVendor}=="${cfg.usbVendor}", ATTRS{idProduct}=="${cfg.usbProduct}", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
        ''
        else ''
          # Set permissions & ModemManager ignore on candidate USB-UART bridges;
          # ensureDeviceScript selects the responding KISS modem when multiple TTYs exist.
          SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d3", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1"
        '';
    in
    {
      options.services.kiss-modem = {
        enable = lib.mkEnableOption "MeshCore KISS modem TCP export over NetBird";

        device = lib.mkOption {
          type = lib.types.str;
          default = "/dev/kiss-modem";
          description = "Serial device node for the KISS modem.";
        };

        baudRate = lib.mkOption {
          type = lib.types.int;
          default = 115200;
          description = "UART baud rate for the MeshCore kiss_modem firmware.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 7620;
          description = "TCP listen port (exposed on NetBird wt0 only).";
        };

        usbVendor = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "10c4";
          description = "Optional USB vendor ID filter for the /dev/kiss-modem udev symlink.";
        };

        usbProduct = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "ea60";
          description = "Optional USB product ID filter for the /dev/kiss-modem udev symlink.";
        };

        usbSerial = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional USB serial attribute filter when multiple USB-UART adapters are attached.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.udev.extraRules = lib.mkIf (cfg.device == "/dev/kiss-modem") udevRules;

        environment.systemPackages = [
          pkgs.esptool
          pkgs.picocom
        ];

        systemd.services.kiss-modem-tcp = {
          description = "MeshCore KISS modem serial-to-TCP bridge (ser2net)";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStartPre = "+${ensureDeviceScript}";
            ExecStart = "${pkgs.ser2net}/bin/ser2net -n -u -c ${ser2netConfig}";
            Restart = "always";
            RestartSec = 2;
            DynamicUser = true;
            SupplementaryGroups = [ "dialout" ];
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        # Mesh-only access over NetBird.
        networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.port ];
      };
    };
}
