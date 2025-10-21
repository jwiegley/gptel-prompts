;;; gptel-prompts.el --- GPTel directive management using files -*- lexical-binding: t -*-

;; Copyright (C) 2025 John Wiegley

;; Author: John Wiegley <johnw@gnu.org>
;; Created: 19 May 2025
;; Version: 1.0
;; Keywords: ai gptel prompts
;; X-URL: https://github.com/jwiegley/dot-emacs
;; Package-Requires: ((emacs "24.1"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; This package provides enhanced prompt management capabilities for GPTel,
;; allowing you to organize and dynamically load AI prompts from external
;; files rather than hardcoding them in your Emacs configuration.

;; Key Features:
;;
;; * Multi-format prompt support: Load prompts from .txt, .md, .org, .json,
;;   .eld (Emacs Lisp data), .el (Emacs Lisp functions), and .poet/.jinja
;;   (Prompt Poet/Jinja2 templates)
;;
;; * Template interpolation: Use Jinja2-style {{variable}} syntax with
;;   customizable variables and dynamic functions
;;
;; * File watching: Automatically reload prompts when files change
;;
;; * Project-aware prompts: Automatically load project-specific conventions
;;   from CONVENTIONS.md or CLAUDE.md files
;;
;; * Conversation format support: Handle multi-turn conversations with
;;   system/user/assistant roles

;; Setup:
;;
;;   (use-package gptel-prompts
;;     :after (gptel)
;;     :custom
;;     (gptel-prompts-directory "~/my-prompts")
;;     :config
;;     (gptel-prompts-update)
;;     ;; Optional: auto-reload on file changes
;;     (gptel-prompts-add-update-watchers))

;; File Formats:
;;
;; * Plain text (.txt, .md, .org): Used as-is for system prompts
;; * JSON (.json): Array of {role: "system/user/assistant", content: "..."}
;; * Emacs Lisp data (.eld): List format for conversations
;; * Emacs Lisp code (.el): Lambda functions for dynamic prompts
;; * Prompt Poet (.poet, .j2, .jinja, .jinja2): YAML + Jinja2 templates

;; Template Variables:
;;
;; Use {{variable_name}} in your prompts. Variables can be defined in
;; `gptel-prompts-template-variables' or generated dynamically by functions
;; in `gptel-prompts-template-functions'.

;; Project Integration:
;;
;; Add `gptel-prompts-project-conventions' to `gptel-directives' to
;; automatically load project-specific prompts from CONVENTIONS.md or
;; CLAUDE.md files in your project root.

;;; Code:

(require 'cl-lib)
(require 'cl-macs)
(require 'rx)
(require 'filenotify)
(require 'gptel)

(defgroup gptel-prompts nil
  "Helper library for managing GPTel prompts (aka directives)."
  :group 'gptel)

(defcustom gptel-prompts-directory "~/.emacs.d/prompts"
  "*Directory where GPTel prompts are defined, one per file.

Note that files can be of different types, which will cause them to be
represented as directives differently. See `gptel-prompts-file-regexp'
for more information."
  :type 'file
  :group 'gptel-prompts)

(defcustom gptel-prompts-file-regexp
  (rx "." (group
           (or "txt"
               "md"
               "org"
               "eld"
               "el"
               (seq "j" (optional "inja") (optional "2"))
               "poet"
               "json"))
      string-end)
  "*Directory where GPTel prompts are defined, one per file.

Note that files can be of different types, which will cause them
to be represented as directives differently:

  .txt, .md, .org    Purely textual prompts that are used as-is
  .eld               Must be a Lisp list represent a conversation:
                       SYSTEM, USER, ASSISTANT, [USER, ASSISTANT, ...]
  .el                Must evaluate to a Lisp function
  .poet              See https://github.com/character-ai/prompt-poet
  .json              JSON list of role-assigned prompts"
  :type 'regexp
  :group 'gptel-prompts)

(defcustom gptel-prompts-template-variables nil
  "*An alist of names to strings used during template expansion.

Example:
  ((\"name\" . \"John\")
   (\"hobbies\" . \"Emacs\"))

These would referred to using {{ name }} and {{ hobbies }} in the
prompt template."
  :type '(alist :key-type string :value-type string)
  :group 'gptel-prompts)

(defcustom gptel-prompts-template-functions
  '(gptel-prompts-add-current-time)
  "*Set of functions run when a template prompt is used.

These are called when the template is going to be used by
`gptel-request'. Each function receives the name of the template file,
and must return either nil or an alist of variable values to prepend to
`gptel-prompts-template-variables'. See that variable's documentation
for the expected format."
  :type '(list function)
  :group 'gptel-prompts)

(defcustom gptel-prompts-template-base-directory nil
  "Base directory for resolving inherited files referenced in prompts.
Accepts either a string directory expanded with `expand-file-name'
to resolve relative template paths referenced in prompts, or a function
that receives a prompt and a file and returns a directory.  When nil,
inherited file resolution will default to the directory containing
the prompt file being interpolated."
  :type '(choice (const :tag "Use prompt file directory" nil)
                 (directory :tag "Custom base directory")
                 (function :tag "Function that returns base directory"))
  :group 'gptel-prompts)

(defcustom gptel-prompts-prepare-template-env-functions '()
  "Hook for preparing the `templatel' environment before interpolation.
Can be used for adding `templatel' filters and tests."
  :type '(list function)
  :group 'gptel-prompts)

(defcustom gptel-prompts-get-template-env-function #'gptel-prompts--prepare-template-env
  "Return a `templatel' environment to be used for interpolation."
  :type 'function
  :group 'gptel-prompts)

(defun gptel-prompts-process-prompts (prompts)
  "Convert from a list of PROMPTS in dialog format, to GPTel.

For example:

  (((role . \"system\")
    (content . \"Sample\")
    (name . \"system instructions\"))
   ((role . \"system\")
    (content . \"Sample\")
    (name . \"further system instructions\"))
   ((role . \"user\")
    (content . \"Sample\")
    (name . \"User message\"))
   ((role . \"assistant\")
    (content . \"Sample\")
    (name . \"Model response\"))
   ((role . \"user\")
    (content . \"Sample\")
    (name . \"Second user message\")))

Becomes:

   (\"system instructions\nfurther system instructions\"
    (prompt \"User message\")
    (response \"Model response\")
    (prompt \"Second user message\"))"
  (let ((system "") result)
    (dolist (prompt prompts)
      (let ((content (alist-get 'content prompt))
            (role (alist-get 'role prompt)))
        (cond
         ((string= role "system")
          (setq system (if (string-empty-p system)
                           content
                         (concat system "\n" content))))
         ((string= role "user")
          (setq result (cons (list 'prompt content) result)))
         ((string= role "assistant")
          (setq result (cons (list 'response content) result)))
         ((string= role "tool")
          (error "Tools not yet supported in Poet prompts"))
         (t
          (error "Role not recognized in prompt: %s"
                 (pp-to-string prompt))))))
    (cons system (nreverse result))))

(defun gptel-prompts--prepare-template-env (prompt &optional file)
  "Returns a `template' environment with support for file inclusion and
inheritance. When `gptel-prompts-template-base-directory' is nil, uses
the directory of the PROMPT file being interpolated for resolving
template paths with `expand-file-name'

Can be used to extend the environment with template inheritance,
filters, and tests."
  (let* ((base-dir (or ; Determine base directory for template resolution
                    (or
                     (and (functionp gptel-prompts-template-base-directory)
                          (funcall gptel-prompts-template-base-directory
                                   prompt file))
                     gptel-prompts-template-base-directory)
                    (when file (file-name-directory file))
                    default-directory))
         ;; Create environment with importfn
         (env (templatel-env-new
               :importfn (lambda (environment name)
                           (let ((template-path (expand-file-name name base-dir)))
                             (when (file-readable-p template-path)
                               (templatel-env-add-template
                                environment name
                                (templatel-new-from-file template-path))))))))
    (mapcar #'(lambda (f) (funcall f env))
            gptel-prompts-prepare-template-env-functions)
    env))

(defun gptel-prompts-interpolate (prompt &optional file)
  "Expand Jinja-style references using a full templatel environment."
  (require 'templatel)
  ;; Gather variables from template functions
  (let* ((vars (apply #'append
                      (mapcar #'(lambda (f) (funcall f file))
                              gptel-prompts-template-functions)))
         (all-vars (cl-remove-duplicates
                    (append vars gptel-prompts-template-variables)
                    :test #'string= :from-end t :key #'car))
         (env (funcall gptel-prompts-get-template-env-function prompt file)))
    ;; Add the main template to the environment and render it
    (templatel-env-add-template env "main" (templatel-new prompt))
    (templatel-env-render env "main" all-vars)))

(defun gptel-prompts-interpolate-buffer ()
  "Expand Jinja-style references to `gptel-prompts-template-variables'.
See `gptel-prompts-interpolate'.
This function can be added to `gptel-prompt-transform-functions'."
  (let ((replacement (gptel-prompts-interpolate (buffer-string))))
    (delete-region (point-min) (point-max))
    (insert replacement)))

(defun gptel-prompts-poet (file)
  "Read Yaml + Jinja FILE in prompt-poet format."
  (require 'yaml)
  (gptel-prompts-process-prompts
   (mapcar #'yaml--hash-table-to-alist
           (yaml-parse-string
            (gptel-prompts-interpolate
             (with-temp-buffer
               (insert-file-contents file)
               (buffer-string))
             file)))))

(defun gptel-prompts-process-file (file)
  "Process FILE and return appropriate content.

FILE is a string path to the file to be processed.

Handles different file types based on extension:
- .eld files: Read as Emacs Lisp data, must evaluate to a list
- .el files: Read as Emacs Lisp code, must evaluate to a function/lambda
- .json files: Parse as JSON array and process as prompts via
  `gptel-prompts-process-prompts'
- .j2/.jinja/.jinja2/.poet files: Return lambda that calls
  `gptel-prompts-poet' with FILE
- Other files: Return trimmed file contents as plain text string

Returns the processed content in the appropriate format for each file
type. Signals an error if the file content doesn't match expected format
for typed files."
  (cond ((string-match "\\.eld\\'" file)
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (let ((lst (read (current-buffer))))
             (if (listp lst)
                 lst
               (error "Emacs Lisp data prompts must evaluate to a list")))))
        ((string-match "\\.el\\'" file)
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (let ((func (read (current-buffer))))
             (if (and (functionp func)
                      (listp func)
                      (eq 'lambda (car func)))
                 func
               (error "Emacs Lisp prompts must evaluate to a function/lambda")))))
        ((string-match "\\.json\\'" file)
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (let ((conversation (json-read)))
             (if (vectorp conversation)
                 (gptel-prompts-process-prompts (seq-into conversation 'list))
               (error "Emacs Lisp prompts must evaluate to a list")))))
        ((string-match "\\.\\(j\\(inja\\)?2?\\|poet\\)\\'" file)
         `(lambda () (gptel-prompts-poet ,file)))
        (t
         (with-temp-buffer
           (insert-file-contents file)
           (string-trim (buffer-string))))))

(defun gptel-prompts-read-directory (dir)
  "Read prompts from directory DIR and establish them in `gptel-directives'."
  (cl-loop for file in (directory-files dir t gptel-prompts-file-regexp)
           collect (cons (intern (file-name-sans-extension
                                  (file-name-nondirectory file)))
                         (gptel-prompts-process-file file))))

(defun gptel-prompts-update ()
  "Update `gptel-directives' from files in `gptel-prompts-directory'."
  (interactive)
  (dolist (prompt (gptel-prompts-read-directory gptel-prompts-directory))
    (setq gptel-directives
          (cl-delete-if #'(lambda (x) (eq (car x) (car prompt)))
                        gptel-directives))
    (add-to-list 'gptel-directives prompt)))

(defun gptel-prompts-add-current-time (_file)
  "Add the current time as a variable for Poet interpolation."
  `(("current_time" . ,(format-time-string "%F %T"))))

(defun gptel-prompts-add-update-watchers ()
  "Watch all files in DIR and run CALLBACK when any is modified."
  (let ((watches (list (file-notify-add-watch
                        gptel-prompts-directory '(change)
                        #'(lambda (&rest _events)
                            (gptel-prompts-update))))))
    (dolist (file (directory-files gptel-prompts-directory
                                   t gptel-prompts-file-regexp))
      (when (file-regular-p file)
        (push (file-notify-add-watch file '(change)
                                     #'(lambda (&rest _events)
                                         (gptel-prompts-update)))
              watches)))
    watches))

(defvar gptel-prompts--project-conventions-alist nil
  "Alist mapping projects to project conventions for LLMs.")

(defcustom gptel-prompts-project-files
  '("CONVENTIONS.md"
    "CLAUDE.md"
    "AGENTS.md"
    (".github" . "copilot-instructions\\.md")
    (".instructions.d" . "^.*\\.md$")
    ".instructions.md")
  "A list of files or directories with prompts for the current project.
Entries can be strings (file/directory names) or cons cells where the
CAR is a directory path and the CDR is either a regexp string or a
filter function for selecting which files in that directory should be
chosen.

The first matching rule in the list for a given project is used, with
the rest ignored.

If a directory is specified without a filter (as a plain string), all
markdown files within it will be aggregated into a single prompt."
  :type '(repeat (choice file directory
                         (cons directory (choice regexp function))))
  :group 'gptel-prompts)

(defun gptel-prompts--read-directory-filtered (dir regexp-or-function)
  "Read files from DIR for which REGEXP-OR-FUNCTION is a match."
  (when (and (file-directory-p dir)
             (file-readable-p dir))
    (let ((files
           (cl-remove-if-not
            (cond
             ((functionp regexp-or-function)
              (lambda (f)
                (funcall regexp-or-function (file-name-nondirectory f))))
             ((stringp regexp-or-function)
              (lambda (f)
                (string-match-p regexp-or-function (file-name-nondirectory f))))
             (t (error "Invalid filter: %s" regexp-or-function)))
            (directory-files dir t "^[^.].*" t))))
      (unless (null files)
        (mapconcat
         (lambda (file)
           (when (and (file-regular-p file)
                      (file-readable-p file))
             (with-temp-buffer
               (insert-file-contents file)
               (buffer-string))))
         files "\n\n")))))

(defun gptel-prompts--read-directory (dir)
  "Read all Markdown files from DIR, concated together."
  (let ((contents
         (mapconcat
          (lambda (file)
            (when (and (file-regular-p file)
                       (file-readable-p file))
              (with-temp-buffer
                (insert-file-contents file)
                (buffer-string))))
          (directory-files dir t "^[^.].*\\.md$" t)
          "\n\n")))
    (unless (string-empty-p contents)
      contents)))

(defun gptel-prompts-project-conventions ()
  "System prompt is obtained from project CONVENTIONS.
This function should be added to `gptel-directives'. To replace
the default directive, use:

  (setf (alist-get \\'default gptel-directives)
        #\\'gptel-project-conventions)"
  (when-let* ((project (project-current))
              (root (project-root project)))
    (with-memoization
        (alist-get root gptel-prompts--project-conventions-alist
                   nil nil #'equal)
      (or (cl-loop
           for item in gptel-prompts-project-files
           for path = (expand-file-name
                       (if (consp item) (car item) item)
                       root)
           when (file-readable-p path)
           return (cond
                   ((consp item)
                    (gptel-prompts--read-directory-filtered (car item) (cdr item)))
                   ((file-directory-p path)
                    (gptel-prompts--read-directory path))
                   (t
                    (with-temp-buffer
                      (insert-file-contents path)
                      (buffer-string)))))
          "You are a helpful assistant. Respond concisely."))))

(provide 'gptel-prompts)

;;; gptel-prompts.el ends here
