{ ... }: {
  flake.modules.nixos.download-services =
# Download services configuration for containers
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
  options.services.download-stack = {
    enable = mkEnableOption "download stack services";
    
    downloadDir = mkOption {
      type = types.str;
      default = "/mnt/storage/downloads";
      description = "Directory for downloads";
    };
    
    services = {
      qbittorrent = {
        enable = mkEnableOption "qBittorrent BitTorrent client";
        port = mkOption {
          type = types.port;
          default = 8080;
          description = "Port for qBittorrent web interface";
        };
      };
      
      sabnzbd = {
        enable = mkEnableOption "SABnzbd Usenet client";
        port = mkOption {
          type = types.port;
          default = 8081;
          description = "Port for SABnzbd web interface";
        };
      };
      
      deluge = {
        enable = mkEnableOption "Deluge BitTorrent client";
        port = mkOption {
          type = types.port;
          default = 8112;
          description = "Port for Deluge web interface";
        };
      };
    };
  };

  config = mkIf config.services.download-stack.enable {
    services.nspawn-containers = {
      enable = true;
      
      containers = {
        # qBittorrent container
        qbittorrent = mkIf config.services.download-stack.services.qbittorrent.enable {
          enable = true;
          
          bindMounts = {
            "/downloads" = {
              hostPath = config.services.download-stack.downloadDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/qbittorrent";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [{
            hostPort = config.services.download-stack.services.qbittorrent.port;
            containerPort = 8080;
          }];
          
          nixosConfig = {
            services.qbittorrent = {
              enable = true;
              dataDir = "/config";
              port = 8080;
              openFirewall = true;
            };
            
            users.users.qbittorrent = {
              isSystemUser = true;
              group = "downloads";
              extraGroups = [ "media" ];
              uid = 13001;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            users.groups.media.gid = 13000;
            
            system.stateVersion = "25.05";
          };
        };
        
        # SABnzbd container
        sabnzbd = mkIf config.services.download-stack.services.sabnzbd.enable {
          enable = true;
          
          bindMounts = {
            "/downloads" = {
              hostPath = config.services.download-stack.downloadDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/sabnzbd";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [{
            hostPort = config.services.download-stack.services.sabnzbd.port;
            containerPort = 8080;
          }];
          
          nixosConfig = {
            services.sabnzbd = {
              enable = true;
              configFile = "/config/sabnzbd.ini";
            };
            
            users.users.sabnzbd = {
              isSystemUser = true;
              group = "downloads";
              extraGroups = [ "media" ];
              uid = 13002;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            users.groups.media.gid = 13000;
            
            system.stateVersion = "25.05";
          };
        };
        
        # Deluge container
        deluge = mkIf config.services.download-stack.services.deluge.enable {
          enable = true;
          
          bindMounts = {
            "/downloads" = {
              hostPath = config.services.download-stack.downloadDir;
              isReadOnly = false;
            };
            "/config" = {
              hostPath = "/var/lib/deluge";
              isReadOnly = false;
            };
          };
          
          forwardPorts = [
            {
              hostPort = config.services.download-stack.services.deluge.port;
              containerPort = 8112;
            }
            {
              hostPort = 58846;
              containerPort = 58846;
            }
          ];
          
          nixosConfig = {
            services.deluge = {
              enable = true;
              web = {
                enable = true;
                port = 8112;
              };
            };
            
            users.users.deluge = {
              isSystemUser = true;
              group = "downloads";
              extraGroups = [ "media" ];
              uid = 13003;
            };
            users.groups.downloads = {
              gid = 13001;
            };
            users.groups.media.gid = 13000;
            
            networking.firewall.allowedTCPPorts = [ 8112 58846 ];
            
            system.stateVersion = "25.05";
          };
        };
      };
    };

    # Create download group and directories on host
    users.groups.downloads = {
      gid = 13001;
    };
    users.groups.media = {
      gid = 13000;
    };

    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/lib/qbittorrent 0755 13001 13001 -"
      "d /var/lib/sabnzbd 0755 13002 13001 -"
      "d /var/lib/deluge 0755 13003 13001 -"
      "d ${config.services.download-stack.downloadDir} 0775 root 13001 -"
    ];
  };
};
}
