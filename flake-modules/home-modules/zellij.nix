{ ... }: {
  flake.modules.homeManager.zellij =
{ config, pkgs, ... }:

{
  programs.zellij.enable = true;

  home.file.".local/bin/zellij-agent-resurrect" = {
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import os
      import re
      import shlex
      import sys

      raw = os.environ.get("RESURRECT_COMMAND", "")
      if not raw.strip():
          sys.stdout.write(raw)
          sys.exit(0)

      try:
          tokens = shlex.split(raw)
      except ValueError:
          sys.stdout.write(raw)
          sys.exit(0)

      if not tokens:
          sys.stdout.write(raw)
          sys.exit(0)

      # Strip leading shell/interpreter wrapper (e.g. /nix/store/.../bash /.../bin/yolo-claude ...)
      if len(tokens) >= 2 and os.path.basename(tokens[0]) in ("bash", "sh", "fish", "zsh"):
          if os.path.basename(tokens[1]).startswith("yolo-"):
              tokens = tokens[1:]

      exe_base = os.path.basename(tokens[0])
      rest = tokens[1:]

      YOLO_WRAPPERS = {
          "yolo-claude",
          "yolo-agy",
          "yolo-opencode",
          "yolo-pi",
          "yolo-kimi",
          "yolo-codex",
      }

      if exe_base == "agy-resurrect":
          emit(["agy-resurrect"] + rest)

      def emit(argv: list[str]) -> None:
          sys.stdout.write(shlex.join(argv))
          sys.exit(0)

      # 1. yolo-* wrappers: normalize executable basename (survives Nix store GC)
      #    and ensure --resurrect is present.
      if exe_base in YOLO_WRAPPERS:
          if "--resurrect" not in rest:
              rest = ["--resurrect"] + rest
          emit([exe_base] + rest)

      # 2. Bare claude -> convert --session-id <uuid> to --resume <uuid>, else add --continue
      if exe_base == "claude":
          subcmds = {"agents", "auth", "doctor", "gateway", "install", "mcp", "plugin", "plugins", "setup-token", "update", "upgrade"}
          if rest and rest[0] in subcmds:
              sys.stdout.write(raw)
              sys.exit(0)
          has_resume = any(
              a in ("-c", "--continue", "-r", "--resume")
              or a.startswith("--resume=")
              for a in rest
          )
          if has_resume:
              emit(["claude"] + rest)
          out = []
          replaced_sid = False
          i = 0
          while i < len(rest):
              if rest[i] == "--session-id" and i + 1 < len(rest):
                  out.extend(["--resume", rest[i + 1]])
                  replaced_sid = True
                  i += 2
                  continue
              if rest[i].startswith("--session-id="):
                  out.extend(["--resume", rest[i].split("=", 1)[1]])
                  replaced_sid = True
                  i += 1
                  continue
              out.append(rest[i])
              i += 1
          if not replaced_sid:
              out = ["--continue"] + out
          emit(["claude"] + out)

      # 3. Bare opencode -> opencode --continue
      if exe_base == "opencode":
          subcmds = {"upgrade", "update", "uninstall", "acp", "api", "debug", "auth", "mcp", "plugin", "models", "stats", "run", "session", "service", "reload", "pair", "serve"}
          if rest and rest[0] in subcmds:
              sys.stdout.write(raw)
              sys.exit(0)
          has_resume = any(
              a in ("-c", "--continue", "-s", "--session")
              or a.startswith("--session=")
              for a in rest
          )
          if not has_resume:
              rest = ["--continue"] + rest
          emit(["opencode"] + rest)

      # 4. Bare agy -> agy-resurrect (uses exact conversation_id recorded by statusline.sh,
      #    falling back to agy --continue if Zellij died before turn 1 assigned an ID)
      if exe_base == "agy":
          subcmds = {"acp", "agent", "agents", "changelog", "help", "install", "mcp", "mic-serve", "models", "plugin", "plugins", "remote-control", "update"}
          if rest and rest[0] in subcmds:
              sys.stdout.write(raw)
              sys.exit(0)
          has_resume = any(
              a in ("-c", "--continue", "--conversation")
              or a.startswith("--conversation=")
              for a in rest
          )
          if has_resume:
              emit(["agy"] + rest)
          emit(["agy-resurrect"] + rest)

      # 5. Bare pi -> pi --continue
      if exe_base == "pi":
          subcmds = {"install", "remove", "uninstall", "update", "list", "config"}
          if rest and rest[0] in subcmds:
              sys.stdout.write(raw)
              sys.exit(0)
          has_resume = any(
              a in ("-c", "--continue", "-r", "--resume", "--session")
              or a.startswith("--session=")
              for a in rest
          )
          if not has_resume:
              rest = ["--continue"] + rest
          emit(["pi"] + rest)

      # 6. Bare kimi -> kimi --continue
      if exe_base == "kimi":
          subcmds = {"login", "logout", "term", "acp", "info", "export", "mcp", "plugin", "vis", "web"}
          if rest and rest[0] in subcmds:
              sys.stdout.write(raw)
              sys.exit(0)
          has_resume = any(
              a in ("--continue", "--session", "--resume")
              or a.startswith("--session=")
              or a.startswith("--resume=")
              for a in rest
          )
          if not has_resume:
              rest = ["--continue"] + rest
          emit(["kimi"] + rest)

      # 7. Bare codex -> codex ... resume --last
      if exe_base == "codex":
          subcmds = {"resume", "exec", "login", "logout", "mcp", "completion", "debug", "apply"}
          if any(a in subcmds for a in rest):
              emit(["codex"] + rest)
          emit(["codex"] + rest + ["resume", "--last"])

      sys.stdout.write(raw)
    '';
  };

  home.file.".config/zellij/config.kdl".text = ''
    scroll_buffer_size 100000
    support_kitty_keyboard_protocol true

    // Preserve sessions across disconnects, crashes, and reboots
    on_force_close "detach"
    session_serialization true
    serialize_pane_viewport true
    scrollback_lines_to_serialize 10000
    serialization_interval 10
    post_command_discovery_hook "${config.home.homeDirectory}/.local/bin/zellij-agent-resurrect"

    ui {
        pane_frames {
            rounded_corners true
        }
    }

    keybinds {
        normal {
            // used for moving in fish, hjkl is enough
            unbind "Alt Left"
            unbind "Alt Right"
            unbind "Alt Up"
            unbind "Alt Down"
        }
        session {
            // Explicit Quit lives inside Session mode (Ctrl+o -> q) so accidental
            // Ctrl+q never purges serialized sessions from disk.
            bind "q" { Quit; }
        }
        tab {
            // used for fzf in fish
            unbind "Ctrl t"
            bind "Ctrl y" { SwitchToMode "Normal"; }
        }
        shared_except "locked" {
            // Remap Ctrl+q to Detach so serialized session state stays intact
            unbind "Ctrl q"
            bind "Ctrl q" { Detach; }
        }
        shared_except "tab" "locked" {
            // used for fzf in fish
            unbind "Ctrl t"
            bind "Ctrl y" { SwitchToMode "Tab"; }
        }
        shared_except "move" "locked" {
            // collides with ctrl+backspace
            unbind "Ctrl h"
            bind "Ctrl j" { SwitchToMode "Move"; }
        }
    }
  '';
};
}
