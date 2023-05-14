{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation rec {
  pname = "privatebin";
  version = "1.7.4";

  src = fetchFromGitHub {
    owner = "PrivateBin";
    repo = pname;
    rev = version;
    hash = "sha256-RFP6rhzfBzTmqs4eJXv7LqdniWoeBJpQQ6fLdoGd5Fk=";
  };

  installPhase = ''
    runHook preInstall
    cp -ar . $out
    runHook postInstall
  '';

  meta = with lib; {
    description = "Minimalist, open source online pastebin where the server has zero knowledge of pasted data";
    changelog = "https://github.com/PrivateBin/PrivateBin/blob/${version}/CHANGELOG.md";
    license = with licenses; [libpng gpl2 bsd3 mit cc-by-40];
    homepage = "https://privatebin.info/";
    platforms = platforms.all;
    maintainers = with maintainers; [e1mo defelo];
  };
}
