{ config, lib, pkgs, hostname, inputs, ... }:

with lib;

let
  cfg = config.services.backup;
  kopia = pkgs.kopia;
in {
  options.services.backup = {
    enable = mkEnableOption "Kopia backup service";
    
    server = mkEnableOption "Kopia repository server role";
    
    repoPath = mkOption {
      type = types.str;
      default = "/var/lib/kopia-repo";
      description = "Location of the Kopia repository on the server";
    };

    serverAddress = mkOption {
      type = types.str;
      default = "https://butthead.netbird.cloud:51515";
      description = "Address of the Kopia server";
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
        "d ${cfg.repoPath} 0700 root root -"
      ];

      systemd.services.kopia-server = {
        description = "Kopia Repository Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" "systemd-tmpfiles-setup.service" ];
        path = [ kopia ];
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

          # Connect to or create repository
          if [ ! -f "$HOME/.config/kopia/repository.config" ]; then
            # Check if repo data exists at path
            if [ -f "${cfg.repoPath}/kopia.repository.f" ]; then
              echo "Found existing repository at ${cfg.repoPath}, connecting..."
              ${kopia}/bin/kopia repository connect filesystem --path ${cfg.repoPath}
            else
              echo "Creating new repository at ${cfg.repoPath}..."
              ${kopia}/bin/kopia repository create filesystem --path ${cfg.repoPath}
            fi

            # Add server user (ignore if exists)
            SERVER_PASS=$(cat ${config.sops.secrets.kopia_server_password.path})
            ${kopia}/bin/kopia server user add backup-user@${hostname} --user-password="$SERVER_PASS" || true
          fi

          exec ${kopia}/bin/kopia server start --address 0.0.0.0:51515 --tls-generate-cert --tls-print-server-cert
        '';
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

          # Check if connected, auto-connect if not
          if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
             echo "Kopia not connected. Attempting to connect..."

             CERT_FILE="/var/lib/kopia/.config/kopia/kopia.cert"
             if [ -f "$CERT_FILE" ]; then
               FINGERPRINT=$(${pkgs.openssl}/bin/openssl x509 -fingerprint -sha256 -noout -in "$CERT_FILE" | sed 's/.*=//;s/://g')
               echo "Connecting to ${cfg.serverAddress} with fingerprint $FINGERPRINT"
               ${kopia}/bin/kopia repository connect server \
                 --url ${cfg.serverAddress} \
                 --server-cert-fingerprint "$FINGERPRINT" \
                 --override-hostname "$(hostname)" \
                 --override-username "backup-user"
             else
               echo "Server cert not found at $CERT_FILE. Is kopia-server running?"
               exit 1
             fi
          fi

          echo "Starting snapshot..."
          ${kopia}/bin/kopia snapshot create /home /var/lib

          # Set retention policy
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
