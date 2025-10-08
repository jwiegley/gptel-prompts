# Manage GPTel directives (aka prompts)

This package offers an alternative way to manage your `gptel-directives`
variable, using files rather than customizing the variable directly.

You can get started using the following configuration:

```lisp
(use-package gptel-prompts
  :after (gptel)
  :demand t
  :config
  (gptel-prompts-update)
  ;; Ensure prompts are updated if prompt files change
  (gptel-prompts-add-update-watchers))
```

Whenever your prompt files change, you must arrange for `gptel-prompts-update`
to be called, which will update `gptel-directives` appropriately.

## Different prompt types

You may now put prompts, one per file, in the directory
`gptel-prompts-directory`, which by default is `"~/.emacs.d/prompts"`. Prompts
may be one of three different kinds:

### Plain text

If the file extension is `.txt`, `.md` or `.org`, the content of the file is
used directly, as if you had added that string to `gptel-directives`.

### Emacs Lisp lists

If the file extension is `.el`, the file must evaluate to a list of strings
and/or symbols, as expected by `gptel-directives`. Please see the
documentation of that variable for more information.

### Prompt Poet templates

Based on the standard set by [Prompt Poet](https://github.com/character-ai/prompt-poet),
files ending in `.poet` or `.jinja` will be interpreted as YAML files using
Jinja templating. The templating is applied first, before it is parsed as a
YAML file.

This is done dynamically, at the time the prompt is used, so you can see the
results of your expansion using GPTel’s Inspect capabilities when
`gptel-expert-commands` is set to a non-nil value. Here is an example poet
prompt.:

```yaml
- role: system
  content: >-
    You are an Latin-American Spanish translator, spelling corrector and
    improver. I will speak to you in English, and you will translate and
    answer in the corrected and improved version of my text, in Latin-American
    Spanish. I want you to replace my simplified A0-level words and sentences
    with more beautiful and elegant, upper level Latin-American Spanish words
    and sentences. Keep the meaning same, but make them more literary and
    clear. I want you to only reply with the correction, the improvements and
    nothing else, do not write explanations.

- role: user
  content: |
    Please translate the following into Spanish. The time is {{ current_time }}:
```

Note the `>-` and `|` content directives, which are used to manage when and
where newlines appear in the actual prompts, while allowing the file itself to
use what is easiest to maintain in the editor.

NOTE: If you wish to use the Prompt Poet format, you will need to install the
Emacs dependencies [yaml](https://elpa.gnu.org/packages/yaml.html) and
[templatel](https://github.com/emacs-love/templatel).

Using `templatel` template inheritance with `extends` and `block` requires
creating a base template that generates a valid YAML file. Block statements on
child templates should be written so that YAML indentation is not broken,
otherwise a YAML parse error is raised.

Extending the `templatel` environment is provided by customizing the variable
`gptel-prompts-template-env-prepare-functions` with a list of functions, each
function receives the `templatel` environment. Here is an example of adding a
`templatel` filter named `nindent` which indents the string according to the
provided number of characters `n`, similar to the Helm chart `nindent` filter.

```elisp
(defun my/templatel-filter-nindent (s n)
  "Adds `n' spaces after each newline character."
  (let ((indent-string (make-string n ? )))
    (replace-regexp-in-string "\n" (concat "\n" indent-string) s)))

(defun my/prepare-gptel-prompts-templatel-env (env)
  (templatel-env-add-filter env "nindent" #'my/templatel-filter-nindent))

(setopt gptel-prompts-template-env-prepare-functions
  (list #'my/prepare-gptel-prompts-templatel-env))
```

Example usage:

base.md:

```yaml
- role: system
  content: >-
    base for prompt
    {% block content %}{% endblock %}
```

test.poet:

```
{% extends "base.md" %}

{% block content %}{{ "hello

world some
prompt text here

" | nindent(4) }}{% endblock %}
```
