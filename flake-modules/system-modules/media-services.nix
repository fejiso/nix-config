{ ... }: {
  flake.modules.nixos.media-services =
# Media services configuration for containers
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:

with lib;

{
  options.services.media-stack = {
    enable = mkEnableOption "media stack services";
    
    dataDir = mkOption {
      type = types.str;
      default = "/mnt/user";
      description = "Base directory for media data";
    };
    
    services = {
      sonarr = {
        enable = mkEnableOption "Sonarr TV series management";
        port = mkOption {
          type = types.port;
          default = 8989;
          description = "Port for Sonarr web interface";
        };
      };
      
      radarr = {
        enable = mkEnableOption "Radarr movie management";
        port = mkOption {
          type = types.port;
          default = 7878;
          description = "Port for Radarr web interface";
        };
      };
      
      lidarr = {
        enable = mkEnableOption "Lidarr music management";
        port = mkOption {
          type = types.port;
          default = 8686;
          description = "Port for Lidarr web interface";
        };
      };
      
      prowlarr = {
        enable = mkEnableOption "Prowlarr indexer management";
        port = mkOption {
          type = types.port;
          default = 9696;
          description = "Port for Prowlarr web interface";
        };
      };
      
      jellyfin = {
        enable = mkEnableOption "Jellyfin media server";
        port = mkOption {
          type = types.port;
          default = 8096;
          description = "Port for Jellyfin web interface";
        };
      };

      emby = {
        enable = mkEnableOption "Emby media server";
        port = mkOption {
          type = types.port;
          default = 8920;
          description = "Port for Emby web interface";
        };
      };
    };
  };

  config = mkIf config.services.media-stack.enable {
    services.nspawn-containers = {
      enable = true;
      
      containers = {
        # Sonarr container
        sonarr = mkIf config.services.media-stack.services.sonarr.enable {
          enable = true;
          
          bindMounts = {
            "/data" = {
              hostPath = config.services.media-stack.dataDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/sonarr";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [{
            hostPort = config.services.media-stack.services.sonarr.port;
            containerPort = 8989;
          }];
          
          nixosConfig = {
            services.sonarr = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };
            
            systemd.services.sonarr.serviceConfig = {
              UMask = "0002";
            };
            
            users.users.sonarr = {
              isSystemUser = true;
              group = "media";
              extraGroups = [ "downloads" ];
              uid = 13101;
            };
            users.groups.media = {
              gid = 13000;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            
            system.stateVersion = "25.05";
          };
        };
        
        # Radarr container
        radarr = mkIf config.services.media-stack.services.radarr.enable {
          enable = true;
          
          bindMounts = {
            "/data" = {
              hostPath = config.services.media-stack.dataDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/radarr";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [{
            hostPort = config.services.media-stack.services.radarr.port;
            containerPort = 7878;
          }];
          
          nixosConfig = {
            services.radarr = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };
            
            systemd.services.radarr.serviceConfig = {
              UMask = "0002";
            };
            
            users.users.radarr = {
              isSystemUser = true;
              group = "media";
              extraGroups = [ "downloads" ];
              uid = 13102;
            };
            users.groups.media = {
              gid = 13000;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            
            system.stateVersion = "25.05";
          };
        };
        
        # Lidarr container
        lidarr = mkIf config.services.media-stack.services.lidarr.enable {
          enable = true;
          
          bindMounts = {
            "/data" = {
              hostPath = config.services.media-stack.dataDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/lidarr";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [{
            hostPort = config.services.media-stack.services.lidarr.port;
            containerPort = 8686;
          }];
          
          nixosConfig = {
            services.lidarr = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };
            
            users.users.lidarr = {
              isSystemUser = true;
              group = "media";
              extraGroups = [ "downloads" ];
              uid = 13103;
            };
            users.groups.media = {
              gid = 13000;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            
            system.stateVersion = "25.05";
          };
        };
        
        # Jellyfin container
        jellyfin = mkIf config.services.media-stack.services.jellyfin.enable {
          enable = true;

          bindMounts = {
            "/media" = {
              hostPath = "${config.services.media-stack.dataDir}/media";
              isReadOnly = true;
            };
            "/config" = {
              hostPath = "/var/lib/jellyfin";
              isReadOnly = false;
            };
          };

          forwardPorts = [{
            hostPort = config.services.media-stack.services.jellyfin.port;
            containerPort = 8096;
          }];

          nixosConfig = {
            services.jellyfin = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };

            users.users.jellyfin = {
              isSystemUser = true;
              group = "jellyfin";
              extraGroups = [ "media" "video" "render" ];
              uid = 13104;
            };
            users.groups.jellyfin = {
              gid = 13104;
            };
            users.groups.media = {
              gid = 13000;
            };

            # Hardware acceleration support
            hardware.graphics.enable = true;

            system.stateVersion = "25.05";
          };
        };

        # Emby container
        emby = mkIf config.services.media-stack.services.emby.enable {
          enable = true;

          bindMounts = {
            "/media" = {
              hostPath = "${config.services.media-stack.dataDir}/media";
              isReadOnly = true;
            };
            "/config" = {
              hostPath = "/var/lib/emby";
              isReadOnly = false;
            };
          };

          forwardPorts = [{
            hostPort = config.services.media-stack.services.emby.port;
            containerPort = 8920;
          }];

          nixosConfig = {
            services.emby = {
              enable = true;
              openFirewall = true;
              dataDir = "/config";
            };

            users.users.emby = {
              isSystemUser = true;
              group = "emby";
              extraGroups = [ "media" "video" "render" ];
              uid = 13105;
            };
            users.groups.emby = {
              gid = 13105;
            };
            users.groups.media = {
              gid = 13000;
            };

            # Hardware acceleration support
            hardware.graphics.enable = true;

            system.stateVersion = "25.05";
          };
        };
      };
    };

    # Create media group on host
    users.groups.media = {
      gid = 13000;
    };

    # Create necessary directories
    # Use numeric UIDs/GIDs since container users don't exist on host
    systemd.tmpfiles.rules = [
      "d /var/lib/sonarr 0755 13101 13000 -"
      "d /var/lib/radarr 0755 13102 13000 -"
      "d /var/lib/lidarr 0755 13103 13000 -"
      "d /var/lib/jellyfin 0755 13104 13104 -"
      "d /var/lib/emby 0755 13105 13105 -"
      "d ${config.services.media-stack.dataDir}/media 0775 root 13000 - -"
      "d ${config.services.media-stack.dataDir}/download 0775 root 13001 - -"
      "d /var/snapraid 0755 root root -"
    ];
  };
};
}
