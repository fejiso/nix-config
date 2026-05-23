{ lib, ... }: {
  options.flake.modules = {
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = ''
        NixOS module classes contributed by flake-parts modules. Each name is
        a deferred module that accumulates contributions from every file that
        writes to `flake.modules.nixos.<name>`. Hosts compose by importing
        `config.flake.modules.nixos.default` plus any opt-in features.
      '';
    };

    homeManager = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = "Home-manager module classes, same convention as `nixos`.";
    };
  };
}
