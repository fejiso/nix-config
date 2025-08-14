{ config, pkgs, ... }:

{
  programs.gpg = {
    enable = true;
    scdaemon.enable = true;
    scdaemon.settings = {
      "card-timeout" = 5;
      "disable-ccid" = true;
      "pcsc-shared" = true;
    };
    agent = {
      enable = true;
      enableSshSupport = true;
    };
  };
}