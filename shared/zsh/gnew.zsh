gnew() {
  if [[ -z "$1" ]]; then
    echo "Usage: gnew <[owner/]repo-name>" >&2
    return 1
  fi

  local input="$1"
  local name owner
  if [[ "$input" == */* ]]; then
    owner="${input%%/*}"
    name="${input##*/}"
  else
    name="$input"
  fi

  local target=~/projects/$name
  if [[ -d "$target" ]]; then
    echo "Already exists: $name — cd'ing into it"
    cd "$target"
    return
  fi

  if [[ -z "$owner" ]]; then
    owner="$(gh api user -q .login)" || { echo "gh auth error" >&2; return 1; }
  fi

  mkdir -p "$HOME/projects"
  cd "$HOME/projects"
  gh repo create "$owner/$name" --private --clone >/dev/null || return 1
  cd "$target"
  echo "# $name" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  git push -qu origin main

  echo "Created $name at https://github.com/$owner/$name"
}
