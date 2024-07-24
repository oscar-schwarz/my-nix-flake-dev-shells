{
  description = "A dev environment for a Nuxt project";

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
                # Add quotation marks to value if it contains spaces
                containsChar = char: str: builtins.any (c: c == char) (lib.strings.stringToCharacters str);
                raw = builtins.getAttr attr set;
                value = if containsChar " " raw then ("\"" + raw + "\"") else raw;
              in
                "${attr}=${value}"
            ) (builtins.attrNames set)
          ) + "\n";
        };

        # PROGRAMS
        nodejs = pkgs.nodejs_16;


        # VSCodium
        # Sets vscodium as the VSCode package and includes extensions
        vscodiumWithExtensions = pkgs.vscode-with-extensions.override {
          vscode = pkgs.vscodium;
          vscodeExtensions =
          let
            exts = inputs.nix-vscode-extensions.extensions.${system};
          in [
	          exts.open-vsx.vue.volar
          ];
        };

        # VSCodium user settings
        vscodeUserSettings = {
          "workbench.colorTheme" = "Solarized Dark";
          "files.exclude" = {
            "**/.git" = false;
          };
          "git.confirmSync" = false;
        };


        # Useful scripts
        shellScripts = [

          # Starts the docker daemon, the sail daemon and vite. After CTRL+C on vite the daemons are killed again
          (pkgs.writeShellApplication {
            name = "env-up";
            text = ''
              ${nodejs}/bin/npm install
              ${nodejs}/bin/npm run dev
            '';
          })
        ];


        dotEnv = {
          NUXT_PUBLIC_API_BASE = "https://beste.schule/api";
          NUXT_PUBLIC_OAUTH_AUTHORIZATION_URL = "https://beste.schule/oauth/authorize";
          NUXT_PUBLIC_OAUTH_REGISTRATION_URL = "https://beste.schule/oauth/join";
          NUXT_PUBLIC_OAUTH_TOKEN_URL = "https://beste.schule/oauth/token";
          NUXT_PUBLIC_BASE_URL = "http://localhost:3000";
          NUXT_PUBLIC_OAUTH_CLIENT_ID = "";
          NUXT_PUBLIC_OAUTH_CLIENT_ID_MOBILE = "";
          NUXT_PUBLIC_OAUTH_CALLBACK_URL = "http://localhost:3000/";
          NUXT_PUBLIC_OAUTH_CALLBACK_URL_MOBILE = "schule.beste:/";
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
          ];
        };

        # The actual shell config
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

            # You probably won't need these packages because 'env-up' should deal with them but here you go anyway
            nodejs # See above in 'env-up' for explanation
            pkgs.git
          ];

          # Generate necessary files and create symlinks to them
          shellHook = ''
            echo "Entering Nuxt Environment"

            # VSCodium user settings
            mkdir .vscode -p
            ln -fs ${writeJson vscodeUserSettings} .vscode/settings.json

            # Git exclude
            ln -fs "${writeList gitConfig.exclude}" .git/info/exclude

            # Also, only rewrite the .env if theres a change
            newEnvPath="${writeDotEnv dotEnv}"
            if [ "$(diff $newEnvPath .env)" != "" ]; then
              echo "Updating .env"
              echo -e "$(cat $newEnvPath)" > .env
            fi
            
          '';
        };
      in
      {
        inherit devShells;
      }
    );
}
