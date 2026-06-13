{ ... }: {
  flake.modules.homeManager.linux-default = { pkgs, ... }: {
    home.packages = with pkgs; [
      lshw
      pciutils
      e2fsprogs # badblocks
    ];
  };
}
