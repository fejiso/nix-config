{ ... }: {
  flake.modules.nixos.backup =
{ config, lib, pkgs, hostname, inputs, ... }:

with lib;

let
  cfg = config.services.backup;
  kopia = pkgs.kopia;
  openssl = "${pkgs.openssl}/bin/openssl";
in {
  options.services.backup = {
    enable = mkEnableOption "Kopia backup service";

    server = mkEnableOption "Kopia repository server role";

    repoPath = mkOption {
      type = types.str;
      default = "/var/lib/kopia-repo";
      description = "Location of the Kopia repository on the server (local path)";
    };

    serverAddress = mkOption {
      type = types.str;
      default = "https://butthead.netbird.cloud:51515";
      description = "Address of the Kopia server";
    };

    sharedPath = mkOption {
      type = types.str;
      default = "/mnt/Backups/Kopia";
      description = ''
        NFS-mounted path to the Kopia shared directory.
        Clients read the server fingerprint and write their hostname for
        auto-registration here. Defaults to the NFS mount of the server's
        repoPath parent directory.
      '';
    };
  };

  config = mkMerge [
    # Common Configuration
    (mkIf cfg.enable {
      environment.systemPackages = [ kopia ];

      sops.secrets.kopia_repo_password = {
        sopsFile = "${inputs.self}/secrets/kopia.yaml";
        key = "repo_password";
      };
      sops.secrets.kopia_server_password = {
        sopsFile = "${inputs.self}/secrets/kopia.yaml";
        key = "server_password";
      };
    })

    # Server Configuration
    (mkIf (cfg.enable && cfg.server) {
      systemd.tmpfiles.rules = [
        "d ${cfg.repoPath} 0755 root root -"
        "d ${cfg.repoPath}/known-clients 0777 root root -"
      ];

      systemd.services.kopia-server = {
        description = "Kopia Repository Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" "systemd-tmpfiles-setup.service" ];
        path = [ kopia pkgs.openssl ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10";
          CacheDirectory = "kopia";
          StateDirectory = "kopia";
        };
        environment = {
          HOME = "/var/lib/kopia";
        };
        script = ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_repo_password.path})"

          if [ ! -f "$HOME/.config/kopia/repository.config" ]; then
            if [ -f "${cfg.repoPath}/kopia.repository.f" ]; then
              echo "Found existing repository at ${cfg.repoPath}, connecting..."
              ${kopia}/bin/kopia repository connect filesystem --path ${cfg.repoPath}
            else
              echo "Creating new repository at ${cfg.repoPath}..."
              ${kopia}/bin/kopia repository create filesystem --path ${cfg.repoPath}
            fi
          fi

          CERT_FILE="$HOME/.config/kopia/server.crt"
          KEY_FILE="$HOME/.config/kopia/server.key"
          mkdir -p "$(dirname "$CERT_FILE")"
          if [ ! -f "$CERT_FILE" ]; then
            echo "Generating TLS certificate..."
            ${openssl} req -x509 -newkey rsa:4096 -keyout "$KEY_FILE" -out "$CERT_FILE" \
              -days 3650 -nodes -subj "/CN=${hostname}" \
              -addext "subjectAltName=DNS:${hostname},DNS:${hostname}.netbird.cloud"
          fi

          FINGERPRINT=$(${openssl} x509 -fingerprint -sha256 -noout -in "$CERT_FILE" | sed 's/.*=//;s/://g')
          echo "$FINGERPRINT" > ${cfg.repoPath}/server-fingerprint
          chmod 0644 ${cfg.repoPath}/server-fingerprint
          echo "Server fingerprint published: $FINGERPRINT"

          exec ${kopia}/bin/kopia server start --address 0.0.0.0:51515 \
            --tls-cert-file "$CERT_FILE" --tls-key-file "$KEY_FILE"
        '';
      };

      systemd.services.kopia-register-clients = {
        description = "Register Kopia backup clients";
        after = [ "kopia-server.service" ];
        requires = [ "kopia-server.service" ];
        serviceConfig = {
          Type = "oneshot";
        };
        environment = {
          HOME = "/var/lib/kopia";
        };
        path = [ kopia ];
        script = ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_repo_password.path})"
          SERVER_PASS="$(cat ${config.sops.secrets.kopia_server_password.path})"
          for client_file in ${cfg.repoPath}/known-clients/*; do
            [ -f "$client_file" ] || continue
            client_hostname=$(basename "$client_file")
            echo "Ensuring client registered: $client_hostname"
            ${kopia}/bin/kopia server user add backup-user@"$client_hostname" \
              --user-password="$SERVER_PASS" 2>/dev/null || true
          done
        '';
      };

      systemd.timers.kopia-register-clients = {
        description = "Periodically register new Kopia clients";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "60s";
          AccuracySec = "10s";
        };
      };

      networking.firewall.allowedTCPPorts = [ 51515 ];
    })

    # Client Configuration
    (mkIf cfg.enable {
      systemd.services.kopia-backup = {
        description = "Kopia Backup Snapshot";
        after = [ "sops-nix.service" ] ++ lib.optionals (cfg.server) [ "kopia-server.service" ];
        wants = lib.optionals (cfg.server) [ "kopia-server.service" ];
        environment = {
          HOME = "/root";
        };
        path = [ kopia ];
        script = ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_server_password.path})"

          mkdir -p ${cfg.sharedPath}/known-clients 2>/dev/null || true
          touch ${cfg.sharedPath}/known-clients/$(hostname) 2>/dev/null || true

          if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
             echo "Kopia not connected. Attempting to connect..."

             FINGERPRINT_FILE="${cfg.sharedPath}/server-fingerprint"

             for i in $(seq 1 60); do
               [ -f "$FINGERPRINT_FILE" ] && break
               echo "Waiting for server fingerprint... (attempt $i/60)"
               sleep 5
             done

             if [ ! -f "$FINGERPRINT_FILE" ]; then
               echo "Server fingerprint not found at $FINGERPRINT_FILE. Is the kopia server running?"
               exit 1
             fi

             FINGERPRINT=$(cat "$FINGERPRINT_FILE")

             for i in $(seq 1 12); do
               echo "Connecting to ${cfg.serverAddress} with fingerprint $FINGERPRINT (attempt $i/12)"
               if ${kopia}/bin/kopia repository connect server \
                 --url ${cfg.serverAddress} \
                 --server-cert-fingerprint "$FINGERPRINT" \
                 --override-hostname "$(hostname)" \
                 --override-username "backup-user"; then
                 break
               fi
               echo "Connection failed — waiting for server to register our user..."
               sleep 30
             done

             if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
               echo "Failed to connect after retries."
               exit 1
             fi
          fi

          echo "Starting snapshot..."
          ${kopia}/bin/kopia snapshot create /home /var/lib

          ${kopia}/bin/kopia policy set --global --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-annual 1
        '';
      };

      systemd.timers.kopia-backup = {
        description = "Run Kopia backup daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    })
  ];
}
;
}
