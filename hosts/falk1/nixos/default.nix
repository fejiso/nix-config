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
  ];

  networking.hostName = "falk1";

  # Lightweight server profile (systemd-networkd, volatile journald, zram, no docs/UI)
  embedded.enable = true;

  # Cloud VPS: no Bluetooth hardware
  hardware.bluetooth.enable = lib.mkForce false;

  # Hetzner Cloud x86_64 boots via Legacy BIOS (GPT + 1M BIOS boot partition sda14):
  # disable base.nix's default systemd-boot and install GRUB to /dev/sda.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # Allow root SSH login for Colmena deployments (key-only via base.nix / users.nix)
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

  # Static IPv6 from secrets/network.yaml (sops).
  # Prior to falk1's host key being added to .sops.yaml, 10-embedded-wired.network
  # brings up IPv4 DHCP automatically; once sops decrypts this template, 05-falk1-wired
  # takes precedence and configures both DHCPv4 and static IPv6.
  sops.secrets.falk1-ipv6 = {
    sopsFile = "${inputs.private}/secrets/network.yaml";
    key = "falk1/ipv6";
  };

  sops.templates."05-falk1-wired.network" = {
    path = "/run/systemd/network/05-falk1-wired.network";
    owner = "systemd-network";
    mode = "0440";
    content = ''
      [Match]
      Name=en* eth*

      [Network]
      DHCP=ipv4
      Address=${config.sops.placeholder.falk1-ipv6}

      [Route]
      Gateway=fe80::1

      [Link]
      RequiredForOnline=routable
    '';
  };

  systemd.services.falk1-network-reload = {
    description = "Reload systemd-networkd with sops static IPv6 config";
    after = [ "sops-nix.service" "systemd-networkd.service" ];
    wants = [ "systemd-networkd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -f /run/systemd/network/05-falk1-wired.network ]; then
        ${pkgs.systemd}/bin/networkctl reload
        for iface in $(${pkgs.iproute2}/bin/ip -o link show | ${pkgs.gawk}/bin/awk -F': ' '$2 ~ /^(en|eth)/ {print $2}'); do
          ${pkgs.systemd}/bin/networkctl reconfigure "$iface" || true
        done
      fi
    '';
  };

  system.stateVersion = "26.05";
}
