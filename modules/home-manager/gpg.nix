{
  imports = [ ./gpg-agent.nix ];

  programs.gpg = {
    enable = true;
    settings = {
      # Allow loopback pinentry for automated tools like sops-nix
      use-agent = true;
      pinentry-mode = "loopback";
    };
    scdaemonSettings = {
      "card-timeout" = "5";
      "disable-ccid" = true;
      "pcsc-shared" = true;
    };
  };
}
