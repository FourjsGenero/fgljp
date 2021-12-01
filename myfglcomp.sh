#!/bin/bash
#recompile only when needed
myfglcomp() {
  local src=$1.4gl
  local src=$1.4gl
  local m42=$1.42m
  local compile=0
  if [ ! -f "$m42" ]; then
    compile=1
    reason="$m42 doesn't exist"
  else
    if [ "$src" -nt "$m42" ]; then
      compile=1
      reason="$src is newer"
    else
      fglrun -r $m42 >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        compile=1
        reason="p code in $m42 is not valid"
      fi
    fi
  fi
  if [ $compile -eq 1 ]; then
    echo "compile $src, $reason."
    fglcomp -M -Wall -r $src
    if [ $? -ne 0 ]; then
      exit 1
    fi
  else
    echo "$m42 up to date."
  fi
}
