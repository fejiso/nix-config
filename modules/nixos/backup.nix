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
      };
      sops.secrets.kopia_server_password = {
        sopsFile = "${inputs.self}/secrets/kopia.yaml";
      };
    })

    # Server Configuration
    (mkIf (cfg.enable && cfg.server) {
      systemd.services.kopia-server = {
        description = "Kopia Repository Server";
        wantedBy = [ "multi-user.target" ];
        environment = {
          KOPIA_PASSWORD_FILE = config.sops.secrets.kopia_repo_password.path;
        };
        path = [ kopia ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10";
        };
        script = ''
          # Initialize repo if config doesn't exist
          if [ ! -f /root/.config/kopia/repository.config ]; then
            echo "Initializing Kopia repository at ${cfg.repoPath}..."
            mkdir -p ${cfg.repoPath}
            ${kopia}/bin/kopia repository create filesystem --path ${cfg.repoPath}
            
            # Add default user
            SERVER_PASS=$(cat ${config.sops.secrets.kopia_server_password.path})
            ${kopia}/bin/kopia server user add backup-user@${hostname} --user-password="$SERVER_PASS"
          fi
          
          # Start server
          # We use --insecure because we are behind a secure mesh (Netbird) or will handle certs later
          # Actually Kopia server insists on TLS. We let it generate one.
          exec ${kopia}/bin/kopia server start --address 0.0.0.0:51515 --tls-generate-cert --tls-print-server-cert
        '';
      };
      
      networking.firewall.allowedTCPPorts = [ 51515 ];
    })

    # Client Configuration
    (mkIf cfg.enable {
      systemd.services.kopia-backup = {
        description = "Kopia Backup Snapshot";
        environment = {
          # We use the server password to connect
          KOPIA_PASSWORD_FILE = config.sops.secrets.kopia_server_password.path;
        };
        path = [ kopia ];
        script = ''
          # Check if connected
          if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
             echo "Kopia not connected. Attempting to connect..."
             # Note: This will fail if the server cert is not trusted.
             # You might need to run this manually once:
             # kopia repository connect server --url ${cfg.serverAddress} --server-cert-fingerprint <FINGERPRINT>
             echo "Automatic connection not fully implemented (needs cert fingerprint). Please connect manually."
             exit 1
          fi
          
          echo "Starting snapshot..."
          ${kopia}/bin/kopia snapshot create /home /var/lib
          
          # Set retention policy (can be run repeatedly, it's idempotent-ish)
          # We set it for the current user/host
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
