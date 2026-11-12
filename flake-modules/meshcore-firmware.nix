{ inputs, ... }: {
  # MeshCore kiss_modem firmware tooling for pre-1.0 / V1.0 TTGO LoRa32 boards
  # (source: github.com/meshcore-dev/MeshCore v1.18.0 + firmware/meshcore-tlora-v1).
  #
  #   nix develop .#meshcore                              — platformio + esptool shell
  #   nix run .#kiss-modem-build                          — build LilyGo_TLora_V1_0_kiss_modem
  #   nix run .#kiss-modem-flash -- --port /dev/ttyUSB0   — build + flash locally
  #   nix run .#kiss-modem-flash -- --host hispanas       — build locally + flash over SSH
  #   nix run .#kiss-modem-flash -- --host lenovix        — build locally + flash over SSH
  perSystem = { pkgs, ... }:
    let
      variantSrc = ../firmware/meshcore-tlora-v1;
      envName = "LilyGo_TLora_V1_0_kiss_modem";

      prepareTree = ''
        work=$(mktemp -d /tmp/meshcore-kiss.XXXXXX)
        cp -r ${inputs.meshcore}/. "$work"/
        chmod -R u+w "$work"
        mkdir -p "$work/variants/lilygo_tlora_v1"
        cp -f ${variantSrc}/* "$work/variants/lilygo_tlora_v1/"
        chmod -R u+w "$work/variants/lilygo_tlora_v1"
        cd "$work"
      '';
    in
    {
      devShells.meshcore = pkgs.mkShell {
        packages = [
          pkgs.platformio-core
          pkgs.esptool
          pkgs.picocom
        ];
      };

      apps = {
        kiss-modem-build = {
          type = "app";
          program = toString (pkgs.writeShellScript "kiss-modem-build" ''
            set -euo pipefail
            ${prepareTree}
            ${pkgs.platformio-core}/bin/pio run -e ${envName} -t mergebin
            echo "Build complete: $work/.pio/build/${envName}/"
            ls -lh "$work/.pio/build/${envName}/"*.bin
          '');
        };

        kiss-modem-flash = {
          type = "app";
          program = toString (pkgs.writeShellScript "kiss-modem-flash" ''
            set -euo pipefail

            host=""
            port=""
            erase=0

            while [ $# -gt 0 ]; do
              case "$1" in
                --host|-H)
                  host="$2"
                  shift 2
                  ;;
                --port|-p)
                  port="$2"
                  shift 2
                  ;;
                --erase)
                  erase=1
                  shift
                  ;;
                --help|-h)
                  echo "Usage: nix run .#kiss-modem-flash -- [--host <hostname>] [--port /dev/kiss-modem|/dev/ttyUSB0] [--erase]"
                  exit 0
                  ;;
                *)
                  echo "Unknown argument: $1" >&2
                  exit 1
                  ;;
              esac
            done

            ${prepareTree}
            ${pkgs.platformio-core}/bin/pio run -e ${envName} -t mergebin

            build_dir="$work/.pio/build/${envName}"
            merged_bin="$build_dir/firmware-merged.bin"

            if [ -z "$host" ]; then
              if [ -z "$port" ]; then
                if [ -e /dev/kiss-modem ]; then
                  port="/dev/kiss-modem"
                else
                  port="/dev/ttyUSB0"
                fi
              fi
              echo "Flashing local board on $port ..."
              if [ "$erase" -eq 1 ]; then
                ${pkgs.esptool}/bin/esptool.py --chip esp32 --port "$port" erase_flash
              fi
              if [ -n "$merged_bin" ]; then
                ${pkgs.esptool}/bin/esptool.py --chip esp32 --port "$port" --baud 460800 write_flash -z 0x0 "$merged_bin"
              else
                ${pkgs.platformio-core}/bin/pio run -e ${envName} -t upload --upload-port "$port"
              fi
              exit 0
            fi

            target="root@$host"
            if [[ "$host" != *.* ]]; then
              target="root@$host.netbird.cloud"
            fi

            echo "Uploading firmware artefacts to $target ..."
            remote_dir="/tmp/kiss-modem-flash"
            ssh "$target" "mkdir -p $remote_dir"
            scp "$build_dir/bootloader.bin" "$build_dir/partitions.bin" "$build_dir/firmware.bin" "$target:$remote_dir/"
            if [ -n "$merged_bin" ]; then
              scp "$merged_bin" "$target:$remote_dir/merged.bin"
            fi

            ssh "$target" '
              set -euo pipefail
              port="'"$port"'"
              if [ -z "$port" ]; then
                if [ -e /dev/kiss-modem ]; then
                  port=/dev/kiss-modem
                elif [ -e /dev/ttyUSB0 ]; then
                  port=/dev/ttyUSB0
                elif [ -e /dev/ttyACM0 ]; then
                  port=/dev/ttyACM0
                else
                  echo "No serial port found (/dev/kiss-modem, /dev/ttyUSB0, /dev/ttyACM0)" >&2
                  exit 1
                fi
              fi

              was_active=0
              if systemctl is-active --quiet kiss-modem-tcp.service 2>/dev/null; then
                was_active=1
                echo "Stopping kiss-modem-tcp.service before flash..."
                systemctl stop kiss-modem-tcp.service
                sleep 1
              fi

              restore_svc() {
                if [ "$was_active" -eq 1 ]; then
                  echo "Restarting kiss-modem-tcp.service..."
                  systemctl start kiss-modem-tcp.service
                fi
              }
              trap restore_svc EXIT

              flash_cmd="nix-shell -p esptool --run"
              if command -v esptool.py >/dev/null 2>&1; then
                esptool_bin="esptool.py"
              else
                esptool_bin=""
              fi

              run_esptool() {
                if [ -n "$esptool_bin" ]; then
                  "$esptool_bin" "$@"
                else
                  nix --extra-experimental-features "nix-command flakes" shell nixpkgs#esptool -c esptool.py "$@"
                fi
              }

              if [ "'"$erase"'" -eq 1 ]; then
                run_esptool --chip esp32 --port "$port" erase_flash
              fi

              if [ -f /tmp/kiss-modem-flash/merged.bin ]; then
                run_esptool --chip esp32 --port "$port" --baud 460800 write_flash -z 0x0 /tmp/kiss-modem-flash/merged.bin
              else
                run_esptool --chip esp32 --port "$port" --baud 460800 write_flash -z \
                  0x1000 /tmp/kiss-modem-flash/bootloader.bin \
                  0x8000 /tmp/kiss-modem-flash/partitions.bin \
                  0x10000 /tmp/kiss-modem-flash/firmware.bin
              fi
              rm -rf /tmp/kiss-modem-flash
            '
            echo "Remote flash on $target complete!"
          '');
        };
      };
    };
}
