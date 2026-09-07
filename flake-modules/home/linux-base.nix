{ ... }: {
  flake.modules.homeManager.linux-default = { pkgs, ... }: {
    home.packages = with pkgs; [
      lshw
      pciutils # lspci
      usbutils # lsusb
      nmon
      e2fsprogs # badblocks
    ];
  };
}
