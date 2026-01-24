# Common services configuration
{
  config,
  lib,
  pkgs,
  hostname,
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

  # Reticulum Network Stack daemon (shared for all users)
  systemd.services.rnsd = {
    description = "Reticulum Network Stack Daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3Packages.rns}/bin/rnsd --service --config /etc/reticulum";
      Restart = "always";
      RuntimeMaxSec = "15min";
    };
  };

  # Shared config directories
  systemd.tmpfiles.rules = [
    "d /etc/reticulum 0755 root root -"
    "d /var/run/reticulum 0777 root root -"
    "d /etc/lxmf 0755 root root -"
  ];

  # Reticulum config for shared access
  environment.etc."reticulum/config".text = ''
    [reticulum]
    enable_transport = True
    share_instance = Yes
    shared_instance_port = 37428
    instance_control_port = 37429
    node_name = ${hostname}

    [logging]
    loglevel = 4

    [interfaces]
      [[Default Interface]]
        type = AutoInterface
        enabled = Yes
        group_id = reticulum

      [[Yggdrasil Remote]]
        type = TCPClientInterface
        enabled = yes
        target_host = 201:5d78:af73:5caf:a4de:a79f:3278:71e5
        target_port = 4343

      # Public Reticulum TCP hubs (geographically distributed)
      [[RNS Dublin]]
        type = TCPClientInterface
        enabled = yes
        target_host = dublin.connect.reticulum.network
        target_port = 4965

      [[RNS Frankfurt]]
        type = TCPClientInterface
        enabled = yes
        target_host = frankfurt.connect.reticulum.network
        target_port = 5377

      [[RNS BetweenTheBorders]]
        type = TCPClientInterface
        enabled = yes
        target_host = betweentheborders.com
        target_port = 4242

      [[TCP Server]]
        type = TCPServerInterface
        enabled = yes
        listen_ip = 0.0.0.0
        listen_port = 4242

      # Netbird mesh peers
      [[Peer hierro]]
        type = TCPClientInterface
        enabled = yes
        target_host = hierro.netbird.cloud
        target_port = 4242

      [[Peer blacktop]]
        type = TCPClientInterface
        enabled = yes
        target_host = blacktop.netbird.cloud
        target_port = 4242

      [[Peer butthead]]
        type = TCPClientInterface
        enabled = yes
        target_host = butthead.netbird.cloud
        target_port = 4242
  '';

  # Reticulum ports
  networking.firewall.allowedTCPPorts = [ 4242 ];  # TCP server
  networking.firewall.allowedUDPPorts = [ 29716 ]; # AutoInterface multicast discovery


  # Environment variable so all apps use the shared Reticulum instance
  environment.variables.RNS_SHARED_INSTANCE = "Yes";

  # LXMF daemon for message propagation and node announcement
  systemd.services.lxmd = {
    description = "LXMF Propagation Daemon";
    after = [ "network.target" "rnsd.service" ];
    requires = [ "rnsd.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      RNS_SHARED_INSTANCE = "Yes";
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3Packages.lxmf}/bin/lxmd --config /etc/lxmf";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # LXMF config
  environment.etc."lxmf/config".text = ''
    [lxmf]
    display_name = ${hostname}
    announce_at_start = yes
    announce_interval = 360
    propagation_node = yes
    propagation_limit = 256
  '';


}
