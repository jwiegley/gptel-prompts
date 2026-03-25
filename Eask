;; -*- mode: eask; lexical-binding: t -*-

(package "gptel-prompts"
         "1.0.0"
         "Manage gptel-directives in individual files")

(website-url "https://github.com/jwiegley/gptel-prompts")
(keywords "gptel" "prompts" "directives")

(package-file "gptel-prompts.el")

(script "test" "emacs --batch -L . -L test -l ert -l gptel-prompts-test -f ert-run-tests-batch-and-exit")
(script "fuzz" "emacs --batch -L . -L test -l ert -l gptel-prompts-fuzz -f ert-run-tests-batch-and-exit")
(script "lint" "emacs --batch -L . --eval \"(require 'package-lint)\" -f package-lint-batch-and-exit gptel-prompts.el")
(script "format" "scripts/format.sh")
(script "format-check" "scripts/check-format.sh")
(script "bench" "scripts/check-benchmark.sh")
(script "coverage" "scripts/check-coverage.sh")

(source "gnu")
(source "melpa")

(depends-on "emacs" "29.1")
(depends-on "gptel" "0.9.8.5")
(depends-on "yaml")
(depends-on "templatel")
