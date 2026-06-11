{
  lib,
  fetchFromGitHub,
  applyPatches,
  mastodon,

  patches ? [ ],
  gemset ? ./gemset.nix,
  yarnMissingHashes ? ./missing-hashes.json,
  yarnHash ? "sha256-xJ13bSBARpDP/RWWQwnJji6+YPrTbmm49G7di4olLwk=",
}:

let
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "TheEssem";
      repo = "mastodon";
      rev = "5e88cbc5500d572d8a00a558f1e015ae09a0620d";
      hash = "sha256-f24QE+ZYMUodSCQRggiy0iFfbJsvQrI0r1OsqlPzGD0=";
    };
    inherit patches;
  };
in

(mastodon.override {
  pname = "chuckya";
  version = "0-unstable-2026-09-01";

  srcOverride = src;

  inherit gemset yarnMissingHashes yarnHash;
}).overrideAttrs
  {
    passthru = {
      updateScript = ./update.sh;

      # needed for nix-update
      inherit src;
    };

    meta = {
      description = "Close-to-upstream soft fork of Mastodon Glitch Edition";
      homepage = "https://github.com/TheEssem/mastodon";
      license = lib.licenses.agpl3Plus;
      maintainers = with lib.maintainers; [ defelo ];
    };
  }
