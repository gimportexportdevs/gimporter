{
  description = "Garmin ConnectIQ (MonkeyC) development environment for gimporter";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

  outputs = inputs:
    let
      lib = inputs.nixpkgs.lib;

      sdkVersion = "9.2.0";
      sdkRelease = "connectiq-sdk-lin-${sdkVersion}-2026-06-09-92a1605b2";

      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f {
        pkgs = import inputs.nixpkgs { inherit system; };
        inherit system;
      });

      # The Linux SDK: monkeyc & friends are Java, launched via bash scripts.
      # The simulator binaries are x86_64 ELF and won't run from the store on
      # NixOS anyway (use `make run` with an SDK-manager install for that);
      # this package is the compile/package toolchain.
      #
      # Note: monkeyc computes MB_HOME from $0 and regenerates
      # bin/default.jungle there on every run, so it cannot run directly from
      # the read-only store — the devShell exposes it through a writable
      # symlink shadow instead (see shellHook). That is also why the scripts
      # get their java calls patched to absolute paths rather than being
      # wrapped with wrapProgram (a wrapper would re-anchor $0 in the store).
      connectiqSdkFor = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "connectiq-sdk";
        version = sdkVersion;

        src = pkgs.fetchzip {
          url = "https://developer.garmin.com/downloads/connect-iq/sdks/${sdkRelease}.zip";
          stripRoot = false;
          hash = "sha256-SIiEE71WhEcg67JmT4iuKYfe/gbBVi35I1XPd/3xKlo=";
        };

        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r . $out
          runHook postInstall
        '';

        postFixup = ''
          # Some scripts (e.g. monkeym) ship without the executable bit
          for f in $out/bin/*; do
            if [ -f "$f" ] && grep -Iq '^#!' "$f"; then
              chmod +x "$f"
              sed -i 's|^\([[:space:]]*\)java |\1${pkgs.jdk}/bin/java |' "$f"
            fi
          done
          patchShebangs $out/bin
        '';
      };
    in
    {
      packages = forEachSupportedSystem ({ pkgs, system }:
        lib.optionalAttrs (lib.hasSuffix "linux" system) rec {
          connectiq-sdk = connectiqSdkFor pkgs;
          default = connectiq-sdk;
        });

      devShells = forEachSupportedSystem ({ pkgs, system }:
        let
          linux = lib.hasSuffix "linux" system;
          sdk = connectiqSdkFor pkgs;
        in
        {
          default = pkgs.mkShell ({
            packages = [ pkgs.jdk ];
          }
          # On darwin the SDK comes from the SDK manager; properties.mk
          # falls back to its current-sdk.cfg when SDK_HOME is unset.
          // lib.optionalAttrs linux {
            # monkeyc insists on writing bin/default.jungle next to its jar,
            # so give it a writable symlink shadow of the store SDK, keyed by
            # store hash so SDK updates get a fresh shadow.
            shellHook = ''
              sdk_shadow="''${XDG_CACHE_HOME:-$HOME/.cache}/gimporter/$(basename ${sdk})"
              if [ ! -d "$sdk_shadow" ]; then
                mkdir -p "$sdk_shadow"
                cp -rs ${sdk}/. "$sdk_shadow/"
                chmod -R u+w "$sdk_shadow"
                # monkeybrains resolves its jar's canonical path and writes
                # default.jungle next to the real file, so jars must be
                # real copies, not symlinks into the store
                for jar in "$sdk_shadow"/bin/*.jar; do
                  cp --remove-destination "$(readlink -f "$jar")" "$jar"
                done
              fi
              export SDK_HOME="$sdk_shadow"
            '';
          });
        });
    };
}
