{
  description = "A dev environment for a project with Laravel and Vue";

  inputs = {
    # Nix packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # VSCode extension from marketplace and vscode oss
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # for "eachDefaultSystem"
    flake-utils.follows = "nix-vscode-extensions/flake-utils";
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        # Aliases that simulate a module
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        # Functions
        writeJson = set: pkgs.writeTextFile {
          name = "filename"; # this does not need to be unique
          text = builtins.toJSON set;
        };
        writeList = list: pkgs.writeTextFile {
          name = "filename";
          text = lib.concatStringsSep "\n" list;
        };
        writeYaml = set: pkgs.writeTextFile {
          name = "filename";
          text = lib.generators.toYAML {} set;
        };
        writeDotEnv = set: pkgs.writeTextFile {
          name = "filename";
          text = builtins.concatStringsSep "\n" (
            map (attr: 
              let
                # Just quote all values, won't hurt
                value = "\"" + (builtins.getAttr attr set) + "\"";
              in
                "${attr}=${value}"
            ) (builtins.attrNames set)
          );
        };


        # VSCodium
        # Sets vscodium as the VSCode package and includes extensions
        vscodiumWithExtensions = pkgs.vscode-with-extensions.override {
          vscode = pkgs.vscodium;
          vscodeExtensions =
          let
            vscodeExtensions = inputs.nix-vscode-extensions.extensions.${system};
          in [
            vscodeExtensions.vscode-marketplace.xdebug.php-debug
          ];
        };

        # VSCodium user settings
        vscodeUserSettings = {
          "workbench.colorTheme" = "Default Dark+";
          "files.exclude" = {
            "**/.git" = false;
          };
          "php.validate.executablePath" = lib.getExe php;
        };


        # PHP
        phpPackageName = "php83";
        php = pkgs.${phpPackageName};
        composer = pkgs.${"${phpPackageName}Packages"}.composer;
        # Some common extensions used in many projects
        phpExtensions = with pkgs.${"${phpPackageName}Extensions"}; [
          dom
          curl
          bcmath
          pdo
          tokenizer
          mbstring
          mysqli
        ];


        # NodeJS
        nodejs = pkgs.nodejs;


        # Useful scripts
        shellScripts = [
          # Run install on the package managers
          (pkgs.writeShellApplication {
            name = "env-install";
            text = ''
              ${lib.getExe composer} install

              # Some node modules need this python version
              PATH="${pkgs.python311Full}/bin:$PATH"
              ${nodejs}/bin/npm install --loglevel verbose
            '';
          })

          # One time setup environment
          (pkgs.writeShellApplication {
            name = "env-setup";
            text = ''
              ${lib.getExe php} artisan key:generate
              ${lib.getExe php} artisan migrate
            '';
          })

          # Starting all processes and killing them again after CTRL+C
          (pkgs.writeShellApplication {
            name = "env-up";
            text = ''
              # Laravel Server
              ${lib.getExe php} artisan serve &
              ARTISAN_PID="%last"

              # Main process is vite, which can be stopped using CTRL+C
              ${nodejs}/bin/npm run dev

              # After vite was stopped kill the processes
              echo "Stopping services..."
              pkill -P "$ARTISAN_PID"
              exit
            '';
          })
        ];


        # Git config
        # This config structure is just for readability
        # The actual assignments happen below
        gitConfig = {
          user = {
            email = "schwarz.oscar@protonmail.com";
            name = "Oscar Schwarz";
          };
          exclude = [
            ".envrc"
            ".direnv"
            ".pre-commit-config.yaml"
            ".mariadb"
          ];
          pre-commit-config = {
            repos = [
              {
                repo = "https://github.com/pre-commit/pre-commit-hooks";
                rev = "v3.2.0";
                hooks = [
                  # {
                  #   id = "trailing-whitespace";
                  # }
                  {
                    id = "end-of-file-fixer";
                  }
                  {
                    id = "check-yaml";
                  }
                  {
                    id = "check-added-large-files";
                  }
                  {
                    id = "no-commit-to-branch";
                    args = [
                      "--branch" "master"
                      "--branch" "main"
                      "--branch" "production"
                    ];
                  }
                ];
              }
              {
                repo = "local";
                hooks = [
                  {
                    id = "check-types-ts";
                    name = "Check export type declaration order";
                    entry = "./scripts/check-types-ts";
                    language = "script";
                    files = "^resources/js/types\\.ts$";
                  }
                ];
              }
            ];
          };
        };

        dotEnv = {
          APP_NAME = "Laravel-App";
          APP_URL = "http://127.0.0.1:8000";

          TOKEN_VALID = "14";
          TOKEN_LENGTH = "16";

          SESSION_LIFETIME = "30";
          MIX_SESSION_LIFETIME = "30";

          API_VERSION = "0.3";

          RATE_LIMIT = "60";

          LOG_CHANNEL = "stack";
          LOG_STACK_CHANNELS = "daily";
          LOG_LEVEL = "debug"; #emergency, alert, critical, error, warning, notice, info, or debug

          DB_CONNECTION = "mysql";
          DB_HOST = "127.0.0.1";
          DB_PORT = "3306";
          DB_DATABASE = "database";
          DB_USERNAME = "user";
          DB_PASSWORD = "user";

          PLAN_SCHULE_URL = "http://plan.schule";

          # Whether report generation is dispatched async (default true).
          # Use false for debugging to catch break points in ReportProcessor
          REPORT_DISPATCH_ASYNC = "true";

          # For debugging: Allows to execute large reports without writing the result to cache
          # This allows to read the reports' SQL queries in the API response
          REPORT_BYPASS_CACHE = "false";

          # Report queue
          QUEUE_CONNECTION = "database";
        };

        devShells.default = pkgs.mkShell {
          # These git env variables define who is commiting
          GIT_AUTHOR_NAME = gitConfig.user.name;
          GIT_AUTHOR_EMAIL = gitConfig.user.email;
          GIT_COMMITTER_EMAIL = gitConfig.user.email;
          GIT_COMMITTER_NAME = gitConfig.user.name;

          # The packages exposed to the shell
          buildInputs =
            phpExtensions ++
            shellScripts ++
          [
            php
            composer
            nodejs

            pkgs.pre-commit
          ];

          # Generate necessary files and create symlinks to them
          shellHook = ''
            # VSCodium user settings
            mkdir .vscode -p
            ln -fs ${writeJson vscodeUserSettings} .vscode/settings.json

            # Git exclude
            ln -fs "${writeList gitConfig.exclude}" .git/info/exclude

            # Pre commit config
            ln -fs "${writeYaml gitConfig.pre-commit-config}" .pre-commit-config.yaml
            pre-commit install

            # .env setup
            ln -fs "${writeDotEnv dotEnv}" .env

            echo "Entering Laravel-Vue Dev Environment"
          '';
        };
      in
      {
        inherit devShells;
      }
    );
}