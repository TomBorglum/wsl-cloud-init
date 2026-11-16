# pixi is installed by the `use pixi` direnv directive on first use, not at provision time, so
# an unconditional eval of its completions errors on every shell start on a fresh instance.
#
# A guard alone would leave the user without completions until `exec zsh`, because .zshrc has
# already run by the time `direnv allow` installs pixi. A precmd hook runs before every prompt in
# the current shell, so the shell that ran `direnv allow` picks them up at its next prompt.
_pixi_completion_init() {
  [[ -x "$HOME/.pixi/bin/pixi" ]] || return 0
  eval "$("$HOME/.pixi/bin/pixi" completion --shell zsh)"
  add-zsh-hook -d precmd _pixi_completion_init
  unfunction _pixi_completion_init
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _pixi_completion_init
