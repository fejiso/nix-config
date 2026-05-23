{ ... }: {
  flake.modules.homeManager.default = { lib, ... }: {
    programs.git = {
      settings.user.name = lib.mkDefault "Fernando Jiménez";
    };
  };
}
