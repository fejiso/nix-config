{ ... }: {
  # Desktop-ish system services: audio (pipewire), mDNS (avahi), printing
  # (cups), and location-based timezone. Extracted from the old monolithic
  # `default`. Imported by the `desktop` UI aspect, and added explicitly to the
  # current headless server hosts that ran these before the refactor (so their
  # behavior is preserved). Resource-constrained `embedded` boards omit it.
  flake.modules.nixos.desktop-services =
{ pkgs, ... }: {
  # Enable CUPS for printing
  services.printing = {
    enable = true;
    drivers = with pkgs; [ gutenprint hplip ];
  };

  # Enable network printer discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    # Support high sample rates, default to 192kHz if supported
    extraConfig.pipewire."92-high-sample-rate" = {
      "context.properties" = {
        "default.clock.rate" = 192000;
        "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
      };
    };
  };

  # Enable location services
  services.geoclue2.enable = true;

  # Automatically update timezone based on location
  services.automatic-timezoned.enable = true;
}
;
}
