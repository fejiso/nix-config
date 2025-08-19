{
  pkgs, ...
}: {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-all;
    extraConfig = "pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses";
  };
}
