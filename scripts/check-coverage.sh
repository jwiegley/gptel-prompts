#!/usr/bin/env bash
set -euo pipefail

# Check function coverage against baseline.
# Tracks which public gptel-prompts functions are called during tests.
# Usage: scripts/check-coverage.sh

BASELINE_FILE=".coverage-baseline"

COVERAGE=$(emacs --batch -L . -L test \
  -l cl-lib \
  -l gptel-prompts \
  -l ert \
  --eval "
(let ((all-fns nil)
      (called-fns (make-hash-table :test #'eq)))
  ;; Collect all public package functions
  (mapatoms
   (lambda (sym)
     (when (and (fboundp sym)
                (string-prefix-p \"gptel-prompts\" (symbol-name sym))
                (not (string-match-p \"--\" (symbol-name sym))))
       (push sym all-fns)
       (let ((f sym))
         (advice-add f :before
                     (lambda (&rest _) (puthash f t called-fns)))))))
  ;; Run tests
  (load \"test/gptel-prompts-test\" nil t)
  (ert-run-tests-batch)
  ;; Report
  (let* ((total (length all-fns))
         (covered (hash-table-count called-fns))
         (pct (if (> total 0) (round (* 100.0 (/ (float covered) total))) 0)))
    (message \"Coverage: %d/%d public functions (%d%%)\" covered total pct)
    (message \"Covered: %s\"
             (mapconcat #'symbol-name
                        (let (result)
                          (maphash (lambda (k _v) (push k result)) called-fns)
                          (sort result (lambda (a b)
                                         (string< (symbol-name a)
                                                  (symbol-name b)))))
                        \", \"))
    (let ((uncovered (cl-remove-if (lambda (f) (gethash f called-fns)) all-fns)))
      (when uncovered
        (message \"Uncovered: %s\"
                 (mapconcat #'symbol-name
                            (sort uncovered (lambda (a b)
                                              (string< (symbol-name a)
                                                       (symbol-name b))))
                            \", \"))))
    (princ (format \"%d\" pct))))" 2>/dev/null)

echo "Function coverage: ${COVERAGE}%"

if [ -f "$BASELINE_FILE" ]; then
  BASELINE=$(tr -d '[:space:]' < "$BASELINE_FILE")
  if [ "$COVERAGE" -lt "$BASELINE" ]; then
    echo "FAIL: Coverage dropped from ${BASELINE}% to ${COVERAGE}%"
    exit 1
  fi
  echo "OK: Coverage ${COVERAGE}% >= baseline ${BASELINE}%"
else
  echo "No baseline found. Saving current coverage as baseline."
  echo "$COVERAGE" > "$BASELINE_FILE"
fi
