# Override the oh-my-zsh `pj` plugin completion.
#
# The stock _pj offers the project list at every word position, so repeated
# <Tab> keeps appending the same project name (`pj foo foo foo ...`). This
# version only completes the project name in its actual argument slot.
_pj() {
  local -a projects
  local basedir
  for basedir ($PROJECT_PATHS); do
    projects+=(${basedir}/*(/N:t))
  done

  # `pjo` is `alias pjo="pj open"`, so its project arg is word 2.
  if [[ $words[1] == pjo ]]; then
    (( CURRENT == 2 )) && compadd -a projects
    return
  fi

  case $CURRENT in
    2) compadd -- open; compadd -a projects ;;          # pj <project> | pj open
    3) [[ $words[2] == open ]] && compadd -a projects ;; # pj open <project>
  esac
}
compdef _pj pj pjo
