{ config, ... }: {
  flake.modules.homeManager.gpg =
{
  imports = [ config.flake.modules.homeManager.gpg-agent ];

  programs.gpg = {
    enable = true;
    settings = {
      use-agent = true;
    };
    scdaemonSettings = {
      "card-timeout" = "5";
      "pcsc-shared" = true;
    };
  };
}
;
}
