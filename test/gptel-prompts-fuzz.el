;;; gptel-prompts-fuzz.el --- Fuzz tests for gptel-prompts -*- lexical-binding: t; -*-

;; Copyright (C) 2025 John Wiegley

;;; Commentary:

;; Property-based fuzz tests that exercise gptel-prompts with randomized input.

;;; Code:

(require 'ert)
(require 'gptel-prompts)

(defun gptel-prompts-fuzz--random-string (max-len)
  "Generate a random string of up to MAX-LEN characters."
  (let ((len (1+ (random max-len)))
        (chars "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?"))
    (apply #'string
           (cl-loop repeat len
                    collect (aref chars (random (length chars)))))))

(defun gptel-prompts-fuzz--random-role ()
  "Return a random valid role string."
  (nth (random 3) '("system" "user" "assistant")))

(defun gptel-prompts-fuzz--random-prompts (count)
  "Generate COUNT random prompt entries with valid roles."
  (cl-loop repeat count
           collect `((role . ,(gptel-prompts-fuzz--random-role))
                     (content . ,(gptel-prompts-fuzz--random-string 100)))))

(ert-deftest gptel-prompts-fuzz-process-prompts ()
  "Fuzz: process-prompts never crashes on valid input."
  (dotimes (_ 100)
    (let ((prompts (gptel-prompts-fuzz--random-prompts (1+ (random 10)))))
      (should (listp (gptel-prompts-process-prompts prompts))))))

(ert-deftest gptel-prompts-fuzz-process-prompts-result-structure ()
  "Fuzz: process-prompts output always has a string car."
  (dotimes (_ 50)
    (let* ((prompts (gptel-prompts-fuzz--random-prompts (1+ (random 8))))
           (result (gptel-prompts-process-prompts prompts)))
      (should (stringp (car result))))))

(ert-deftest gptel-prompts-fuzz-process-file-text ()
  "Fuzz: process-file handles random text content."
  (dotimes (_ 50)
    (let ((tmp (make-temp-file "fuzz" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file tmp
              (insert (gptel-prompts-fuzz--random-string 500)))
            (should (stringp (gptel-prompts-process-file tmp))))
        (delete-file tmp)))))

(ert-deftest gptel-prompts-fuzz-process-file-eld ()
  "Fuzz: process-file with valid eld content."
  (dotimes (_ 50)
    (let ((tmp (make-temp-file "fuzz" nil ".eld")))
      (unwind-protect
          (progn
            (with-temp-file tmp
              (insert (format "(%s)"
                              (mapconcat
                               (lambda (_)
                                 (format "%S" (gptel-prompts-fuzz--random-string 50)))
                               (make-list (1+ (random 5)) nil)
                               " "))))
            (should (listp (gptel-prompts-process-file tmp))))
        (delete-file tmp)))))

(ert-deftest gptel-prompts-fuzz-process-file-json ()
  "Fuzz: process-file with valid random JSON conversations."
  (dotimes (_ 50)
    (let* ((count (1+ (random 5)))
           (entries
            (cl-loop
             repeat count
             collect (format "{\"role\": \"%s\", \"content\": \"%s\"}"
                             (gptel-prompts-fuzz--random-role)
                             (replace-regexp-in-string
                              "[\"\\\\\n\r\t]" " "
                              (gptel-prompts-fuzz--random-string 50)))))
           (json-str (format "[%s]" (mapconcat #'identity entries ", ")))
           (tmp (make-temp-file "fuzz" nil ".json")))
      (unwind-protect
          (progn
            (with-temp-file tmp
              (insert json-str))
            (should (listp (gptel-prompts-process-file tmp))))
        (delete-file tmp)))))

(ert-deftest gptel-prompts-fuzz-read-directory ()
  "Fuzz: read-directory handles directories with many random files."
  (let ((tmp-dir (make-temp-file "fuzz-dir" t)))
    (unwind-protect
        (progn
          (dotimes (i 20)
            (with-temp-file (expand-file-name (format "prompt-%d.txt" i) tmp-dir)
              (insert (gptel-prompts-fuzz--random-string 200))))
          (let ((result (gptel-prompts-read-directory tmp-dir)))
            (should (= (length result) 20))
            (dolist (entry result)
              (should (symbolp (car entry)))
              (should (stringp (cdr entry))))))
      (delete-directory tmp-dir t))))

(provide 'gptel-prompts-fuzz)
;;; gptel-prompts-fuzz.el ends here
