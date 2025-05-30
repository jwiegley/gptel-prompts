;;; gptel-prompts --- Extra functions for use with gptel

;; Copyright (C) 2025 John Wiegley

;; Author: John Wiegley <johnw@gnu.org>
;; Created: 19 May 2025
;; Version: 1.0
;; Keywords: ai gptel tools
;; X-URL: https://github.com/jwiegley/dot-emacs

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

(require 'cl-lib)
(require 'cl-macs)
(require 'rx)
(eval-when-compile
  (require 'cl))

(require 'gptel)

(defgroup gptel-prompts nil
  "Helper library for managing GPTel prompts (aka directives)."
  :group 'gptel)

(defcustom gptel-prompts-directory "~/.emacs.d/prompts"
  "*Directory where GPTel prompts are defined, one per file.

Note that files can be of different types, which will cause them
to be represented as directives differently:

  .txt, .md, .org    Purely textual prompts that are used as-is
  .el                Must be a Lisp list represent a conversation:
                       SYSTEM, USER, ASSISTANT, [USER, ASSISTANT, ...]
  .jinja, jinja2     A Jinja template supporting Emacs Lisp sexps"
  :type 'file
  :group 'gptel-prompts)

(defcustom gptel-prompts-file-regexp
  (rx "." (group
           (or "txt"
               "md"
               "org"
               "el"
               (seq "j" (optional "inja") (optional "2"))
               "poet"
               "json"))
      string-end)
  "*Directory where GPTel prompts are defined, one per file.

Note that files can be of different types, which will cause them
to be represented as directives differently:

  .txt, .md, .org    Purely textual prompts that are used as-is
  .el                Must be a Lisp list represent a conversation:
                       SYSTEM, USER, ASSISTANT, [USER, ASSISTANT, ...]
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
`gptel-request'. Each function receives the name of the template
file, and must return either `nil' or an alist of variable values
to prepend to `gptel-prompts-template-variables'. See that
variable's documentation for the expected format."
  :type '(list function)
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
         (otherwise
          (error "Role not recognized in prompt: %s"
                 (pp-to-string prompt))))))
    (cons system (nreverse result))))

(defun gptel-prompts-poet (file)
  "Read Yaml + Jinja file in prompt-poet format."
  (require 'templatel)
  (require 'yaml)
  (let ((vars (apply #'append
                     (mapcar #'(lambda (f) (funcall f file))
                             gptel-prompts-template-functions))))
    (gptel-prompts-process-prompts
     (mapcar #'yaml--hash-table-to-alist
             (yaml-parse-string
              (templatel-render-string
               (with-temp-buffer
                 (insert-file-contents file)
                 (buffer-string))
               (cl-remove-duplicates
                (append vars gptel-prompts-template-variables)
                :test #'string= :from-end t :key #'car)))))))

(defun gptel-prompts-process-file (file)
  (cond ((string-match "\\.el\\'" file)
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (let ((lst (read (current-buffer))))
             (if (listp lst)
                 lst
               (error "Emacs Lisp prompts must evaluate to a list")))))
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
  (setq gptel-directives
        (gptel-prompts-read-directory gptel-prompts-directory)))

(defun gptel-prompts-add-current-time (_file)
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

(defun gptel-prompts-project-conventions ()
  "System prompt is obtained from project CONVENTIONS.
This function should be added to `gptel-directives'. To replace
the default directive, use:

  (setf (alist-get 'default gptel-directives)
        #'gptel-project-conventions)"
  (when-let ((root (project-root (project-current))))
    (with-memoization
        (alist-get root gptel-prompts--project-conventions-alist
                   nil nil #'equal)
      (let ((conven (file-name-concat root "CONVENTIONS.md"))
            (claude (file-name-concat root "CLAUDE.md")))
        (cond ((file-readable-p conven)
               (with-temp-buffer
                 (insert-file-contents conven)
                 (buffer-string)))
              ((file-readable-p claude)
               (with-temp-buffer
                 (insert-file-contents claude)
                 (buffer-string)))
              (t "Place your generic/fallback system message here."))))))

(provide 'gptel-prompts)
