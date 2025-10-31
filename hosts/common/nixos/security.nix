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
  
  # Audio realtime permissions
  security.rtkit.enable = true;
  security.pam.loginLimits = [
    {
      domain = "@audio";
      type = "-";
      item = "rtprio";
      value = "95";
    }
    {
      domain = "@audio";
      type = "-";
      item = "memlock";
      value = "unlimited";
    }
  ];
}
