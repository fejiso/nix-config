{
  programs.gpg = {
    enable = true;
    scdaemonSettings = {
      "card-timeout" = "5";
      "disable-ccid" = true;
      "pcsc-shared" = true;
    };
  };
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    # Use pinentry-gnome3 for GUI, or pkgs.pinentry-curses for CLI
    pinentryPackage = pkgs.pinentry-gnome3;
  };
}