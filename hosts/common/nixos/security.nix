# Security configuration
{
  config,
  lib,
  ...
}: {
  # Enable sudo
  security.sudo.enable = true;
  
  # Polkit
  security.polkit.enable = true;
  
  # PAM configuration
  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };
}
