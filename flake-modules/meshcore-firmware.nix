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
        work="''${XDG_CACHE_HOME:-$HOME/.cache}/meshcore-kiss-build"
        if [ ! -f "$work/platformio.ini" ]; then
          mkdir -p "$work"
          cp -r ${inputs.meshcore}/. "$work"/
          chmod -R u+w "$work"
        fi
        mkdir -p "$work/variants/lilygo_tlora_v1"
        for src_file in ${variantSrc}/*; do
          dst_file="$work/variants/lilygo_tlora_v1/$(basename "$src_file")"
          if ! cmp -s "$src_file" "$dst_file" 2>/dev/null; then
            cp -f "$src_file" "$dst_file"
            chmod u+w "$dst_file"
          fi
        done
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
                ${pkgs.esptool}/bin/esptool --chip esp32 --port "$port" erase-flash
              fi
              if [ -f "$merged_bin" ]; then
                ${pkgs.esptool}/bin/esptool --chip esp32 --port "$port" --baud 460800 write-flash -z 0x0 "$merged_bin"
              else
                ${pkgs.platformio-core}/bin/pio run -e ${envName} -t upload --upload-port "$port"
              fi
              exit 0
            fi

            if [[ "$host" == *@* ]]; then
              user_part="''${host%%@*}"
              host_part="''${host#*@}"
            else
              user_part="root"
              host_part="$host"
            fi
            if [[ "$host_part" != *.* ]]; then
              host_part="$host_part.netbird.cloud"
            fi
            target="$user_part@$host_part"

            echo "Uploading firmware artefacts to $target ..."
            remote_dir="/tmp/kiss-modem-flash"
            ssh "$target" mkdir -p "$remote_dir"
            scp "$build_dir/bootloader.bin" "$build_dir/partitions.bin" "$build_dir/firmware.bin" "$target:$remote_dir/"
            if [ -f "$merged_bin" ]; then
              scp "$merged_bin" "$target:$remote_dir/merged.bin"
            fi

            port_arg="''${port:-auto}"
            ssh "$target" /usr/bin/env bash -s -- "$port_arg" "$erase" <<'REMOTE_EOF'
            main() {
              set -euo pipefail
              port="$1"
              erase="$2"

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

              run_esptool_v5() {
                if command -v esptool >/dev/null 2>&1; then
                  esptool "$@" </dev/null
                else
                  nix --extra-experimental-features "nix-command flakes" shell nixpkgs#esptool -c esptool "$@" </dev/null
                fi
              }

              is_esp32_port() {
                local cand="$1"
                if command -v fuser >/dev/null 2>&1 && fuser -s "$cand" 2>/dev/null; then
                  echo "Skipping busy serial port $cand" >&2
                  return 1
                fi
                if command -v esptool >/dev/null 2>&1 || ! command -v esptool.py >/dev/null 2>&1; then
                  run_esptool_v5 --chip esp32 --port "$cand" chip-id >/dev/null 2>&1
                else
                  esptool.py --chip esp32 --port "$cand" chip_id </dev/null >/dev/null 2>&1
                fi
              }

              if [ "$port" = "auto" ] || [ -z "$port" ]; then
                shopt -s nullglob
                cands=(/dev/ttyUSB* /dev/ttyACM*)
                if [ "''${#cands[@]}" -eq 0 ]; then
                  echo "No serial port found (/dev/ttyUSB*, /dev/ttyACM*)" >&2
                  exit 1
                fi
                matched=""
                for cand in "''${cands[@]}"; do
                  echo "Probing $cand for ESP32 (TTGO LoRa32)..."
                  if is_esp32_port "$cand"; then
                    matched="$cand"
                    echo "Confirmed ESP32 on $matched"
                    break
                  else
                    echo "  $cand is not a plain ESP32 (or is busy), skipping."
                  fi
                done
                if [ -z "$matched" ]; then
                  echo "ERROR: No plain ESP32 board found among: ''${cands[*]}" >&2
                  exit 1
                fi
                port="$matched"
              fi

              if command -v esptool >/dev/null 2>&1 || ! command -v esptool.py >/dev/null 2>&1; then
                if [ "$erase" -eq 1 ]; then
                  run_esptool_v5 --chip esp32 --port "$port" erase-flash
                fi
                if [ -f /tmp/kiss-modem-flash/merged.bin ]; then
                  run_esptool_v5 --chip esp32 --port "$port" --baud 460800 write-flash -z 0x0 /tmp/kiss-modem-flash/merged.bin
                else
                  run_esptool_v5 --chip esp32 --port "$port" --baud 460800 write-flash -z \
                    0x1000 /tmp/kiss-modem-flash/bootloader.bin \
                    0x8000 /tmp/kiss-modem-flash/partitions.bin \
                    0x10000 /tmp/kiss-modem-flash/firmware.bin
                fi
              else
                if [ "$erase" -eq 1 ]; then
                  esptool.py --chip esp32 --port "$port" erase_flash </dev/null
                fi
                if [ -f /tmp/kiss-modem-flash/merged.bin ]; then
                  esptool.py --chip esp32 --port "$port" --baud 460800 write_flash -z 0x0 /tmp/kiss-modem-flash/merged.bin </dev/null
                else
                  esptool.py --chip esp32 --port "$port" --baud 460800 write_flash -z \
                    0x1000 /tmp/kiss-modem-flash/bootloader.bin \
                    0x8000 /tmp/kiss-modem-flash/partitions.bin \
                    0x10000 /tmp/kiss-modem-flash/firmware.bin </dev/null
                fi
              fi

              if [ -L /dev/kiss-modem ] || [ ! -e /dev/kiss-modem ]; then
                ln -sfn "$port" /dev/kiss-modem
              fi
              sleep 1.5

              rm -rf /tmp/kiss-modem-flash
            }
            main "$@"
            REMOTE_EOF
            echo "Remote flash on $target complete!"
          '');
        };
      };
    };
}
