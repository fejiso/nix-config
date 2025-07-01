# NetBird Setup Guide

This configuration adds NetBird VPN to all NixOS hosts with the setup key securely stored using sops-nix.

## Initial Setup

1. **Generate age key and setup sops:**
   ```bash
   ./setup-sops.sh
   ```

2. **Encrypt the secrets file:**
   ```bash
   sops secrets/netbird.yaml
   ```
   This will open your editor to encrypt the file. The setup key `5A4D518F-CBCD-45A0-8454-7B747333A09B` is already in the file.

3. **Commit your changes:**
   ```bash
   git add .
   git commit -m "Add NetBird configuration with sops-encrypted setup key"
   ```

## Deployment

Deploy to your NixOS hosts:

```bash
# For each host
sudo nixos-rebuild switch --flake .#elitedx
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
