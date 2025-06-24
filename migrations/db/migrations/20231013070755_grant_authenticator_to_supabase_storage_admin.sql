-- migrate:up
grant authenticator to capitala_storage_admin;
revoke anon, authenticated, service_role from capitala_storage_admin;

-- migrate:down
