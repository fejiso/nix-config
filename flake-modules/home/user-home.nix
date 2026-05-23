{ lib, ... }: {
  flake.modules.homeManager.default = {
    home = {
      username = lib.mkDefault "z-247";
      homeDirectory = lib.mkDefault "/home/z-247";
    };
  };
}
