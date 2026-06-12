#!/bin/zsh

for test in ${0:h}/*.sh(N); do
  [[ "$test" == "${0}" ]] && continue
  echo "--- $(basename $test) ---"
  zsh "$test"
  echo ""
done
