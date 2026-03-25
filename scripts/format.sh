#!/usr/bin/env bash
set -euo pipefail

# Format all .el files to match Emacs standard indentation.
# Usage: scripts/format.sh [files...]
# With no arguments, formats all .el files in the project.

if [ $# -gt 0 ]; then
  files="$@"
else
  files=$(find . -name '*.el' -not -path './.eask/*' -not -path './.git/*')
fi

for file in $files; do
  [[ "$file" == *.el ]] || continue
  [ -f "$file" ] || continue
  emacs --batch \
    --eval "(progn
              (find-file \"$file\")
              (emacs-lisp-mode)
              (indent-region (point-min) (point-max))
              (delete-trailing-whitespace)
              (when (buffer-modified-p)
                (save-buffer)
                (message \"Formatted: %s\" \"$file\")))" \
    2>&1
done
