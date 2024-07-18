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
                value = builtins.getAttr attr set;
              in
                "${attr}=${value}"
            ) (builtins.attrNames set)
          ) + "\n";
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
          "php.validate.executablePath" = lib.getExe pkgs.php83;
        };


        # Useful scripts
        shellScripts = [
          # A script meant to be run at when the repo is being set up
          # currently just creates keys and migrates
          (pkgs.writeShellApplication {
            name="env-setup";
            text=''
              # Test if docker runs
              if [ "$(pidof docker)" = "" ]; then
                echo """Docker is not running. Make sure that you run \"env-up\" in another terminal."""
                exit
              fi

              # Set laravel keys and migrate
              ./vendor/bin/sail exec --user root laravel.test php artisan passport:keys
              ./vendor/bin/sail exec --user root laravel.test php artisan migrate
            '';
          })

          # Starts the docker daemon, the sail daemon and vite. After CTRL+C on vite the daemons are killed again
          (pkgs.writeShellApplication {
            name = "env-up";
            text = ''
              # The function that is called on CTRL+C in the terminal
              function cleanup() {
                echo Cleaning up...
                pkill "$DOCKER_PID"
                exit
              }
              trap cleanup SIGINT


              # Install sail
              ${lib.getExe pkgs.php83Packages.composer} install

              # Run docker daemon
              # remove ">/dev/null 2>&1" for debugging, otherwise that info litters the terminal
              ${pkgs.docker}/bin/dockerd-rootless & #>/dev/null 2>&1 &
              DOCKER_PID="%last"

              
              # Wait for docker to boot
              sleep 3

              # Run sail container
              ./vendor/bin/sail up -d

              # Run install node modules
              ./vendor/bin/sail exec --user root laravel.test npm "install"
              # revert the package-lock changes
              ${lib.getExe pkgs.git} restore package-lock.json

              # Little hack to fix permissions in laravel storage
              if [ "$(stat -c "%a" ./storage)" != "777" ]; then
                echo "The ./storage directory does not have the 777 permission, without it the sail user in the container cannot write to it. Sudo is required to add it."
                sudo chmod -R 777 ./storage
              fi

              # run vite (This is listening to CTRL+C
              # It is run in root-shell of the container because of some permission issue
              ./vendor/bin/sail exec -T --user root laravel.test npm run dev
            '';
          })
        ];


        dotEnv = {
          APP_ENV = "local";
          APP_DEBUG= "true";
          APP_NAME = "Laravel-Sail-App";
          APP_URL = "http://0.0.0.0:8000"; # Using 8000 as its not a privileged port
          APP_PORT = "8000";
          APP_KEY = "base64:Igl3VDbdMSWnCDABL7k9ioK8hJ1EKgM25kh6vnxUntQ="; # This has to be set

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
          DB_HOST = "mariadb";
          DB_PORT = "3306"; # TODO: Use a slightly different port to allow other database services on the system
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

          # XDebug config
          SAIL_XDEBUG_MODE = "develop,debug,coverage";

          # Pusher variables (I don't use pusher, thats to disable the warning about 
          # them not being defined)
          PUSHER_APP_ID= "app-id";
          PUSHER_APP_KEY= "app-key";
          PUSHER_APP_SECRET= "app-secret";
        };


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

        devShells.default = pkgs.mkShell {
          # These git env variables define who is commiting
          GIT_AUTHOR_NAME = gitConfig.user.name;
          GIT_AUTHOR_EMAIL = gitConfig.user.email;
          GIT_COMMITTER_EMAIL = gitConfig.user.email;
          GIT_COMMITTER_NAME = gitConfig.user.name;

          # The packages exposed to the shell
          buildInputs =
            shellScripts ++
          [
            vscodiumWithExtensions
            
            pkgs.pre-commit
            pkgs.docker
            pkgs.git
          ];

          # Generate necessary files and create symlinks to them
          shellHook = ''
            export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
            alias sail="sh vendor/bin/sail"

            echo "Entering Laravel-Sail Dev Environment"

            # VSCodium user settings
            mkdir .vscode -p
            ln -fs ${writeJson vscodeUserSettings} .vscode/settings.json

            # Git exclude
            ln -fs "${writeList gitConfig.exclude}" .git/info/exclude

            # Pre commit config
            ln -fs "${writeYaml gitConfig.pre-commit-config}" .pre-commit-config.yaml
            pre-commit install

            # .env setup (This can't be a symlink, laravel does not like that)
            # I suppose converting a set to a string, writing that to nix store then reading that string from the store file
            # to echo it into another file is not the most straightforward method of doing that but who cares.
            echo -e "$(cat ${writeDotEnv dotEnv})" > .env
          '';
        };
      in
      {
        inherit devShells;
      }
    );
}