{ ... }: {
  flake.modules.nixos.haos-vm =
# Home Assistant OS in a QEMU/KVM VM (downloads the official HAOS image on
# first start). Web UI forwarded to host :8123. Extracted from
# hosts/butthead/nixos.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.haos-vm;
in
{
  options.services.haos-vm = {
    enable = mkEnableOption "Home Assistant OS VM";
  };

  config = mkIf cfg.enable {
    systemd.services.haos-vm = {
      description = "Home Assistant OS VM";
      after = [ "network.target" "libvirtd.service" ];
      wants = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.qemu_kvm pkgs.curl pkgs.xz ];

      unitConfig = {
        StartLimitIntervalSec = 0;
      };

      preStart = ''
        # Create HAOS directory if it doesn't exist
        mkdir -p /var/lib/haos

        # Download HAOS image if it doesn't exist
        if [ ! -f /var/lib/haos/haos.qcow2 ]; then
          echo "Downloading Home Assistant OS image..."
          ${pkgs.curl}/bin/curl -L -o /var/lib/haos/haos.qcow2.xz \
            https://github.com/home-assistant/operating-system/releases/download/13.2/haos_ova-13.2.qcow2.xz
          ${pkgs.xz}/bin/unxz /var/lib/haos/haos.qcow2.xz

          # Convert to compressed qcow2 and resize to 64GB
          ${pkgs.qemu_kvm}/bin/qemu-img convert -O qcow2 -c /var/lib/haos/haos.qcow2 /var/lib/haos/haos-compressed.qcow2
          mv /var/lib/haos/haos-compressed.qcow2 /var/lib/haos/haos.qcow2
          ${pkgs.qemu_kvm}/bin/qemu-img resize /var/lib/haos/haos.qcow2 64G
        fi
      '';

      serviceConfig = {
        Restart = "always";
        RestartSec = "15min";
        Type = "simple";

        ExecStart = ''
          ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
            -name haos \
            -machine type=q35,accel=kvm \
            -cpu host \
            -smp 2 \
            -m 4096 \
            -nographic \
            -drive file=/var/lib/haos/haos.qcow2,if=virtio,cache=writethrough,discard=on \
            -netdev user,id=net0,hostfwd=tcp::8123-:8123 \
            -device virtio-net-pci,netdev=net0 \
            -serial mon:stdio \
            -bios ${pkgs.OVMF.fd}/FV/OVMF.fd
        '';
      };
    };
  };
}
;
}
