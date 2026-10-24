{ inputs, ... }: {
  # ESP32 blinkenlights firmware tooling (source: github.com/fejiso/blinkenlights,
  # flake input `blinkenlights`, flake = false).
  #
  #   nix develop .#blinkenlights   — platformio + sops shell for local hacking
  #   nix run .#blinkenlights-build — build firmware from the pinned source
  #   nix run .#blinkenlights-flash — build + `pio run -t upload`
  #
  # The apps copy the pinned source into a temp dir (the store is read-only
  # and pio needs a writable build tree) and decrypt the Wi-Fi credentials
  # from the private input's secrets/blinkenlights.ini via sops (user age key).
  perSystem = { pkgs, ... }: {
    devShells.blinkenlights = pkgs.mkShell {
      packages = [ pkgs.platformio-core pkgs.sops ];
    };

    apps =
      let
        mkApp = upload: {
          type = "app";
          program = toString (pkgs.writeShellScript "blinkenlights-${if upload then "flash" else "build"}" ''
            set -euo pipefail
            work=$(mktemp -d /tmp/blinkenlights.XXXXXX)
            cp -r ${inputs.blinkenlights}/. "$work"/
            chmod -R u+w "$work"
            cd "$work"
            ${pkgs.sops}/bin/sops --decrypt --input-type ini --output-type ini \
              ${inputs.private}/secrets/blinkenlights.ini > secrets.ini
            ${pkgs.platformio-core}/bin/pio run ${if upload then "-t upload" else ""}
            echo "build tree: $work (firmware.bin in .pio/build/esp32dev/)"
          '');
        };
      in
      {
        blinkenlights-build = mkApp false;
        blinkenlights-flash = mkApp true;
      };
  };
}
