{
  description = "gptel-prompts - Manage GPTel directives using files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        emacsWithDeps = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages
          (epkgs: with epkgs; [
            gptel
            yaml
            templatel
            package-lint
          ]);

        src = pkgs.lib.cleanSource ./.;

        runEmacsCheck = name: script: pkgs.runCommand "gptel-prompts-${name}" {
          nativeBuildInputs = [ emacsWithDeps ];
        } ''
          cp -r ${src}/. ./work
          chmod -R u+w ./work
          cd work
          ${script}
          touch $out
        '';
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "gptel-prompts";
          version = "1.0.0";
          inherit src;
          nativeBuildInputs = [ emacsWithDeps ];
          buildPhase = ''
            rm -f *.elc
            emacs --batch -L . \
              --eval "(setq byte-compile-error-on-warn t)" \
              -f batch-byte-compile gptel-prompts.el
          '';
          installPhase = ''
            mkdir -p $out/share/emacs/site-lisp
            cp gptel-prompts.el gptel-prompts.elc $out/share/emacs/site-lisp/
          '';
        };

        checks = {
          # Byte-compile with all warnings as errors
          byte-compile = runEmacsCheck "byte-compile" ''
            rm -f *.elc
            emacs --batch -L . \
              --eval "(setq byte-compile-error-on-warn t)" \
              -f batch-byte-compile gptel-prompts.el
          '';

          # Package-lint for packaging conventions
          lint = runEmacsCheck "lint" ''
            emacs --batch -L . \
              --eval "(require 'package-lint)" \
              -f package-lint-batch-and-exit gptel-prompts.el
          '';

          # Check code formatting matches Emacs standard indentation
          format = runEmacsCheck "format" ''
            emacs --batch \
              -L . \
              --eval "(progn
                        (dolist (file '(\"gptel-prompts.el\"
                                        \"test/gptel-prompts-test.el\"
                                        \"test/gptel-prompts-fuzz.el\"
                                        \"test/gptel-prompts-bench.el\"))
                          (when (file-exists-p file)
                            (find-file file)
                            (emacs-lisp-mode)
                            (let ((original (buffer-string)))
                              (indent-region (point-min) (point-max))
                              (delete-trailing-whitespace)
                              (unless (string= original (buffer-string))
                                (message \"Formatting differs: %s\" file)
                                (kill-emacs 1)))
                            (kill-buffer))))"
          '';

          # Run ERT unit tests
          test = runEmacsCheck "test" ''
            emacs --batch -L . -L test \
              -l ert \
              -l gptel-prompts-test \
              -f ert-run-tests-batch-and-exit
          '';

          # Run fuzz tests
          fuzz = runEmacsCheck "fuzz" ''
            emacs --batch -L . -L test \
              -l ert \
              -l gptel-prompts-fuzz \
              -f ert-run-tests-batch-and-exit
          '';

          # Full build with warnings as errors
          build = self.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            emacsWithDeps
            pkgs.lefthook
          ];
          shellHook = ''
            echo "gptel-prompts development shell"
            echo "  emacs    - Emacs with gptel, yaml, templatel, package-lint"
            echo "  lefthook - Git hooks manager"
            echo ""
            echo "Run 'lefthook install' to set up pre-commit hooks"
          '';
        };
      }
    );
}
