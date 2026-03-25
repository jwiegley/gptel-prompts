;;; gptel-prompts-test.el --- Tests for gptel-prompts -*- lexical-binding: t; -*-

;; Copyright (C) 2025 John Wiegley

;;; Commentary:

;; Unit tests for gptel-prompts.

;;; Code:

(require 'ert)
(require 'gptel-prompts)

;;; gptel-prompts-process-prompts

(ert-deftest gptel-prompts-test-process-prompts-system-only ()
  "Process a single system prompt."
  (let ((result (gptel-prompts-process-prompts
                 '(((role . "system") (content . "You are helpful."))))))
    (should (equal result '("You are helpful.")))))

(ert-deftest gptel-prompts-test-process-prompts-full-conversation ()
  "Process a full multi-turn conversation."
  (let ((result (gptel-prompts-process-prompts
                 '(((role . "system") (content . "System prompt"))
                   ((role . "user") (content . "Hello"))
                   ((role . "assistant") (content . "Hi"))
                   ((role . "user") (content . "Bye"))))))
    (should (equal (car result) "System prompt"))
    (should (equal (cadr result) '(prompt "Hello")))
    (should (equal (caddr result) '(response "Hi")))
    (should (equal (cadddr result) '(prompt "Bye")))))

(ert-deftest gptel-prompts-test-process-prompts-multiple-system ()
  "Multiple system prompts are concatenated with newline."
  (let ((result (gptel-prompts-process-prompts
                 '(((role . "system") (content . "First"))
                   ((role . "system") (content . "Second"))))))
    (should (equal (car result) "First\nSecond"))))

(ert-deftest gptel-prompts-test-process-prompts-empty-system ()
  "Empty system content is handled."
  (let ((result (gptel-prompts-process-prompts
                 '(((role . "user") (content . "Hello"))))))
    (should (equal (car result) ""))
    (should (equal (cadr result) '(prompt "Hello")))))

(ert-deftest gptel-prompts-test-process-prompts-tool-error ()
  "Tool role signals an error."
  (should-error
   (gptel-prompts-process-prompts
    '(((role . "tool") (content . "result"))))))

(ert-deftest gptel-prompts-test-process-prompts-unknown-role-error ()
  "Unknown role signals an error."
  (should-error
   (gptel-prompts-process-prompts
    '(((role . "unknown") (content . "test"))))))

;;; gptel-prompts-process-file

(ert-deftest gptel-prompts-test-process-file-text ()
  "Process a plain text file with whitespace trimming."
  (let ((temp-file (make-temp-file "gptel-test" nil ".txt")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "  Hello, world!  "))
          (should (equal (gptel-prompts-process-file temp-file)
                         "Hello, world!")))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-md ()
  "Process a markdown file."
  (let ((temp-file (make-temp-file "gptel-test" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "# Heading\n\nBody text"))
          (should (equal (gptel-prompts-process-file temp-file)
                         "# Heading\n\nBody text")))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-org ()
  "Process an org-mode file."
  (let ((temp-file (make-temp-file "gptel-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "* Heading\nBody text"))
          (should (equal (gptel-prompts-process-file temp-file)
                         "* Heading\nBody text")))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-eld ()
  "Process an Emacs Lisp data file."
  (let ((temp-file (make-temp-file "gptel-test" nil ".eld")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "(\"system prompt\" (prompt \"hello\"))"))
          (should (equal (gptel-prompts-process-file temp-file)
                         '("system prompt" (prompt "hello")))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-eld-non-list-error ()
  "Non-list eld content signals an error."
  (let ((temp-file (make-temp-file "gptel-test" nil ".eld")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "\"just a string\""))
          (should-error (gptel-prompts-process-file temp-file)))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-el ()
  "Process an Emacs Lisp code file containing a lambda."
  (let ((temp-file (make-temp-file "gptel-test" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "(lambda () \"hello\")"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (listp result))
            (should (eq 'lambda (car result)))
            (should (equal (funcall result) "hello"))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-el-non-lambda-error ()
  "Non-lambda el content signals an error."
  (let ((temp-file (make-temp-file "gptel-test" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "\"just a string\""))
          (should-error (gptel-prompts-process-file temp-file)))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-json ()
  "Process a JSON file with role/content objects."
  (let ((temp-file (make-temp-file "gptel-test" nil ".json")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "[{\"role\": \"system\", \"content\": \"Test\"}]"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (equal (car result) "Test"))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-json-conversation ()
  "Process a JSON file with a multi-turn conversation."
  (let ((temp-file (make-temp-file "gptel-test" nil ".json")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "[{\"role\": \"system\", \"content\": \"Sys\"},
                      {\"role\": \"user\", \"content\": \"Hi\"},
                      {\"role\": \"assistant\", \"content\": \"Hello\"}]"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (equal (car result) "Sys"))
            (should (equal (cadr result) '(prompt "Hi")))
            (should (equal (caddr result) '(response "Hello")))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-poet ()
  "Poet files return a lambda."
  (let ((temp-file (make-temp-file "gptel-test" nil ".poet")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "- role: system\n  content: Test"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (listp result))
            (should (eq 'lambda (car result)))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-jinja ()
  "Jinja files return a lambda."
  (let ((temp-file (make-temp-file "gptel-test" nil ".jinja")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "- role: system\n  content: Test"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (listp result))
            (should (eq 'lambda (car result)))))
      (delete-file temp-file))))

(ert-deftest gptel-prompts-test-process-file-j2 ()
  "J2 files return a lambda."
  (let ((temp-file (make-temp-file "gptel-test" nil ".j2")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "- role: system\n  content: Test"))
          (let ((result (gptel-prompts-process-file temp-file)))
            (should (listp result))
            (should (eq 'lambda (car result)))))
      (delete-file temp-file))))

;;; gptel-prompts-read-directory

(ert-deftest gptel-prompts-test-read-directory ()
  "Read prompts from a directory."
  (let ((temp-dir (make-temp-file "gptel-test-dir" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "greeting.txt" temp-dir)
            (insert "Hello!"))
          (with-temp-file (expand-file-name "farewell.md" temp-dir)
            (insert "Goodbye!"))
          (let ((result (gptel-prompts-read-directory temp-dir)))
            (should (= (length result) 2))
            (should (equal (alist-get 'greeting result) "Hello!"))
            (should (equal (alist-get 'farewell result) "Goodbye!"))))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-read-directory-skips-autosave ()
  "Autosave and lock files are skipped."
  (let ((temp-dir (make-temp-file "gptel-test-dir" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "good.txt" temp-dir)
            (insert "Keep me"))
          (with-temp-file (expand-file-name "#autosave.txt" temp-dir)
            (insert "Skip me"))
          (with-temp-file (expand-file-name ".#lock.txt" temp-dir)
            (insert "Skip me too"))
          (let ((result (gptel-prompts-read-directory temp-dir)))
            (should (= (length result) 1))
            (should (equal (alist-get 'good result) "Keep me"))))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-read-directory-multiple-types ()
  "Directory with mixed file types."
  (let ((temp-dir (make-temp-file "gptel-test-dir" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "text.txt" temp-dir)
            (insert "Plain text"))
          (with-temp-file (expand-file-name "data.eld" temp-dir)
            (insert "(\"system\" (prompt \"hello\"))"))
          (with-temp-file (expand-file-name "ignored.html" temp-dir)
            (insert "<html></html>"))
          (let ((result (gptel-prompts-read-directory temp-dir)))
            (should (= (length result) 2))
            (should (stringp (alist-get 'text result)))
            (should (listp (alist-get 'data result)))))
      (delete-directory temp-dir t))))

;;; gptel-prompts-add-current-time

(ert-deftest gptel-prompts-test-add-current-time ()
  "Current time variable is generated."
  (let ((result (gptel-prompts-add-current-time nil)))
    (should (= (length result) 1))
    (should (equal (caar result) "current_time"))
    (should (stringp (cdar result)))
    (should (string-match-p "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" (cdar result)))))

;;; gptel-prompts--project-conventions-read

(ert-deftest gptel-prompts-test-project-conventions-read-conventions ()
  "Read CONVENTIONS.md from project root."
  (let ((temp-dir (make-temp-file "gptel-project" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "CONVENTIONS.md" temp-dir)
            (insert "Project conventions here"))
          (let ((result (gptel-prompts--project-conventions-read temp-dir)))
            (should (equal result "Project conventions here"))))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-project-conventions-read-claude ()
  "Read CLAUDE.md when CONVENTIONS.md is absent."
  (let ((temp-dir (make-temp-file "gptel-project" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "CLAUDE.md" temp-dir)
            (insert "Claude instructions"))
          (let ((result (gptel-prompts--project-conventions-read temp-dir)))
            (should (equal result "Claude instructions"))))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-project-conventions-read-priority ()
  "CONVENTIONS.md takes priority over CLAUDE.md."
  (let ((temp-dir (make-temp-file "gptel-project" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "CONVENTIONS.md" temp-dir)
            (insert "Conventions"))
          (with-temp-file (expand-file-name "CLAUDE.md" temp-dir)
            (insert "Claude"))
          (let ((result (gptel-prompts--project-conventions-read temp-dir)))
            (should (equal result "Conventions"))))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-project-conventions-fallback ()
  "Missing conventions returns default prompt."
  (let ((temp-dir (make-temp-file "gptel-project" t)))
    (unwind-protect
        (let ((result (gptel-prompts--project-conventions-read temp-dir)))
          (should (equal result "You are a helpful assistant. Respond concisely.")))
      (delete-directory temp-dir t))))

;;; gptel-prompts-update

(ert-deftest gptel-prompts-test-update ()
  "Update populates gptel-directives from directory."
  (let ((temp-dir (make-temp-file "gptel-test-dir" t))
        (gptel-prompts-directory nil)
        (gptel-directives nil))
    (unwind-protect
        (progn
          (setq gptel-prompts-directory temp-dir)
          (with-temp-file (expand-file-name "test-prompt.txt" temp-dir)
            (insert "A test prompt"))
          (gptel-prompts-update)
          (should (equal (alist-get 'test-prompt gptel-directives)
                         "A test prompt")))
      (delete-directory temp-dir t))))

(ert-deftest gptel-prompts-test-update-replaces-existing ()
  "Update replaces an existing directive with the same name."
  (let ((temp-dir (make-temp-file "gptel-test-dir" t))
        (gptel-prompts-directory nil)
        (gptel-directives '((test-prompt . "Old prompt"))))
    (unwind-protect
        (progn
          (setq gptel-prompts-directory temp-dir)
          (with-temp-file (expand-file-name "test-prompt.txt" temp-dir)
            (insert "New prompt"))
          (gptel-prompts-update)
          (should (equal (alist-get 'test-prompt gptel-directives)
                         "New prompt")))
      (delete-directory temp-dir t))))

(provide 'gptel-prompts-test)
;;; gptel-prompts-test.el ends here
