{ ... }: {
  flake.modules.homeManager.kilocode =
# Kilo Code VS Code extension configuration
# Configures Kilo Code with OpenRouter and OpenCode Go providers
# API keys are managed via sops-nix and injected via activation script
{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.programs.kilocode;
  
  # Kilo Code configuration
  kiloConfig = {
    # Provider configurations
    provider = {
      openrouter = {
        models = {
          "anthropic/claude-sonnet-4-20250514" = {
            options.transforms = [ "middle-out" ];
          };
          "openai/gpt-4o" = {};
          "google/gemini-pro-1.5" = {};
        };
      };
      opencode-go = {
        models = {
          "deepseek-v4-pro" = {};
          "qwen3.7-max" = {};
        };
      };
    };
    
    # UI settings
    auto_collapse_reasoning = true;
    terminal_command_display = true;
    
    # Experimental features
    experimental = {
      batch_tool = true;
      codebase_search = true;
    };
  };
  
  # Convert to JSONC (JSON with comments)
  kiloConfigJson = builtins.toJSON kiloConfig;
  
in {
  options.programs.kilocode = {
    enable = mkEnableOption "Kilo Code VS Code extension configuration";
  };

  config = mkIf cfg.enable {
    # Create Kilo Code config directory
    home.file.".config/kilo".source = pkgs.runCommand "kilo-config" {} ''
      mkdir -p $out
      
      # Write main config file
      cat > $out/kilo.jsonc << 'EOF'
{
  "$schema": "https://app.kilo.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "anthropic/claude-sonnet-4-20250514": {
          "options": {
            "transforms": ["middle-out"]
          }
        },
        "openai/gpt-4o": {},
        "google/gemini-pro-1.5": {}
      }
    },
    "opencode-go": {
      "models": {
        "deepseek-v4-pro": {},
        "qwen3.7-max": {}
      }
    }
  },
  "auto_collapse_reasoning": true,
  "terminal_command_display": true,
  "experimental": {
    "batch_tool": true,
    "codebase_search": true
  }
}
EOF
    '';

    # Activation script to configure Kilo Code API keys
    # This reads the sops secrets and configures Kilo Code
    home.activation.kilocodeApiKeys = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Read API keys from sops secrets
      OPENROUTER_KEY=$(cat ${config.sops.secrets.openrouter-api-key.path} 2>/dev/null || echo "")
      OPENCODEGO_KEY=$(cat ${config.sops.secrets.opencodego-api-key.path} 2>/dev/null || echo "")
      
      # Create Kilo Code secrets config (if keys are available)
      if [ -n "$OPENROUTER_KEY" ] || [ -n "$OPENCODEGO_KEY" ]; then
        mkdir -p ${config.home.homeDirectory}/.config/kilo
        
        cat > ${config.home.homeDirectory}/.config/kilo/secrets.json << EOF
{
  "openrouter_api_key": "$OPENROUTER_KEY",
  "opencodego_api_key": "$OPENCODEGO_KEY"
}
EOF
        chmod 600 ${config.home.homeDirectory}/.config/kilo/secrets.json
      fi
    '';

    # VS Code extension installation hint
    # Note: VS Code extensions need to be installed manually or via vscode-with-extensions
    home.packages = with pkgs; [
      # Add a helper script to install the extension
      (writeShellScriptBin "install-kilocode" ''
        echo "Installing Kilo Code extension..."
        code --install-extension kilocode.Kilo-Code
        echo "Kilo Code installed successfully!"
        echo ""
        echo "API keys have been configured via sops-nix."
        echo "Open VS Code and Kilo Code should automatically detect them."
      '')
    ];
  };
}
;
}
