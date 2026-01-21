# Common services configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Enable SSH agent
  programs.ssh.startAgent = true;

  # Enable CUPS for printing
  services.printing = {
    enable = true;
    drivers = with pkgs; [ gutenprint hplip ];
  };

  # Enable network printer discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable location services
  services.geoclue2.enable = true;

  # Automatically update timezone based on location
  services.automatic-timezoned.enable = true;

  # Yggdrasil mesh networking
  services.yggdrasil = {
    enable = true;
    persistentKeys = true;
    settings = {
      Peers = [
        # Public peers - add more from https://publicpeers.neilalexander.dev/
        "tls://ygg.mkg20001.io:443"
        "tls://ygg-uplink.thingylabs.io:443"
      ];
    };
  };

  # I2P daemon
  services.i2pd = {
    enable = true;
    ifname4 = "eth0";
    address = "0.0.0.0";
    proto = {
      http.enable = true;
      socksProxy.enable = true;
      httpProxy.enable = true;
    };
  };

  # Reticulum Network Stack daemon
  systemd.services.rnsd = {
    description = "Reticulum Network Stack Daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3Packages.rns}/bin/rnsd --service";
      Restart = "always";
      RuntimeMaxSec = "15min";
    };
  };

}
