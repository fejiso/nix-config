# Close-to-mainline kernel for the Xiaomi Mi A1 (tissot), from the
# msm8953-mainline project (the same tree postmarketOS'
# linux-postmarketos-qcom-msm8953 builds). The full config is vendored
# verbatim from pmaports (config-postmarketos-qcom-msm8953.aarch64);
# mobile-nixos' kernel-config module layers NixOS requirements on top.
{ mobile-nixos
, fetchFromGitHub
, python3
, ...
}:

mobile-nixos.kernel-builder {
  version = "6.11.1";
  configfile = ./config.aarch64;

  # msm DRM register-header generation runs a python script.
  nativeBuildInputs = [ python3 ];

  src = fetchFromGitHub {
    owner = "msm8953-mainline";
    repo = "linux";
    rev = "v6.11.1-r0";
    hash = "sha256-RHs73cqeZtgp35sbO93BeRIPrfE5UGrEHurjqUS2ROA=";
  };

  isModular = true;
}
