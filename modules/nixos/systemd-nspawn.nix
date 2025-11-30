# systemd-nspawn container module for isolating services
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
  options.services.nspawn-containers = {
    enable = mkEnableOption "systemd-nspawn container services";
    
    containers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this container";
          
          nixosConfig = mkOption {
            type = types.attrs;
            description = "NixOS configuration for the container";
          };
          
          bindMounts = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                hostPath = mkOption {
                  type = types.str;
                  description = "Path on the host";
                };
                isReadOnly = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether the mount is read-only";
                };
              };
            });
            default = {};
            description = "Bind mounts from host to container";
          };
          
          forwardPorts = mkOption {
            type = types.listOf (types.submodule {
              options = {
                hostPort = mkOption {
                  type = types.port;
                  description = "Port on the host";
                };
                containerPort = mkOption {
                  type = types.port;
                  description = "Port in the container";
                };
                protocol = mkOption {
                  type = types.enum [ "tcp" "udp" ];
                  default = "tcp";
                  description = "Protocol to forward";
                };
              };
            });
            default = [];
            description = "Port forwards from host to container";
          };
          
          privateNetwork = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to use private networking";
          };
          
          autoStart = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to start the container automatically";
          };
        };
      });
      default = {};
      description = "systemd-nspawn containers to create";
    };
  };

  config = mkIf config.services.nspawn-containers.enable {
    # Enable systemd-nspawn
    systemd.additionalUpstreamSystemUnits = [ "systemd-nspawn@.service" ];
    
    # Create containers
    containers = mapAttrs (name: containerConfig: {
      inherit (containerConfig) autoStart privateNetwork bindMounts forwardPorts;
      
      config = { config, pkgs, ... }: containerConfig.nixosConfig // {
        # Minimal container configuration
        boot.isContainer = true;
        networking.useHostResolvConf = mkForce false;
        services.resolved.enable = true;
        
        # Basic system packages for containers
        environment.systemPackages = with pkgs; [
          curl
          htop
          nano
        ];
        
        # Ensure proper logging in containers
        services.journald.extraConfig = ''
          Storage=volatile
          ForwardToConsole=no
        '';
      };
    }) (filterAttrs (_: container: container.enable) config.services.nspawn-containers.containers);
    
    # Enable container networking
    networking.nat = mkIf (any (c: c.enable && c.privateNetwork) (attrValues config.services.nspawn-containers.containers)) {
      enable = true;
      internalInterfaces = ["ve-+"];
    };
  };
}