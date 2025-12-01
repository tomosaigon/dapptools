# This file was extracted from overlay.nix in order to provide access
# to our Haskell package extensions from other overlays, bypassing the
# rest of our overlay.  This was necessary for rather obscure reasons.

{ pkgs, lib }:

let
  stdenv = pkgs.stdenv;

in self-hs: super-hs:
  let
    dontCheck = x: y:
      pkgs.haskell.lib.dontCheck
        (self-hs.callCabal2nix x y {});

    sbv_prepatch = pkgs.haskell.lib.dontCheck (self-hs.callCabal2nix "sbv"
      (builtins.fetchGit {
        url = "https://github.com/LeventErkok/sbv";
        rev = "59c1cf37070a5423113f950bf071804257756c7a";
      }) 
      {inherit (pkgs) z3;});

  in {
    restless-git = dontCheck "restless-git" (./src/restless-git);
    wreq = pkgs.haskell.lib.doJailbreak super-hs.wreq;

    # we use a pretty bleeding edge sbv version
    sbv = sbv_prepatch.overrideAttrs (attrs: {
      postPatch = ''
      sed -i -e 's|"z3"|"${pkgs.z3}/bin/z3"|' Data/SBV/Provers/Z3.hs
      sed -i -e 's|"cvc4"|"${pkgs.cvc4}/bin/cvc4"|' Data/SBV/Provers/CVC4.hs'';
      configureFlags = attrs.configureFlags ++ [
        "--ghc-option=-O2"
      ];

    });


    # This package is somewhat unmaintained and doesn't compile with GHC 8.4,
    # so we have to use a GitHub fork that fixes it.
    semver-range = super-hs.semver-range;

    # hevm: built from ./src/hevm, no docs, no tests (legacy solc),
    # then wrapped with extra tools on PATH.
    hevm =
      let
        base = self-hs.callCabal2nix "hevm" (./src/hevm) {
          # Haskell libs with the same names as C libs...
          # Depend on the C libs, not the Haskell libs.
          # These are system deps, not Cabal deps.
          inherit (pkgs) secp256k1;
          ff = pkgs.libff;
        };

        noDocs  = pkgs.haskell.lib.dontHaddock base;
        noTests = pkgs.haskell.lib.dontCheck   noDocs;
      in
        noTests.overrideAttrs (attrs: {
          postInstall = ''
            wrapProgram $out/bin/hevm --prefix PATH \
              : "${lib.makeBinPath (with pkgs; [ bash coreutils git solc ])}"
          '';

          # ensure wrapProgram is available
          nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];
        });
  }
