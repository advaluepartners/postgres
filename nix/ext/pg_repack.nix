{ lib
, stdenv
, fetchFromGitHub
, openssl
, postgresql
, postgresqlTestHook
, readline
, testers
, zlib
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "pg_repack";
  version = "1.5.2";

  buildInputs = postgresql.buildInputs ++ [ postgresql ];

  makeFlags = [ "USE_PGXS=1" ];

  src = fetchFromGitHub {
    owner = "reorg";
    repo = "pg_repack";
    rev = "ver_${finalAttrs.version}";
    hash = "sha256-wfjiLkx+S3zVrAynisX1GdazueVJ3EOwQEPcgUQt7eA=";
  };

  installPhase = ''
    install -D bin/pg_repack -t $out/bin/
    install -D lib/pg_repack${postgresql.dlSuffix} -t $out/lib/
    install -D lib/{pg_repack--${finalAttrs.version}.sql,pg_repack.control} -t $out/share/postgresql/extension
  '';

  passthru.tests = {
    version = testers.testVersion {
      package = finalAttrs.finalPackage;
    };
    extension = stdenv.mkDerivation {
      name = "plpgsql-check-test";
      dontUnpack = true;
      doCheck = true;
      buildInputs = [ postgresqlTestHook ];
      nativeCheckInputs = [ (postgresql.withPackages (ps: [ ps.pg_repack ])) ];
      postgresqlTestUserOptions = "LOGIN SUPERUSER";
      failureHook = "postgresqlStop";
      checkPhase = ''
        runHook preCheck
        psql -a -v ON_ERROR_STOP=1 -c "CREATE EXTENSION pg_repack;"
        runHook postCheck
      '';
      installPhase = "touch $out";
    };
  };

  meta = with lib; {
    description = "Reorganize tables in PostgreSQL databases with minimal locks";
    longDescription = ''
      pg_repack is a PostgreSQL extension which lets you remove bloat from tables and indexes, and optionally restore
      the physical order of clustered indexes. Unlike CLUSTER and VACUUM FULL it works online, without holding an
      exclusive lock on the processed tables during processing. pg_repack is efficient to boot,
      with performance comparable to using CLUSTER directly.
    '';
    homepage = "https://github.com/reorg/pg_repack";
    license = licenses.bsd3;
    inherit (postgresql.meta) platforms;
    mainProgram = "pg_repack";
  };
})
