{ lib, ... }: {
  options.flake.images = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
    description = "SD card images for ARM hosts.";
  };
}
