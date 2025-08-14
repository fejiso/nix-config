# Custom home-manager modules
{
  zsh = import ./zsh.nix;
  tmux = import ./tmux.nix;
  git = import ./git.nix;
  fish = import ./fish.nix;
  zellij = import ./zellij.nix;
  kanshi = import ./kanshi.nix;
  sway = import ./sway.nix;
  wezterm = import ./wezterm.nix;
  beets = import ./beets.nix;
  nethack = import ./nethack.nix;
  ideavim = import ./ideavim.nix;
  gpg = import ./gpg.nix;
}
