# gptel-prompts

I've been using GPTel a lot lately, for many different tasks, and I wanted a
better way to manage all the system prompts I've been accumulating. Customizing
`gptel-directives` directly works fine when you have a handful, but once you've
got dozens of prompts -- some with multi-turn conversations, some using
templating -- it gets unwieldy pretty fast.

So I wrote `gptel-prompts`, which lets you manage directives as individual files
in a directory. Each file becomes a named entry in `gptel-directives`, and
they're automatically reloaded when the files change.

## Getting started

```elisp
(use-package gptel-prompts
  :after (gptel)
  :demand t
  :config
  (gptel-prompts-update)
  ;; Ensure prompts are updated if prompt files change
  (gptel-prompts-add-update-watchers))
```

Put your prompt files in `gptel-prompts-directory` (defaults to
`"~/.emacs.d/prompts"`), and you're done. Whenever files change,
`gptel-prompts-update` refreshes `gptel-directives` automatically.

## Prompt formats

Each file in the prompts directory becomes a named directive. The filename (sans
extension) is the key. There are several supported formats:

### Plain text (`.txt`, `.md`, `.org`)

The file content is used directly as a system prompt string. This is the
simplest option -- just write your prompt and save it.

### Emacs Lisp (`.el`, `.eld`)

For `.eld` files, the content is read as a Lisp data structure -- a list of
strings and/or symbols, matching what `gptel-directives` expects. For `.el`
files, the content is evaluated as Emacs Lisp and should return the same kind of
list. See the `gptel-directives` documentation for the expected format.

### JSON (`.json`)

JSON files can contain either a simple string (used as a system prompt) or an
array of objects with `role` and `content` fields for multi-turn conversations.

### Prompt Poet (`.poet`, `.jinja`, `.j2`)

This is where it gets interesting. Based on [Prompt
Poet](https://github.com/character-ai/prompt-poet), these files are YAML with
Jinja templating. The templating is applied dynamically when the prompt is used,
so you can see the expansion results via GPTel's Inspect capabilities when
`gptel-expert-commands` is non-nil.

Here's an example:

```yaml
- role: system
  content: >-
    You are a Latin-American Spanish translator, spelling corrector and
    improver. I will speak to you in English, and you will translate and
    answer in the corrected and improved version of my text, in
    Latin-American Spanish.

- role: user
  content: |
    Please translate the following into Spanish. The time is {{ current_time }}:
```

Note the `>-` and `|` YAML content directives -- they control where newlines
appear in the actual prompts while keeping the source file readable.

You'll need the [yaml](https://elpa.gnu.org/packages/yaml.html) and
[templatel](https://github.com/emacs-love/templatel) packages installed to use
this format.

#### Template inheritance

Templatel's `extends` and `block` work here too. The base template needs to
produce valid YAML, and child templates should preserve YAML indentation in their
block overrides.

Set `gptel-prompts-template-base-directory` to control where base templates are
found. It accepts either a directory path or a function returning one, and
defaults to the prompt file's own directory.

#### Extending the templatel environment

You can replace the templatel environment entirely by setting
`gptel-prompts-get-template-env-function` to a function that takes a prompt and
optional file and returns a templatel environment.

Or, to extend the default environment, customize
`gptel-prompts-prepare-template-env-functions` with a list of functions that each
receive the environment. Here's an example adding a `nindent` filter (similar to
the Helm chart one):

```elisp
(defun my/templatel-filter-nindent (s n)
  "Add N spaces after each newline character."
  (let ((indent-string (make-string n ? )))
    (replace-regexp-in-string "\n" (concat "\n" indent-string) s)))

(defun my/prepare-gptel-prompts-templatel-env (env)
  (templatel-env-add-filter env "nindent" #'my/templatel-filter-nindent))

(setopt gptel-prompts-prepare-template-env-functions
  (list #'my/prepare-gptel-prompts-templatel-env))
```

## Project conventions

`gptel-prompts-project-conventions` is a handy function you can add to your
prompts (or use as a directive function) that reads project convention files --
`CONVENTIONS.md`, `CLAUDE.md`, or `AGENTS.md` -- from the current project root
and includes them in the prompt context. It's useful for giving the AI
project-specific guidance automatically.

## Development

The project uses Nix for reproducible builds. `nix develop` drops you into a
shell with everything you need, and `nix flake check` runs all the checks
(byte-compilation, linting, formatting, tests, and fuzzing).

There's also a `lefthook.yml` for pre-commit hooks that runs the same checks
locally before each commit.

Please let me know of any issues or feature requests through the GitHub issues
list!
