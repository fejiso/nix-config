# Hispanas specific NixOS configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    # Add appropriate nixos-hardware module for your specific Lenovo model
    # inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-carbon-gen11
  ];

  # Host-specific networking
  networking.hostName = "hispanas";

  # Intel Core i3-3220 (Ivy Bridge — SSE4.2 + POPCNT + AVX + F16C, no AVX2)
  hardware.cpu.tune = {
    cpu = "ivybridge";
    group = "x86-64-v2";
  };

  # bcachefs support (kernel module + bcachefs-tools)
  hardware.bcachefs-support.enable = true;

  # TESTBED for the stale needs_reconcile fix (see bcachefs-patch.md):
  # bch2_stripe_repair() early-returns on non-degraded stripes without
  # clearing needs_reconcile, so stripes flagged during a transient device
  # state spin in reconcile_hipri forever (ret==0, no IO, no state change).
  # Applied ONLY on hispanas; butthead keeps vanilla 1.39.5 until proven.
  # Drop when fixed upstream.
  nixpkgs.overlays = [
    (_final: prev: {
      bcachefs-tools = prev.bcachefs-tools.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../../../overlays/patches/bcachefs-stripe-repair-clear-stale-needs-reconcile.patch
        ];
      });
    })
  ];

  # Ralink RT5390R (rt2800pci) firmware is notoriously slow (<1Mbps) under
  # default settings. Two well-known fixes:
  #   1. Disable Wi-Fi power management (NetworkManager defaults it on).
  #   2. Disable hardware crypto offload (driver bug; CPU handles it faster).
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = ''
    options rt2800pci nohwcrypt=1
  '';

  # Emilia user account
  users.users.emilia = {
    isNormalUser = true;
    description = "Emilia";
    extraGroups = [ "video" "audio" "networkmanager" ];
    packages = with pkgs; [
      telegram-desktop
    ];
  };

  # Support Spanish locale
  i18n.supportedLocales = [ "es_ES.UTF-8/UTF-8" "en_IE.UTF-8/UTF-8" ];

  # Set Spanish locale for emilia only
  systemd.tmpfiles.rules = [
    "d /home/emilia/.config/environment.d 0755 emilia users -"
  ];
  environment.etc."skel/.config/environment.d/locale.conf".text = "";
  system.activationScripts.emiliaLocale = ''
    mkdir -p /home/emilia/.config/environment.d
    echo 'LANG=es_ES.UTF-8' > /home/emilia/.config/environment.d/locale.conf
    chown -R emilia:users /home/emilia/.config/environment.d
  '';

  # Cinnamon desktop (Linux Mint style)
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.cinnamon.enable = true;
  };

  # Disable GNOME's ssh-agent (conflicts with programs.ssh.startAgent)
  services.gnome.gnome-keyring.enable = lib.mkForce false;
  services.gnome.gcr-ssh-agent.enable = false;

  # Autologin for emilia
  services.displayManager.autoLogin = {
    enable = true;
    user = "emilia";
  };

  # Autostart telegram-desktop
  environment.etc."xdg/autostart/telegram.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Telegram
    Exec=${pkgs.telegram-desktop}/bin/Telegram
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    X-Cinnamon-Autostart-enabled=true
  '';

  # Open firewall for webcam stream
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # Export local bcachefs drive (/mnt/user) via NFS over NetBird (wt0 only)
  services.nfs.server = {
    enable = true;
    mountdPort = 20048;
    statdPort = 4000;
    lockdPort = 4001;
    exports = ''
      /mnt/user 100.107.0.0/16(rw,sync,no_subtree_check,no_root_squash,fsid=1)
    '';
  };

  systemd.services.nfs-server = {
    after = [ "mnt-user.mount" ];
    wants = [ "mnt-user.mount" ];
  };

  networking.firewall.interfaces.wt0 = {
    allowedTCPPorts = [ 2049 111 20048 4000 4001 ];
    allowedUDPPorts = [ 2049 111 20048 4000 4001 ];
  };

  # Export attached pre-1.0 TTGO LoRa32 MeshCore kiss_modem over NetBird (:7620 on wt0)
  services.kiss-modem.enable = true;

  # System state version
  system.stateVersion = "25.05";
}
