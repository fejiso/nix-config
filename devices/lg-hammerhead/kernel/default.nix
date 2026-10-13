# Close-to-mainline kernel for the Nexus 5 (hammerhead), from the
# msm8974-mainline project (the same tree postmarketOS'
# linux-postmarketos-qcom-msm8974 builds). The full config is vendored
# verbatim from pmaports (config-postmarketos-qcom-msm8974.armv7);
# mobile-nixos' kernel-config module layers NixOS requirements on top.
{ mobile-nixos
, fetchFromGitHub
, python3
, ...
}:

mobile-nixos.kernel-builder {
  version = "6.11.4";
  configfile = ./config.armv7l;

  # msm DRM register-header generation runs a python script.
  nativeBuildInputs = [ python3 ];

  src = fetchFromGitHub {
    owner = "msm8974-mainline";
    repo = "linux";
    rev = "v6.11.4-msm8974";
    hash = "sha256-x/PKkBwyAZQaoppJz7G5lUKXip4ggmuV4A2iLAPctLI=";
  };

  isModular = true;
}
