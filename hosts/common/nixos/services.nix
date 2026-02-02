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
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UseDns = false;
    };
  };

  # Disable NixOS SSH agent - GPG agent handles SSH via enableSshSupport
  programs.ssh.startAgent = false;

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

    # Support high sample rates, default to 192kHz if supported
    extraConfig.pipewire."92-high-sample-rate" = {
      "context.properties" = {
        "default.clock.rate" = 192000;
        "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
      };
    };
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
      [[rothbard_RNS_transport_ZA_ygg]]
        type = TCPClientInterface
        enabled = true
        target_host = 200:73eb:2e4:14be:aac7:90b3:784b:71a3
        target_port = 4242
      [[0rbit-yggdrasil]]
        type = TCPClientInterface
        enabled = true
        target_host = 200:978c:6347:8b49:f73e:ac69:daa:f71a
        target_port = 4242
      [[Int32 Pi(Ygg)]]
        type = TCPClientInterface
        enabled = true
        target_host = 200:b55c:7e7a:80fe:9e32:cded:55d2:91
        target_port = 4242

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
      [[RNS Testnet I2P Hub A]]
        type = I2PInterface
        enabled = yes
        peers = mrwqlsioq4hoo2lmeeud7dkfscnm7yxak7dmiyvsrnpfag3z5tsq.b32.i2p


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

      [[acehoss]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.acehoss.net
        target_port = 4242

      [[Beleth RNS Hub]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.beleth.net
        target_port = 4242

      [[FireZen]]
        type = TCPClientInterface
        enabled = yes
        target_host = firezen.com
        target_port = 4242

      [[g00n.cloud Hub]]
        type = TCPClientInterface
        enabled = yes
        target_host = dfw.us.g00n.cloud
        target_port = 6969

      [[interloper node]]
        type = TCPClientInterface
        enabled = yes
        target_host = intr.cx
        target_port = 4242

      [[Jon's Node]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.jlamothe.net
        target_port = 4242

      [[mobilefabrik TCP]]
        type = TCPClientInterface
        enabled = yes
        target_host = phantom.mobilefabrik.com
        target_port = 4242

      [[noDNS1]]
        type = TCPClientInterface
        enabled = yes
        target_host = 202.61.243.41
        target_port = 4965

      [[noDNS2]]
        type = TCPClientInterface
        enabled = yes
        target_host = 193.26.158.230
        target_port = 4965

      [[NomadNode SEAsia TCP]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.jaykayenn.net
        target_port = 4242

      [[ON6ZQ]]
        type = TCPClientInterface
        enabled = yes
        target_host = reticulum.on6zq.be
        target_port = 4965

      [[0rbit-Net]]
        type = TCPClientInterface
        enabled = yes
        target_host = 93.95.227.8
        target_port = 49952

      [[Quad4 TCP Node 1]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.quad4.io
        target_port = 4242

      [[Quad4 TCP Node 2]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns2.quad4.io
        target_port = 4242

      [[Quortal TCP Node]]
        type = TCPClientInterface
        enabled = yes
        target_host = reticulum.qortal.link
        target_port = 4242

      [[RNS.net.china]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.net.cn
        target_port = 4242

      [[RNS.net.in & RNS.in.net]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.net.in   # Domains rns.net.in and rns.in.net resolve to the same IP address; either can be used.
        target_port = 4242

      [[R-Net TCP]]
        type = TCPClientInterface
        enabled = yes
        target_host = istanbul.reserve.network
        target_port = 9034

      [[RNS bnZ-NODE01]]
        type = TCPClientInterface
        enabled = yes
        target_host = node01.rns.bnz.se
        target_port = 4242

      [[RNS COMSEC-RD]]
        type = TCPClientInterface
        enabled = yes
        target_host = 80.78.23.249
        target_port = 4242

      [[RNS HAM RADIO]]
        type = TCPClientInterface
        enabled = yes
        target_host = 135.125.238.229
        target_port = 4242

      [[RNS Testnet StoppedCold]]
        type = TCPClientInterface
        enabled = yes
        target_host = rns.stoppedcold.com
        target_port = 4242

      [[RNS_Transport_US-East]]
        type = TCPClientInterface
        enabled = yes
        target_host = 45.77.109.86
        target_port = 4965

      [[rtclm.de]]
        type = TCPClientInterface
        enabled = yes
        target_host = rtclm.de
        target_port = 4242

      [[SparkN0de]]
        type = TCPClientInterface
        enabled = yes
        target_host = aspark.uber.space
        target_port = 44860

      [[Sydney RNS]]
        type = TCPClientInterface
        enabled = yes
        target_host = sydney.reticulum.au
        target_port = 4242

      [[Tidudanka.com]]
        type = TCPClientInterface
        enabled = yes
        target_host = reticulum.tidudanka.com
        target_port = 37500

  '';

  # Reticulum ports
  networking.firewall.allowedTCPPorts = [ 4242 ];  # TCP server
  networking.firewall.allowedUDPPorts = [ 29716 42671 ]; # AutoInterface multicast discovery


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
      ExecStart = "${pkgs.python3Packages.lxmf}/bin/lxmd -p -s --config /etc/lxmf";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # LXMF config
  environment.etc."lxmf/config".text = ''
    [propagation]
    enable_node = yes
    node_name = ${hostname}
    announce_at_start = yes
    announce_interval = 360
    autopeer = yes
    message_storage_limit = 1024

    [lxmf]
    display_name = ${hostname}
    announce_at_start = yes
  '';

  # iperf3 server listening on wt0 interface for network performance testing
  systemd.services.iperf3-wt0 = {
    description = "iperf3 network performance server on wt0";
    after = [ "network-online.target" "sys-subsystem-net-devices-wt0.device" ];
    wants = [ "network-online.target" ];
    bindsTo = [ "sys-subsystem-net-devices-wt0.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 pkgs.gawk ];
    script = ''
      IP=$(ip -4 addr show wt0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
      if [ -n "$IP" ]; then
        exec ${pkgs.iperf3}/bin/iperf3 -s -B "$IP"
      else
        echo "Could not get IP for wt0 interface"
        exit 1
      fi
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10";
    };
  };

  # iperf3 port (only on wt0 via binding, but firewall needs to allow it)
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 5201 ];

  # Btrfs automatic scrubbing - safe no-op on non-btrfs hosts
  services.btrfs.autoScrub.enable = true;

}
