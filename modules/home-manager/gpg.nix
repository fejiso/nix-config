{
  imports = [ ./gpg-agent.nix ];

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
