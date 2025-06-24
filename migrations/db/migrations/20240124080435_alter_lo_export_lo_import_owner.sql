-- migrate:up
alter function pg_catalog.lo_export owner to capitala_admin;
alter function pg_catalog.lo_import(text) owner to capitala_admin;
alter function pg_catalog.lo_import(text, oid) owner to capitala_admin;

-- migrate:down
