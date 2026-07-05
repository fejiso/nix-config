{ ... }: {
  flake.modules.nixos.backup =
{ config, lib, pkgs, hostname, inputs, ... }:

with lib;

let
  cfg = config.services.backup;
  kopia = pkgs.kopia;
  openssl = "${pkgs.openssl}/bin/openssl";
  # Snapshot these trees on every host.
  snapshotPaths = "/home /var/lib";
  # Global retention applied by each client to its own snapshots.
  retentionPolicy = "--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-annual 10";
  # Ignore-pattern flags built from services.backup.ignore (empty when unset).
  ignoreArgs = concatMapStringsSep " " (p: "--add-ignore " + escapeShellArg p) cfg.ignore;
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
      description = "Address of the Kopia server (used by remote clients over netbird)";
    };

    serverFingerprint = mkOption {
      type = types.str;
      default = "";
      description = ''
        SHA256 fingerprint of the Kopia server's TLS certificate (hex, no
        colons), as printed on server startup and written to
        <repoPath>/server-fingerprint. Required by remote clients to pin the
        server cert (kopia pins the fingerprint, so no hostname validation).
        Set once globally (system/base.nix) after the server's cert stabilises;
        it is a public value (embedded in the TLS cert).
      '';
    };

    clients = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Hostnames of every NixOS host that backs up to this server (each is
        registered as backup-user@<hostname>). Server-only. Replaces the old
        NFS-shared known-clients/ auto-registration, which only worked for the
        handful of hosts that mounted the share.
      '';
    };

    ignore = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Glob patterns to exclude from snapshots, applied to each client's global
        kopia policy (so they apply to every snapshot source). Patterns are
        matched relative to a source root — use a `**/` prefix to match at any
        depth, e.g. `"**/.cache"` or `"**/node_modules"`. Override per host.
      '';
    };
  };

  config = mkMerge [
    # Common — runs on every enabled host (server and remote clients).
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

      # Daily snapshot timer — applies to server-host and remote clients alike.
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

    # Server role: run the kopia repository TCP server + register clients.
    (mkIf (cfg.enable && cfg.server) {
      systemd.tmpfiles.rules = [
        "d ${cfg.repoPath} 0755 root root -"
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
            --tls-cert-file "$CERT_FILE" --tls-key-file "$KEY_FILE" \
            --server-username "admin" \
            --server-password-file ${config.sops.secrets.kopia_server_password.path}
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
        script = let
          ensureClient = h: ''
            echo "Syncing client user: ${h}"
            ${kopia}/bin/kopia server user set backup-user@${h} \
              --user-password="$SERVER_PASS"
          '';
        in ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_repo_password.path})"
          SERVER_PASS="$(cat ${config.sops.secrets.kopia_server_password.path})"
          ${concatMapStringsSep "\n" ensureClient cfg.clients}
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

    # Server-host client: back this box up via localhost, bypassing netbird/NFS.
    # Reads the fingerprint from the local repo file (written by kopia-server),
    # so it tracks the cert automatically — no baked fingerprint needed here.
    (mkIf (cfg.enable && cfg.server) {
      systemd.services.kopia-backup = {
        description = "Kopia Backup Snapshot (server host)";
        after = [ "sops-nix.service" "kopia-server.service" ];
        wants = [ "kopia-server.service" ];
        environment = {
          HOME = "/root";
        };
        path = [ kopia ];
        script = ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_server_password.path})"

          FINGERPRINT_FILE="${cfg.repoPath}/server-fingerprint"
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

          if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
            echo "Kopia not connected. Attempting to connect to localhost..."
            for i in $(seq 1 12); do
              echo "Connecting to https://localhost:51515 (attempt $i/12)"
              if ${kopia}/bin/kopia repository connect server \
                --url https://localhost:51515 \
                --server-cert-fingerprint "$FINGERPRINT" \
                --override-hostname "$(hostname)" \
                --override-username "backup-user"; then
                break
              fi
              echo "Connection failed — waiting for user registration..."
              sleep 30
            done
            if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
              echo "Failed to connect after retries."
              exit 1
            fi
          fi

          echo "Starting snapshot..."
          ${kopia}/bin/kopia snapshot create ${snapshotPaths}
          ${kopia}/bin/kopia policy set --global ${retentionPolicy} ${ignoreArgs}
        '';
      };
    })

    # Remote clients: back up via the kopia server over netbird, pinning the
    # server cert by the fingerprint from config (services.backup.serverFingerprint).
    (mkIf (cfg.enable && !cfg.server) {
      systemd.services.kopia-backup = {
        description = "Kopia Backup Snapshot";
        after = [ "sops-nix.service" ];
        environment = {
          HOME = "/root";
        };
        path = [ kopia ];
        script = ''
          export KOPIA_PASSWORD="$(cat ${config.sops.secrets.kopia_server_password.path})"

          if [ -z "${cfg.serverFingerprint}" ]; then
            echo "services.backup.serverFingerprint is empty — set it (in system/base.nix) to the kopia server's TLS fingerprint." >&2
            exit 1
          fi

          if ! ${kopia}/bin/kopia repository status >/dev/null 2>&1; then
            echo "Kopia not connected. Attempting to connect to ${cfg.serverAddress}..."
            for i in $(seq 1 12); do
              echo "Connecting (attempt $i/12)"
              if ${kopia}/bin/kopia repository connect server \
                --url ${cfg.serverAddress} \
                --server-cert-fingerprint "${cfg.serverFingerprint}" \
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
          ${kopia}/bin/kopia snapshot create ${snapshotPaths}
          ${kopia}/bin/kopia policy set --global ${retentionPolicy} ${ignoreArgs}
        '';
      };
    })
  ];
}
;
}
