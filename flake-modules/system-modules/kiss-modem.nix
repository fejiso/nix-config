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
          connector: serialdev,${cfg.device},${toString cfg.baudRate}n81,local,nobreak,hangup-when-done=false,rts=off,dtr=off
      '';

      udevRules =
        if cfg.usbSerial != null then ''
          SUBSYSTEM=="tty", ATTRS{serial}=="${cfg.usbSerial}", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
        ''
        else if (cfg.usbVendor != null && cfg.usbProduct != null) then ''
          SUBSYSTEM=="tty", ATTRS{idVendor}=="${cfg.usbVendor}", ATTRS{idProduct}=="${cfg.usbProduct}", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
        ''
        else ''
          # Silicon Labs CP210x (standard TTGO LoRa32 pre-1.0 / V1.0 USB-UART)
          SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
          # WCH CH9102 / CH340 variants
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
          SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0660", GROUP="dialout", ENV{ID_MM_DEVICE_IGNORE}="1", SYMLINK+="kiss-modem"
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
