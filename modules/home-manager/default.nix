# Custom home-manager modules
{
  zsh = import ./zsh.nix;
  tmux = import ./tmux.nix;
  git = import ./git.nix;
  fish = import ./fish.nix;
  zellij = import ./zellij.nix;
}
