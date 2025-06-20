{ lib, stdenv, fetchurl, postgresql, bison, flex, perl, pkgs }:

# Apache AGE PostgreSQL Extension
# Based on nixpkgs implementation pattern
# Dependencies: bison, flex, perl (for keyword list generation)

let
  pgMajorStr = lib.versions.major postgresql.version;
  ageVersion = "1.5.0";

  ageSrcInfo =
    if pgMajorStr == "15" then {
      url = "https://dlcdn.apache.org/age/PG15/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-7iuLsE/XKgcLo48vzUpZBJcs67oJwoCL817RPAua8nA=";
      isSupported = true;
    } else if pgMajorStr == "16" then {
      url = "https://dlcdn.apache.org/age/PG16/${ageVersion}/apache-age-${ageVersion}-src.tar.gz";
      hash = "sha256-031wczk98cyqr1536h49f3mdjq4pmbbmbidp00s3sqmjc6z7yy5i";
      isSupported = true;
    } else {
      isSupported = false;
      url = "";
      hash = "";
    };
in
stdenv.mkDerivation rec {
  pname = "age";
  version = ageVersion;

  src = if ageSrcInfo.isSupported then fetchurl {
    url = ageSrcInfo.url;
    sha256 = ageSrcInfo.hash;
  } else pkgs.runCommand "fake-age-src-${pname}-${version}" {} "mkdir -p $out";

  # Following nixpkgs pattern: only essential build tools needed
  nativeBuildInputs = [ bison flex perl ];
  buildInputs = [ postgresql ];

  # Key fix: Set explicit tool paths in makeFlags (nixpkgs approach)
  makeFlags = [
    "USE_PGXS=1" 
    "PG_CONFIG=${postgresql}/bin/pg_config"
    # Critical: Explicit tool paths prevent "missing" script issues
    "BISON=${bison}/bin/bison"
    "FLEX=${flex}/bin/flex"
    "PERL=${perl}/bin/perl"
  ];

  installPhase = if ageSrcInfo.isSupported then ''
    runHook preInstall
    make install USE_PGXS=1 PG_CONFIG=${postgresql}/bin/pg_config
    runHook postInstall
  '' else ''
    echo "Skipping install for unsupported AGE/PG combination."
    mkdir -p $out/lib $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Apache AGE graph database extension for PostgreSQL";
    homepage = "https://age.apache.org/";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = [ maintainers.barneycook ];
    broken = !ageSrcInfo.isSupported;
  };
}