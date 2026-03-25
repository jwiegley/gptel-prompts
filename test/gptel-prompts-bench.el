;;; gptel-prompts-bench.el --- Benchmarks for gptel-prompts -*- lexical-binding: t; -*-

;; Copyright (C) 2025 John Wiegley

;;; Commentary:

;; Performance benchmarks for key gptel-prompts functions.
;; Run with: emacs --batch -L . -L test -l gptel-prompts-bench \
;;           --eval "(gptel-prompts-bench-report)"

;;; Code:

(require 'gptel-prompts)

(defvar gptel-prompts-bench--results nil
  "Alist of benchmark results: ((name . seconds) ...).")

(defun gptel-prompts-bench-run ()
  "Run all benchmarks and return results as an alist."
  (setq gptel-prompts-bench--results nil)

  ;; Benchmark process-prompts
  (let ((input '(((role . "system") (content . "You are a helpful assistant."))
                 ((role . "user") (content . "Hello, how are you?"))
                 ((role . "assistant") (content . "I am doing well, thank you!"))
                 ((role . "user") (content . "What is the weather like?")))))
    (push (cons "process-prompts"
                (car (benchmark-run 1000
                       (gptel-prompts-process-prompts input))))
          gptel-prompts-bench--results))

  ;; Benchmark process-file (text)
  (let ((tmp (make-temp-file "bench" nil ".txt")))
    (with-temp-file tmp
      (insert "You are a helpful coding assistant. Respond concisely."))
    (push (cons "process-file-text"
                (car (benchmark-run 500
                       (gptel-prompts-process-file tmp))))
          gptel-prompts-bench--results)
    (delete-file tmp))

  ;; Benchmark process-file (eld)
  (let ((tmp (make-temp-file "bench" nil ".eld")))
    (with-temp-file tmp
      (insert "(\"System prompt\" (prompt \"User message\") (response \"Reply\"))"))
    (push (cons "process-file-eld"
                (car (benchmark-run 500
                       (gptel-prompts-process-file tmp))))
          gptel-prompts-bench--results)
    (delete-file tmp))

  ;; Benchmark process-file (json)
  (let ((tmp (make-temp-file "bench" nil ".json")))
    (with-temp-file tmp
      (insert "[{\"role\": \"system\", \"content\": \"System\"},
                {\"role\": \"user\", \"content\": \"Hello\"}]"))
    (push (cons "process-file-json"
                (car (benchmark-run 500
                       (gptel-prompts-process-file tmp))))
          gptel-prompts-bench--results)
    (delete-file tmp))

  ;; Benchmark read-directory
  (let ((tmp-dir (make-temp-file "bench-dir" t)))
    (dotimes (i 10)
      (with-temp-file (expand-file-name (format "prompt-%d.txt" i) tmp-dir)
        (insert (format "This is prompt number %d for benchmarking." i))))
    (push (cons "read-directory-10"
                (car (benchmark-run 100
                       (gptel-prompts-read-directory tmp-dir))))
          gptel-prompts-bench--results)
    (delete-directory tmp-dir t))

  ;; Benchmark project-conventions-read
  (let ((tmp-dir (make-temp-file "bench-project" t)))
    (with-temp-file (expand-file-name "CONVENTIONS.md" tmp-dir)
      (insert "# Conventions\n\nFollow these rules."))
    (push (cons "project-conventions-read"
                (car (benchmark-run 200
                       (gptel-prompts--project-conventions-read tmp-dir))))
          gptel-prompts-bench--results)
    (delete-directory tmp-dir t))

  (nreverse gptel-prompts-bench--results))

(defun gptel-prompts-bench-report ()
  "Run benchmarks and print results, one per line: NAME SECONDS."
  (let ((results (gptel-prompts-bench-run)))
    (dolist (r results)
      (princ (format "%s %.6f\n" (car r) (cdr r))))))

(provide 'gptel-prompts-bench)
;;; gptel-prompts-bench.el ends here
