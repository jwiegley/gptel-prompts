#!/usr/bin/env bash
set -euo pipefail

# Check that all .el files match Emacs standard indentation.
# Usage: scripts/check-format.sh [files...]
# With no arguments, checks all .el files in the project.

if [ $# -gt 0 ]; then
  files="$@"
else
  files=$(find . -name '*.el' -not -path './.eask/*' -not -path './.git/*')
fi

status=0
for file in $files; do
  [[ "$file" == *.el ]] || continue
  [ -f "$file" ] || continue
  emacs --batch \
    --eval "(progn
              (find-file \"$file\")
              (emacs-lisp-mode)
              (let ((original (buffer-string)))
                (indent-region (point-min) (point-max))
                (delete-trailing-whitespace)
                (unless (string= original (buffer-string))
                  (message \"FAIL: formatting differs in %s\" \"$file\")
                  (kill-emacs 1))))" \
    2>&1 || { status=1; }
done

if [ "$status" -eq 0 ]; then
  echo "All files properly formatted."
fi
exit $status
