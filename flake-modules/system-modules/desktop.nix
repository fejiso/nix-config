{ ... }: {
  flake.modules.nixos.desktop =
# Common desktop configuration shared between desktop systems
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  # Window managers
  programs.niri.enable = true;

  # Noctalia services: battery, bluetooth, power profiles
  services.upower.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = lib.mkDefault true;

  # DLNA audio bridge via pa-dlna (home module services.boseSoundtouch):
  #  - TCP 8092: pa-dlna HTTP server the renderer pulls the audio stream from.
  #  - UDP 1901: fixed port for SSDP M-SEARCH responses (unicast from the device;
  #    the stateful firewall won't tie them to the multicast query, so it must be
  #    explicitly open or discovery silently finds nothing).
  #  - UDP 1900: SSDP NOTIFY announcements.
  networking.firewall.allowedTCPPorts = [ 8092 ];
  networking.firewall.allowedUDPPorts = [ 1900 1901 ];

  # Gaming
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # MeshChatX (meshchatx): all-in-one Reticulum/LXMF client. Run as the official
  # container — a native nix package is impractical (needs rns 1.3.5 / lxmf 1.0.1
  # newer than nixpkgs, plus lxst/pycodec2/lxmfy, a pnpm frontend build and native
  # libs). The image's default command serves the web UI headless on port 8000;
  # we publish it on localhost only and provide a launcher that opens the browser.
  # The in-container user is UID 1000, matching z-247, so /var/lib/meshchatx data
  # is owned by the user. (Serial/LoRa/Bluetooth need device passthrough — add
  # `extraOptions = [ "--device=..." ]` / dbus socket if you use local hardware.)
  virtualisation.podman.enable = lib.mkDefault true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers.meshchatx = {
      # Fully-qualified: the autoupdate label below rejects short names.
      image = "docker.io/quad4io/meshchatx:latest";
      autoStart = true;
      ports = [ "127.0.0.1:48000:8000" ];
      volumes = [ "/var/lib/meshchatx:/config" ];
      # Default CMD serves HTTPS with a self-signed cert; add --no-https so the
      # localhost-only UI is plain HTTP (no cert warning). Reproduces the image's
      # default command since setting cmd replaces it.
      cmd = [
        "meshchatx"
        "--host=0.0.0.0"
        "--reticulum-config-dir=/config/.reticulum"
        "--storage-dir=/config/.reticulum-meshchatx"
        "--headless"
        "--no-https"
      ];
      # Let the daily podman-auto-update timer (system/podman.nix) refresh it.
      labels."io.containers.autoupdate" = "registry";
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/meshchatx 0755 1000 100 -"
  ];

  # Desktop services
  services.pcscd.enable = true;  # Smart card daemon for hardware tokens
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.udev.extraRules = ''
    # TOKEN2 FIDO2 Security Key - give plugdev group access
    SUBSYSTEM=="usb", ATTR{idVendor}=="349e", ATTR{idProduct}=="0026", GROUP="plugdev", MODE="0664"
  '';

  # greetd + tuigreet: minimal Wayland greeter that launches the niri session
  # directly. Replaces GDM — its GNOME-Shell Wayland greeter fails to start on
  # the nvidia desktop (greeter session dies before the compositor comes up),
  # and niri needs no full desktop manager.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${config.programs.niri.package}/bin/niri-session";
      user = "greeter";
    };
  };

  # The greeter user needs GPU access for the Wayland compositor (niri).
  # The nixpkgs greetd module creates the user but doesn't add video group.
  users.users.greeter.extraGroups = [ "video" "input" ];

services.desktopManager.gnome.enable = lib.mkIf config.services.xserver.enable false;
  
  # Disable GNOME GCR SSH agent to avoid conflict
  services.gnome.gcr-ssh-agent.enable = false;

  # User groups and configuration
  users.groups.plugdev = {};
  users.users.z-247.extraGroups = [ "plugdev" "media-services" ];
  users.users.z-247.packages = with pkgs; [
    amazon-q-cli
    tree
  ];

  # Desktop system packages
  environment.systemPackages = with pkgs; [
    wget
    firefox
    chromium
    git
    alacritty
    pciutils
    usbutils
    pcsclite
    pcsc-tools
    spotify
    poppler-utils

    # meshchatx: open the MeshChatX web UI (served by the container above).
    (writeShellScriptBin "meshchatx" ''
      exec ${xdg-utils}/bin/xdg-open "http://localhost:48000"
    '')
    (makeDesktopItem {
      name = "meshchatx";
      desktopName = "MeshChatX";
      comment = "All-in-one Reticulum / LXMF mesh client";
      exec = "xdg-open http://localhost:48000";
      terminal = false;
      categories = [ "Network" "InstantMessaging" ];
    })
  ];

  # SSH configuration for desktop access
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = lib.mkForce true;
      X11Forwarding = false;
      PermitRootLogin = lib.mkForce "yes";
    };
  };

  # Networking
  networking.networkmanager.enable = true;

  # Localization
  # time.timeZone is managed by automatic-timezoned service
  i18n.defaultLocale = "en_IE.UTF-8";
}
;
}
