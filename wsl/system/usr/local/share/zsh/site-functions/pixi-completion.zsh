# Load pixi's zsh completions, once pixi exists.
#
# pixi is no longer installed at provision time — the `use pixi` direnv directive
# installs it on first use — so this cannot be the unconditional eval that pixi's
# own docs put in ~/.zshrc: on a fresh instance that errors on every shell start.
#
# A guard alone would silence that but leave the user without completions until
# `exec zsh`, because .zshrc has already run by the time `direnv allow` installs
# pixi. A precmd hook runs before every prompt in the *current* shell, so the very
# shell that ran `direnv allow` picks completions up at its next prompt.
#
# Self-removing: once it fires it costs nothing, and until then it is one stat per
# prompt. When pixi is already installed it fires at the first prompt, which is
# indistinguishable from evaluating this at startup.
_pixi_completion_init() {
  [[ -x "$HOME/.pixi/bin/pixi" ]] || return 0
  eval "$("$HOME/.pixi/bin/pixi" completion --shell zsh)"
  add-zsh-hook -d precmd _pixi_completion_init
  unfunction _pixi_completion_init
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _pixi_completion_init
