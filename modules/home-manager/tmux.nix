{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    defaultTerminal = "tmux-256color";
    historyLimit = 40000;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      tpm
      status-variables
      logging
      fpp
      yank
      copycat
      pain-control
      resurrect
      sensible
      prefix-highlight
    ];
    extraConfig = ''
      set -g @resurrect-save "u"
      set -g @resurrect-restore "r"
      set -g prefix C-b
      bind C-b send-prefix
      set -g prefix2 `
      bind ` send-prefix -2
      set -g set-titles on
      set -g set-titles-string '#S:#I.#P #W'
      set -g status-bg colour238
      set -g status-fg white
      set -g status-interval 1
      set -g status-left-length 200
      set -g status-right-length 200
      setw -g monitor-activity on
      set -g visual-activity on
      setw -g window-status-current-style bg=red
      set -g lock-command vlock
      bind L lock-server
      set -g bell-action any
      bind | split-window -h
      bind - split-window -v
      bind S new-session
      bind -r h select-pane -L
      bind -r j select-pane -D
      bind -r k select-pane -U
      bind -r l select-pane -R
      bind : command-prompt
      bind R source-file ~/.config/tmux/tmux.conf
    '';
  };
}