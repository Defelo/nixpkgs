{
  lib,
  fetchFromGitHub,
  applyPatches,
  mastodon,

  patches ? [ ],
  gemset ? ./gemset.nix,
  yarnMissingHashes ? ./missing-hashes.json,
  yarnHash ? "sha256-6EzVYplwOpWrKblq9BStFxNEvVvVexUdwi1HWnmvaZg=",
}:

let
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "TheEssem";
      repo = "mastodon";
      rev = "2e34217489f218663f5d9f2e3b8362bc40cc4a10";
      hash = "sha256-x+2rmDlrKglHSnLFLitBMbWAjFOJBnNRfZChshxjgJc=";
    };
    inherit patches;
  };
in

(mastodon.override {
  pname = "chuckya";
  version = "0-unstable-2026-09-23";

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
