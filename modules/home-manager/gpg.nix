{
  imports = [ ./gpg-agent.nix ];

  programs.gpg = {
    enable = true;
    scdaemonSettings = {
      "card-timeout" = "5";
      "disable-ccid" = true;
      "pcsc-shared" = true;
    };
  };
}
