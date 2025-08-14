{ config, pkgs, ... }:

{
  home.file.".ideavimrc".text = ''
    source ~/helix.vim/helix.idea.vim
  '';
}