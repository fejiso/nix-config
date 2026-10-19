# NetBird Setup Guide

This configuration adds NetBird VPN to all NixOS hosts with the setup key securely stored using sops-nix.

## Initial Setup

1. **In the private repo** (`~/dev/nix-config-private`), edit the encrypted
   secrets file (its `.sops.yaml` drives recipients):
   ```bash
   cd ~/dev/nix-config-private
   sops secrets/netbird.yaml
   ```

2. **Push, then update the input in this repo:**
   ```bash
   git -C ~/dev/nix-config-private commit -am "Update netbird setup key" && git -C ~/dev/nix-config-private push
   nix flake update private
   ```

3. **Commit the flake.lock change:**
   ```bash
   git add flake.lock
   git commit -m "Update private input (netbird)"
   ```

## Deployment

Deploy to your NixOS hosts:

```bash
# For each host (any name from `nixosConfigurations`, e.g.)
sudo nixos-rebuild switch --flake .#elitedex
sudo nixos-rebuild switch --flake .#lenovix
sudo nixos-rebuild switch --flake .#a8
```

## What's Configured

- **NetBird service**: Automatically starts on boot
- **Firewall rules**: Opens UDP port 51820 and trusts the NetBird interface
- **Auto-setup**: Automatically connects using the encrypted setup key
- **Secrets management**: Setup key is encrypted with sops and only readable by the netbird user

## Verification

Check NetBird status on each host:
```bash
sudo netbird status
```

## Troubleshooting

- **Check service status**: `systemctl status netbird`
- **Check setup service**: `systemctl status netbird-setup`
- **View logs**: `journalctl -u netbird -f`
- **Manual setup**: If auto-setup fails, you can manually run:
  ```bash
  sudo netbird up --setup-key "$(sudo cat /run/secrets/netbird_setup_key)"
  ```

## Security Notes

- The setup key is encrypted with age and only accessible to the netbird user
- Each host will automatically join the NetBird network on first boot
- The age private key should be backed up securely
- Consider rotating the NetBird setup key periodically
