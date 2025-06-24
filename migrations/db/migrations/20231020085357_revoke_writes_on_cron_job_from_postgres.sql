-- migrate:up
do $$
begin
  if exists (select from pg_extension where extname = 'pg_cron') then
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  end if;
end $$;

-- Fix: Set the function owner to capitala_admin (superuser) to match the event trigger owner
CREATE OR REPLACE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;
    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;
    alter default privileges for user capitala_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user capitala_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user capitala_admin in schema cron grant all
        on functions to postgres with grant option;
    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;

-- Explicitly set the function owner to capitala_admin
ALTER FUNCTION extensions.grant_pg_cron_access() OWNER TO capitala_admin;

drop event trigger if exists issue_pg_cron_access;
CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();

-- migrate:down
