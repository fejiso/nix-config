# Common services configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Enable SSH agent
  programs.ssh.startAgent = true;

  # Enable CUPS for printing
  services.printing.enable = true;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable location services
  services.geoclue2.enable = true;

  # Automatically update timezone based on location
  services.automatic-timezoned.enable = true;

}
