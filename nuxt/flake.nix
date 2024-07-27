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
        pkgs = import inputs.nixpkgs {
          system = system; 
          config = {
            allowUnfree = true; # Android studio
            android_sdk.accept_license = true; # Android SDK
          };
        };
        lib = pkgs.lib;

        android = {
          versions = {
            tools = "26.1.1";
            platformTools = "34.0.1";
            buildTools = "34.0.0";
            ndk = [ "22.1.7171670" "21.3.6528147" ];
            cmake = "3.18.1";
            emulator = "30.6.3";
          };

          platforms = [ "28" "29" "30" "34" ];
          abis = [ "armeabi-v7a" "arm64-v8a" ];
          extras = [ "extras;google;gcm" ];
        };

        androidSdk = (pkgs.androidenv.composeAndroidPackages {
            toolsVersion = android.versions.tools;
            platformToolsVersion = android.versions.platformTools;
            buildToolsVersions = [ android.versions.buildTools ];
            platformVersions = android.platforms;

            includeEmulator = false;
            includeSources = false;
            includeSystemImages = false;

            systemImageTypes = [ "google_apis_playstore" ];
            abiVersions = android.abis;
            cmakeVersions = [ android.versions.cmake ];

            includeNDK = false;
            useGoogleAPIs = false;
            useGoogleTVAddOns = false;
            includeExtras = android.extras;
        });

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
        nodejs = pkgs.nodejs_20;
        chromium = pkgs.ungoogled-chromium;


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

          # Starts the environment services
          (pkgs.writeShellApplication {
            name = "env-up";
            text = ''
              ${nodejs}/bin/npm install
              ${lib.getExe chromium} http:/localhost:3000 --auto-open-devtools-for-tabs &
              ${nodejs}/bin/npm run dev
            '';
          })

          (pkgs.writeShellApplication {
            name = "android-install";
            text = ''
              ${nodejs}/bin/npm run build --debug
              ${nodejs}/bin/npx cap sync android
              cd android
              export JAVA_HOME="${pkgs.jdk17}"
              export ANDROID_HOME="${androidSdk.androidsdk}/libexec/android-sdk"
              export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/${android.versions.buildTools}/aapt2"
              ./gradlew installDebug

              adb shell am start -n de.schulverwalter.beste/de.schulverwalter.beste.MainActivity
            '';
          })

          (pkgs.writeShellApplication {
            name = "chrome-extension";
            text = ''
              CHROME_VERSION=$(chromium --version | awk '{print $2;exit}')
              EXTENSION_ID="$1"
              URL="https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&prodversion=$CHROME_VERSION&x=id%3D$EXTENSION_ID%26installsource%3Dondemand%26uc"
              echo "$URL"
              chromium "$URL"
            '';
          })
        ];


        dotEnv = {
          NUXT_PUBLIC_API_BASE = "https://beste.schule/api";
          NUXT_PUBLIC_OAUTH_AUTHORIZATION_URL = "https://beste.schule/oauth/authorize";
          NUXT_PUBLIC_OAUTH_REGISTRATION_URL = "https://beste.schule/oauth/join";
          NUXT_PUBLIC_OAUTH_TOKEN_URL = "https://beste.schule/oauth/token";
          NUXT_PUBLIC_BASE_URL = "http://localhost:3000";
          NUXT_PUBLIC_OAUTH_CALLBACK_URL = "http://localhost:3000/login";
          NUXT_PUBLIC_OAUTH_CLIENT_ID = "106";
          NUXT_PUBLIC_OAUTH_CLIENT_ID_MOBILE = "105";
          NUXT_PUBLIC_OAUTH_CALLBACK_URL_MOBILE = "schule.beste:/login";
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
            ".vscode"
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
            nodejs
            chromium
            pkgs.git
            pkgs.android-tools
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
