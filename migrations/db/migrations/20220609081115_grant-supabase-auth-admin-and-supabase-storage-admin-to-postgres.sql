-- migrate:up

-- This is done so that the `postgres` role can manage auth tables triggers,
-- storage tables policies, etc. which unblocks the revocation of superuser
-- access.
--
-- More context: https://www.notion.so/capitala/RFC-Postgres-Permissions-I-40cb4f61bd4145fd9e75ce657c0e31dd#bf5d853436384e6e8e339d0a2e684cbb
grant capitala_auth_admin, capitala_storage_admin to postgres;

-- migrate:down
