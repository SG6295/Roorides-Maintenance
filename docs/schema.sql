--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO supabase_admin;

--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA extensions;


ALTER SCHEMA extensions OWNER TO postgres;

--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql;


ALTER SCHEMA graphql OWNER TO supabase_admin;

--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA graphql_public;


ALTER SCHEMA graphql_public OWNER TO supabase_admin;

--
-- Name: pg_net; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_net; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_net IS 'Async HTTP';


--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: pgbouncer
--

CREATE SCHEMA pgbouncer;


ALTER SCHEMA pgbouncer OWNER TO pgbouncer;

--
-- Name: realtime; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA realtime;


ALTER SCHEMA realtime OWNER TO supabase_admin;

--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO supabase_admin;

--
-- Name: supabase_migrations; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA supabase_migrations;


ALTER SCHEMA supabase_migrations OWNER TO postgres;

--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA vault;


ALTER SCHEMA vault OWNER TO supabase_admin;

--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: aal_level; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.aal_level AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE auth.aal_level OWNER TO supabase_auth_admin;

--
-- Name: code_challenge_method; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.code_challenge_method AS ENUM (
    's256',
    'plain'
);


ALTER TYPE auth.code_challenge_method OWNER TO supabase_auth_admin;

--
-- Name: factor_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_status AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE auth.factor_status OWNER TO supabase_auth_admin;

--
-- Name: factor_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.factor_type AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE auth.factor_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_authorization_status; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_authorization_status AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE auth.oauth_authorization_status OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_client_type AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE auth.oauth_client_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_registration_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_registration_type AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE auth.oauth_registration_type OWNER TO supabase_auth_admin;

--
-- Name: oauth_response_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.oauth_response_type AS ENUM (
    'code'
);


ALTER TYPE auth.oauth_response_type OWNER TO supabase_auth_admin;

--
-- Name: one_time_token_type; Type: TYPE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TYPE auth.one_time_token_type AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE auth.one_time_token_type OWNER TO supabase_auth_admin;

--
-- Name: issue_category; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_category AS ENUM (
    'Mechanical',
    'Electrical',
    'Body',
    'Tyre',
    'GPS',
    'AdBlue',
    'Other'
);


ALTER TYPE public.issue_category OWNER TO postgres;

--
-- Name: issue_severity; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_severity AS ENUM (
    'Minor',
    'Major'
);


ALTER TYPE public.issue_severity OWNER TO postgres;

--
-- Name: issue_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_status AS ENUM (
    'Open',
    'Done',
    'Blocked'
);


ALTER TYPE public.issue_status OWNER TO postgres;

--
-- Name: job_card_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.job_card_status AS ENUM (
    'Open',
    'Completed',
    'Completed - Invoice Pending'
);


ALTER TYPE public.job_card_status OWNER TO postgres;

--
-- Name: outsource_part_disposition; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outsource_part_disposition AS ENUM (
    'returned_to_nvs',
    'retained_by_vendor',
    'retained_by_vendor_with_credit'
);


ALTER TYPE public.outsource_part_disposition OWNER TO postgres;

--
-- Name: rating_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.rating_enum AS ENUM (
    'Good',
    'Ok',
    'Bad'
);


ALTER TYPE public.rating_enum OWNER TO postgres;

--
-- Name: scrap_exclusion_reason; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_exclusion_reason AS ENUM (
    'consumable',
    'destroyed_on_removal',
    'retained_by_vendor',
    'other'
);


ALTER TYPE public.scrap_exclusion_reason OWNER TO postgres;

--
-- Name: scrap_item_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_item_status AS ENUM (
    'in_storage',
    'sent_for_refurbishment',
    'refurbished',
    'sold',
    'written_off',
    'reversed'
);


ALTER TYPE public.scrap_item_status OWNER TO postgres;

--
-- Name: scrap_payment_mode; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_payment_mode AS ENUM (
    'cash',
    'upi',
    'bank_transfer',
    'cheque',
    'other'
);


ALTER TYPE public.scrap_payment_mode OWNER TO postgres;

--
-- Name: scrap_writeoff_reason; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_writeoff_reason AS ENUM (
    'lost',
    'damaged_unsaleable',
    'hazmat_disposal',
    'stocktake_adjustment',
    'donated',
    'other'
);


ALTER TYPE public.scrap_writeoff_reason OWNER TO postgres;

--
-- Name: sla_status_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.sla_status_enum AS ENUM (
    'Pending',
    'Adhered',
    'Violated',
    'NA'
);


ALTER TYPE public.sla_status_enum OWNER TO postgres;

--
-- Name: ticket_status_new; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.ticket_status_new AS ENUM (
    'New',
    'Accepted',
    'Work In Progress',
    'Resolved',
    'Closed',
    'Rejected'
);


ALTER TYPE public.ticket_status_new OWNER TO postgres;

--
-- Name: work_type_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.work_type_enum AS ENUM (
    'InHouse',
    'Outsource'
);


ALTER TYPE public.work_type_enum OWNER TO postgres;

--
-- Name: action; Type: TYPE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TYPE realtime.action AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE',
    'TRUNCATE',
    'ERROR'
);


ALTER TYPE realtime.action OWNER TO supabase_realtime_admin;

--
-- Name: equality_op; Type: TYPE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TYPE realtime.equality_op AS ENUM (
    'eq',
    'neq',
    'lt',
    'lte',
    'gt',
    'gte',
    'in',
    'like',
    'ilike',
    'is',
    'match',
    'imatch',
    'isdistinct'
);


ALTER TYPE realtime.equality_op OWNER TO supabase_realtime_admin;

--
-- Name: user_defined_filter; Type: TYPE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TYPE realtime.user_defined_filter AS (
	column_name text,
	op realtime.equality_op,
	value text,
	negate boolean
);


ALTER TYPE realtime.user_defined_filter OWNER TO supabase_realtime_admin;

--
-- Name: wal_column; Type: TYPE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TYPE realtime.wal_column AS (
	name text,
	type_name text,
	type_oid oid,
	value jsonb,
	is_pkey boolean,
	is_selectable boolean
);


ALTER TYPE realtime.wal_column OWNER TO supabase_realtime_admin;

--
-- Name: wal_rls; Type: TYPE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TYPE realtime.wal_rls AS (
	wal jsonb,
	is_rls_enabled boolean,
	subscription_ids uuid[],
	errors text[]
);


ALTER TYPE realtime.wal_rls OWNER TO supabase_realtime_admin;

--
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE storage.buckettype OWNER TO supabase_storage_admin;

--
-- Name: email(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.email() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION auth.email() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION email(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.email() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION auth.jwt() OWNER TO supabase_auth_admin;

--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION auth.role() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION role(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.role() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: supabase_auth_admin
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION auth.uid() OWNER TO supabase_auth_admin;

--
-- Name: FUNCTION uid(); Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON FUNCTION auth.uid() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';


--
-- Name: grant_pg_cron_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_cron_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
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

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
    revoke trigger on cron.job_run_details from postgres;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_cron_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_cron_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_cron_access() IS 'Grants access to pg_cron';


--
-- Name: grant_pg_graphql_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_graphql_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
begin
    if not exists (
        select 1
        from pg_catalog.pg_event_trigger_ddl_commands() ev
        join pg_catalog.pg_extension e on ev.objid = e.oid
        where e.extname = 'pg_graphql'
    ) then
        return;
    end if;

    drop function if exists graphql_public.graphql;
    create or replace function graphql_public.graphql(
        "operationName" text default null,
        query text default null,
        variables jsonb default null,
        extensions jsonb default null
    )
        returns jsonb
        language sql
        set search_path to ''
    as $$
        select graphql.resolve(
            query := query,
            variables := coalesce(variables, '{}'),
            "operationName" := "operationName",
            extensions := extensions
        );
    $$;

    -- Attach the wrapper to the extension so DROP EXTENSION cascades to it,
    -- which in turn triggers set_graphql_placeholder to reinstall the "not enabled" stub.
    alter extension pg_graphql add function graphql_public.graphql(text, text, jsonb, jsonb);

    grant usage on schema graphql to postgres, anon, authenticated, service_role;
    grant execute on function graphql.resolve to postgres, anon, authenticated, service_role;
    grant usage on schema graphql to postgres with grant option;
    grant usage on schema graphql_public to postgres with grant option;
end;
$_$;


ALTER FUNCTION extensions.grant_pg_graphql_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_graphql_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_graphql_access() IS 'Grants access to pg_graphql';


--
-- Name: grant_pg_net_access(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.grant_pg_net_access() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8.0', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION extensions.grant_pg_net_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION grant_pg_net_access(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.grant_pg_net_access() IS 'Grants access to pg_net';


--
-- Name: pgrst_ddl_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_ddl_watch() OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION extensions.pgrst_drop_watch() OWNER TO supabase_admin;

--
-- Name: set_graphql_placeholder(); Type: FUNCTION; Schema: extensions; Owner: supabase_admin
--

CREATE FUNCTION extensions.set_graphql_placeholder() RETURNS event_trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
            set search_path to ''
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


ALTER FUNCTION extensions.set_graphql_placeholder() OWNER TO supabase_admin;

--
-- Name: FUNCTION set_graphql_placeholder(); Type: COMMENT; Schema: extensions; Owner: supabase_admin
--

COMMENT ON FUNCTION extensions.set_graphql_placeholder() IS 'Reintroduces placeholder function for graphql_public.graphql';


--
-- Name: graphql(text, text, jsonb, jsonb); Type: FUNCTION; Schema: graphql_public; Owner: supabase_admin
--

CREATE FUNCTION graphql_public.graphql("operationName" text DEFAULT NULL::text, query text DEFAULT NULL::text, variables jsonb DEFAULT NULL::jsonb, extensions jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;


ALTER FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) OWNER TO supabase_admin;

--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: supabase_admin
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


ALTER FUNCTION pgbouncer.get_auth(p_usename text) OWNER TO supabase_admin;

--
-- Name: acceptance_deadline(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.acceptance_deadline(p_created_at timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_sla_days INT;
BEGIN
    SELECT COALESCE(value::int, 2) INTO v_sla_days
      FROM system_settings WHERE key = 'acceptance_sla_days';
    IF v_sla_days IS NULL THEN v_sla_days := 2; END IF;

    RETURN add_working_days(p_created_at, v_sla_days);
END;
$$;


ALTER FUNCTION public.acceptance_deadline(p_created_at timestamp with time zone) OWNER TO postgres;

--
-- Name: add_part_to_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_part_to_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.add_part_to_inventory() OWNER TO postgres;

--
-- Name: add_working_days(timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_local      timestamp;
    v_date       date;
    v_time       time;
    days_added   int := 0;
    iterations   int := 0;
    weekly_offs  jsonb;
    dow          int;
    is_holiday   boolean;
BEGIN
    IF start_ts IS NULL OR n_days IS NULL THEN
        RETURN NULL;
    END IF;

    v_local := start_ts AT TIME ZONE 'Asia/Kolkata';
    v_date  := v_local::date;
    v_time  := v_local::time;

    SELECT value::jsonb INTO weekly_offs
      FROM system_settings WHERE key = 'sla_weekly_offs';
    IF weekly_offs IS NULL THEN weekly_offs := '[0,6]'::jsonb; END IF;

    WHILE days_added < n_days LOOP
        -- Guard against a configuration that marks every day an off-day: without this the
        -- loop never terminates and the trigger hangs whatever transaction called it.
        iterations := iterations + 1;
        IF iterations > 3650 THEN
            RAISE EXCEPTION
                'add_working_days: no working day found within 10 years of %. Check system_settings.sla_weekly_offs (currently %) - every weekday may be marked an off-day.',
                start_ts, weekly_offs;
        END IF;

        v_date := v_date + 1;
        dow := EXTRACT(DOW FROM v_date)::int;

        -- Skip weekly offs (day-of-week integers: 0=Sun ... 6=Sat)
        IF weekly_offs @> to_jsonb(dow) THEN CONTINUE; END IF;

        -- Skip holidays
        SELECT EXISTS (SELECT 1 FROM holidays WHERE date = v_date) INTO is_holiday;
        IF is_holiday THEN CONTINUE; END IF;

        days_added := days_added + 1;
    END LOOP;

    RETURN (v_date + v_time) AT TIME ZONE 'Asia/Kolkata';
END;
$$;


ALTER FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer) OWNER TO postgres;

--
-- Name: adjust_part_inventory_on_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.adjust_part_inventory_on_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    IF NEW.part_id = OLD.part_id THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity - OLD.quantity);
    ELSE
        PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, -OLD.quantity);
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.adjust_part_inventory_on_update() OWNER TO postgres;

--
-- Name: apply_part_stock_delta(uuid, uuid, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_available numeric;
    v_part      text;
    v_location  text;
BEGIN
    IF p_location_id IS NULL THEN
        RAISE EXCEPTION 'Cannot change stock without a workshop location.';
    END IF;

    INSERT INTO public.part_stock (part_id, location_id, quantity)
    VALUES (p_part_id, p_location_id, 0)
    ON CONFLICT (part_id, location_id) DO NOTHING;

    SELECT quantity INTO v_available
    FROM   public.part_stock
    WHERE  part_id = p_part_id AND location_id = p_location_id
    FOR UPDATE;

    IF v_available + p_delta < 0 THEN
        SELECT name INTO v_part     FROM public.parts              WHERE id = p_part_id;
        SELECT name INTO v_location FROM public.workshop_locations WHERE id = p_location_id;
        RAISE EXCEPTION 'Not enough stock: % has % available at %, needed %.',
            COALESCE(v_part, 'part'), v_available, COALESCE(v_location, 'this location'), abs(p_delta);
    END IF;

    UPDATE public.part_stock
    SET    quantity = quantity + p_delta,
           updated_at = now()
    WHERE  part_id = p_part_id AND location_id = p_location_id;
END;
$$;


ALTER FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric) OWNER TO postgres;

--
-- Name: calculate_issue_sla_dynamic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_issue_sla_dynamic() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    rule_days INTEGER;
BEGIN
    -- Recalculate on INSERT, or on UPDATE when category/severity actually changed.
    IF TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND (
           NEW.category  IS DISTINCT FROM OLD.category OR
           NEW.severity  IS DISTINCT FROM OLD.severity
       ))
    THEN
        SELECT sla_days INTO rule_days
        FROM sla_rules_config
        WHERE category = NEW.category AND severity = NEW.severity;

        IF rule_days IS NULL THEN rule_days := 3; END IF;

        NEW.sla_days := rule_days;
        -- created_at is `timestamp without time zone` holding UTC; name the zone rather
        -- than relying on the session default.
        NEW.sla_end_date := add_working_days(NEW.created_at AT TIME ZONE 'UTC', rule_days);
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_issue_sla_dynamic() OWNER TO postgres;

--
-- Name: calculate_ticket_overall_sla(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_ticket_overall_sla() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_final_sla   timestamptz;
    v_status      text;
    v_resolved_at timestamptz;
BEGIN
    UPDATE tickets
    SET final_sla_end_date = (
        SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id
    )
    WHERE id = NEW.ticket_id
    RETURNING final_sla_end_date, status::text,
              COALESCE(resolved_at, closed_at) AT TIME ZONE 'UTC'
    INTO v_final_sla, v_status, v_resolved_at;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, now())
                THEN 'Adhered'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < now()
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.ticket_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.calculate_ticket_overall_sla() OWNER TO postgres;

--
-- Name: cancel_stock_audit(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancel_stock_audit(p_audit_id uuid, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role   text;
    v_name   text;
    v_status text;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can cancel a stock audit.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status NOT IN ('counting', 'review') THEN
        RAISE EXCEPTION 'Only an audit still in progress can be cancelled. This one is %.', v_status;
    END IF;

    UPDATE public.stock_audits
    SET status            = 'cancelled',
        cancelled_by      = auth.uid(),
        cancelled_by_name = COALESCE(v_name, ''),
        cancelled_at      = now(),
        cancel_reason     = NULLIF(btrim(COALESCE(p_reason, '')), '')
    WHERE id = p_audit_id;
END;
$$;


ALTER FUNCTION public.cancel_stock_audit(p_audit_id uuid, p_reason text) OWNER TO postgres;

--
-- Name: check_pan_exists(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_pan_exists(p_pan text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM suppliers WHERE upper(trim(pan_number)) = upper(trim(p_pan))
  );
$$;


ALTER FUNCTION public.check_pan_exists(p_pan text) OWNER TO postgres;

--
-- Name: close_job_card_with_scrap(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card              job_cards%ROWTYPE;
    v_decision              jsonb;
    v_issue_part_id         uuid;
    v_action                text;
    v_scrap_ids             uuid[] := '{}';
    v_exclusion_ids         uuid[] := '{}';
    v_reversed_scrap_ids    uuid[] := '{}';
    v_reversed_id           uuid;
    v_new_id                uuid;
    v_issue_part_ids        uuid[];
    v_group_a_ids           uuid[];
    v_required_part_ids     uuid[];
    v_decision_part_ids     uuid[];
    v_missing_ids           uuid[];
    v_extra_ids             uuid[];
    v_extra_permanent_ids   uuid[];
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can close job cards.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id = p_job_card_id AND status = 'Open';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_FOUND_OR_NOT_OPEN',
            'error_message', 'Job card not found or is not currently Open.',
            'details',       null
        )::text;
    END IF;

    IF v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_REQUIRED',
            'error_message', 'Outsource job cards require an invoice before closure.',
            'details',       null
        )::text;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.issues
        WHERE  job_card_id = p_job_card_id
          AND  status <> 'Done'::issue_status
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'ISSUES_NOT_DONE',
            'error_message', 'All issues must be marked Done before closing the job card.',
            'details',       null
        )::text;
    END IF;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_issue_part_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_group_a_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id
      AND  public.get_blocking_scrap_for_issue_part(ip.id) IS NOT NULL;

    SELECT coalesce(array_agg(id), '{}')
    INTO   v_required_part_ids
    FROM   unnest(v_issue_part_ids) AS id
    WHERE  id != ALL(v_group_a_ids);

    SELECT coalesce(array_agg((d->>'issue_part_id')::uuid), '{}')
    INTO   v_decision_part_ids
    FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d;

    SELECT array_agg(id)
    INTO   v_extra_permanent_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id = ANY(v_group_a_ids);

    IF v_extra_permanent_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART_PERMANENT_SCRAP',
            'error_message', 'A decision was provided for a part whose scrap has already been permanently recorded. Remove it from the decisions array.',
            'details',       json_build_object('extra_part_ids', v_extra_permanent_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_missing_ids
    FROM   unnest(v_required_part_ids) AS id
    WHERE  id != ALL(v_decision_part_ids);

    IF v_missing_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_MISSING_PART',
            'error_message', 'A part was added to this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('missing_part_ids', v_missing_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_extra_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id != ALL(v_issue_part_ids);

    IF v_extra_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART',
            'error_message', 'A part was removed from this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('extra_part_ids', v_extra_ids)
        )::text;
    END IF;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        IF v_action = 'exclude' AND (v_decision->>'exclusion_reason') IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_REASON',
                'error_message', 'Exclusion reason is required for excluded parts.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF v_action = 'scrap'
           AND v_job_card.type = 'Outsource'
           AND (v_decision->>'outsource_disposition') IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_DISPOSITION',
                'error_message', 'Outsource disposition is required for scrapped parts on Outsource job cards.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit' THEN
            IF (v_decision->>'outsource_credit_amount') IS NULL
               OR (v_decision->>'outsource_credit_amount')::numeric <= 0
            THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_CREDIT_AMOUNT',
                    'error_message', 'Credit amount must be a positive number when disposition is "retained by vendor with credit".',
                    'details',       json_build_object('issue_part_id', v_issue_part_id)
                )::text;
            END IF;
        END IF;
    END LOOP;

    UPDATE public.job_cards
    SET    status       = 'Completed',
           completed_at = now(),
           remarks      = p_remarks
    WHERE  id = p_job_card_id;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        FOR v_reversed_id IN
            UPDATE public.scrap_inventory
            SET    status     = 'reversed',
                   updated_at = now(),
                   updated_by = auth.uid()
            WHERE  source_issue_part_id = v_issue_part_id
              AND  status = 'in_storage'
            RETURNING id
        LOOP
            v_reversed_scrap_ids := v_reversed_scrap_ids || v_reversed_id;
        END LOOP;

        IF v_action = 'scrap' THEN

            IF v_job_card.type = 'Outsource' THEN
                UPDATE public.issue_parts
                SET    outsource_part_disposition     = (v_decision->>'outsource_disposition')::outsource_part_disposition,
                       outsource_vendor_credit_amount =
                           CASE
                               WHEN (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                               THEN (v_decision->>'outsource_credit_amount')::numeric
                               ELSE NULL
                           END
                WHERE  id = v_issue_part_id;
            END IF;

            INSERT INTO public.scrap_inventory (
                source_ticket_id, source_job_card_id, source_issue_id,
                source_issue_part_id, source_vehicle_number,
                part_id_snapshot, part_name_snapshot, part_number_snapshot,
                quantity_snapshot, unit_snapshot, status,
                outsource_part_disposition_snapshot,
                outsource_vendor_credit_amount_snapshot, created_by
            )
            SELECT
                i.ticket_id, jc.id, ip.issue_id, ip.id, jc.vehicle_number,
                p.id, p.name, p.part_number, ip.quantity_used, p.unit,
                'in_storage'::scrap_item_status,
                CASE WHEN jc.type = 'Outsource'
                     THEN (v_decision->>'outsource_disposition')::outsource_part_disposition
                     ELSE NULL END,
                CASE WHEN jc.type = 'Outsource'
                          AND (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                     THEN (v_decision->>'outsource_credit_amount')::numeric
                     ELSE NULL END,
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_scrap_ids := v_scrap_ids || v_new_id;

        ELSIF v_action = 'exclude' THEN

            INSERT INTO public.scrap_excluded_parts (
                source_job_card_id, source_issue_id, source_issue_part_id,
                part_id_snapshot, part_name_snapshot, quantity_snapshot,
                reason, notes, excluded_by
            )
            SELECT
                jc.id, ip.issue_id, ip.id, p.id, p.name, ip.quantity_used,
                (v_decision->>'exclusion_reason')::scrap_exclusion_reason,
                v_decision->>'exclusion_notes',
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_exclusion_ids := v_exclusion_ids || v_new_id;

        END IF;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'job_card_id',        p_job_card_id,
        'scrap_entry_ids',    v_scrap_ids,
        'exclusion_ids',      v_exclusion_ids,
        'reversed_scrap_ids', v_reversed_scrap_ids
    );
END;
$$;


ALTER FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) OWNER TO postgres;

--
-- Name: close_job_card_with_scrap(uuid, text, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card              job_cards%ROWTYPE;
    v_decision              jsonb;
    v_issue_part_id         uuid;
    v_action                text;
    v_scrap_ids             uuid[] := '{}';
    v_exclusion_ids         uuid[] := '{}';
    v_reversed_scrap_ids    uuid[] := '{}';
    v_reversed_id           uuid;
    v_new_id                uuid;
    v_issue_part_ids        uuid[];
    v_group_a_ids           uuid[];
    v_required_part_ids     uuid[];
    v_decision_part_ids     uuid[];
    v_missing_ids           uuid[];
    v_extra_ids             uuid[];
    v_extra_permanent_ids   uuid[];
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can close job cards.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id = p_job_card_id AND status = 'Open';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_FOUND_OR_NOT_OPEN',
            'error_message', 'Job card not found or is not currently Open.',
            'details',       null
        )::text;
    END IF;

    IF NOT p_invoice_pending AND v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_REQUIRED',
            'error_message', 'Outsource job cards require an invoice before closure.',
            'details',       null
        )::text;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.issues
        WHERE  job_card_id = p_job_card_id
          AND  status <> 'Done'::issue_status
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'ISSUES_NOT_DONE',
            'error_message', 'All issues must be marked Done before closing the job card.',
            'details',       null
        )::text;
    END IF;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_issue_part_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_group_a_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id
      AND  public.get_blocking_scrap_for_issue_part(ip.id) IS NOT NULL;

    SELECT coalesce(array_agg(id), '{}')
    INTO   v_required_part_ids
    FROM   unnest(v_issue_part_ids) AS id
    WHERE  id != ALL(v_group_a_ids);

    SELECT coalesce(array_agg((d->>'issue_part_id')::uuid), '{}')
    INTO   v_decision_part_ids
    FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d;

    SELECT array_agg(id)
    INTO   v_extra_permanent_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id = ANY(v_group_a_ids);

    IF v_extra_permanent_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART_PERMANENT_SCRAP',
            'error_message', 'A decision was provided for a part whose scrap has already been permanently recorded. Remove it from the decisions array.',
            'details',       json_build_object('extra_part_ids', v_extra_permanent_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_missing_ids
    FROM   unnest(v_required_part_ids) AS id
    WHERE  id != ALL(v_decision_part_ids);

    IF v_missing_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_MISSING_PART',
            'error_message', 'A part was added to this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('missing_part_ids', v_missing_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_extra_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id != ALL(v_issue_part_ids);

    IF v_extra_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART',
            'error_message', 'A part was removed from this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('extra_part_ids', v_extra_ids)
        )::text;
    END IF;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        IF v_action = 'exclude' AND (v_decision->>'exclusion_reason') IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_REASON',
                'error_message', 'Exclusion reason is required for excluded parts.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF v_action = 'scrap'
           AND v_job_card.type = 'Outsource'
           AND (v_decision->>'outsource_disposition') IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_DISPOSITION',
                'error_message', 'Outsource disposition is required for scrapped parts on Outsource job cards.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit' THEN
            IF (v_decision->>'outsource_credit_amount') IS NULL
               OR (v_decision->>'outsource_credit_amount')::numeric <= 0
            THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_CREDIT_AMOUNT',
                    'error_message', 'Credit amount must be a positive number when disposition is "retained by vendor with credit".',
                    'details',       json_build_object('issue_part_id', v_issue_part_id)
                )::text;
            END IF;
        END IF;
    END LOOP;

    UPDATE public.job_cards
    SET    status       = CASE WHEN p_invoice_pending
                               THEN 'Completed - Invoice Pending'::public.job_card_status
                               ELSE 'Completed'::public.job_card_status
                          END,
           completed_at = now(),
           remarks      = p_remarks
    WHERE  id = p_job_card_id;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        FOR v_reversed_id IN
            UPDATE public.scrap_inventory
            SET    status     = 'reversed',
                   updated_at = now(),
                   updated_by = auth.uid()
            WHERE  source_issue_part_id = v_issue_part_id
              AND  status = 'in_storage'
            RETURNING id
        LOOP
            v_reversed_scrap_ids := v_reversed_scrap_ids || v_reversed_id;
        END LOOP;

        IF v_action = 'scrap' THEN

            IF v_job_card.type = 'Outsource' THEN
                UPDATE public.issue_parts
                SET    outsource_part_disposition     = (v_decision->>'outsource_disposition')::outsource_part_disposition,
                       outsource_vendor_credit_amount =
                           CASE
                               WHEN (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                               THEN (v_decision->>'outsource_credit_amount')::numeric
                               ELSE NULL
                           END
                WHERE  id = v_issue_part_id;
            END IF;

            INSERT INTO public.scrap_inventory (
                source_ticket_id, source_job_card_id, source_issue_id,
                source_issue_part_id, source_vehicle_number,
                part_id_snapshot, part_name_snapshot, part_number_snapshot,
                quantity_snapshot, unit_snapshot, status,
                outsource_part_disposition_snapshot,
                outsource_vendor_credit_amount_snapshot, created_by
            )
            SELECT
                i.ticket_id, jc.id, ip.issue_id, ip.id, jc.vehicle_number,
                p.id, p.name, p.part_number, ip.quantity_used, p.unit,
                'in_storage'::scrap_item_status,
                CASE WHEN jc.type = 'Outsource'
                     THEN (v_decision->>'outsource_disposition')::outsource_part_disposition
                     ELSE NULL END,
                CASE WHEN jc.type = 'Outsource'
                          AND (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                     THEN (v_decision->>'outsource_credit_amount')::numeric
                     ELSE NULL END,
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_scrap_ids := v_scrap_ids || v_new_id;

        ELSIF v_action = 'exclude' THEN

            INSERT INTO public.scrap_excluded_parts (
                source_job_card_id, source_issue_id, source_issue_part_id,
                part_id_snapshot, part_name_snapshot, quantity_snapshot,
                reason, notes, excluded_by
            )
            SELECT
                jc.id, ip.issue_id, ip.id, p.id, p.name, ip.quantity_used,
                (v_decision->>'exclusion_reason')::scrap_exclusion_reason,
                v_decision->>'exclusion_notes',
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_exclusion_ids := v_exclusion_ids || v_new_id;

        END IF;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'job_card_id',        p_job_card_id,
        'scrap_entry_ids',    v_scrap_ids,
        'exclusion_ids',      v_exclusion_ids,
        'reversed_scrap_ids', v_reversed_scrap_ids
    );
END;
$$;


ALTER FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean) OWNER TO postgres;

--
-- Name: complete_stock_audit(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_stock_audit(p_audit_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role        text;
    v_name        text;
    v_status      text;
    v_location    uuid;
    r             RECORD;
    v_live        numeric;
    v_unit_value  numeric;
    v_total       integer := 0;
    v_var_parts   integer := 0;
    v_net_units   numeric := 0;
    v_net_value   numeric := 0;
    v_unvalued    integer := 0;
    v_unexplained integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can complete a stock audit.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Only an audit under review can be completed. This one is %.', v_status;
    END IF;

    SELECT count(*) INTO v_unexplained
    FROM   public.stock_audit_items
    WHERE  audit_id = p_audit_id AND variance <> 0 AND reason IS NULL;

    IF v_unexplained > 0 THEN
        RAISE EXCEPTION '% mismatch(es) still need a reason before the audit can be completed.', v_unexplained;
    END IF;

    FOR r IN
        SELECT * FROM public.stock_audit_items
        WHERE  audit_id = p_audit_id
        ORDER  BY part_name_snapshot
    LOOP
        SELECT quantity INTO v_live
        FROM   public.part_stock
        WHERE  part_id = r.part_id AND location_id = v_location;
        v_live := COALESCE(v_live, 0);

        -- Latest purchase price per unit, net of discount and before GST — the same
        -- arithmetic purchase_invoice_items.line_total uses.
        SELECT (pii.quantity * pii.unit_price - pii.discount_amount) / NULLIF(pii.quantity, 0)
        INTO   v_unit_value
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = r.part_id
        ORDER  BY pi.invoice_date DESC, pi.created_at DESC
        LIMIT  1;

        IF COALESCE(r.variance, 0) <> 0 THEN
            -- apply_part_stock_delta guards this too, but it cannot know the count is
            -- what pushed the workshop negative, so check here for a usable message.
            IF v_live + r.variance < 0 THEN
                RAISE EXCEPTION 'Cannot write off % of "%": only % left at this workshop after activity during the audit. Re-count that part and run a fresh audit.',
                    abs(r.variance), r.part_name_snapshot, v_live;
            END IF;

            PERFORM public.apply_part_stock_delta(r.part_id, v_location, r.variance);

            v_var_parts := v_var_parts + 1;
            v_net_units := v_net_units + r.variance;

            IF v_unit_value IS NULL THEN
                v_unvalued := v_unvalued + 1;
            ELSE
                v_net_value := v_net_value + round(r.variance * v_unit_value, 2);
            END IF;
        END IF;

        UPDATE public.stock_audit_items
        SET moved_during_audit  = v_live - r.system_qty,
            applied_delta       = COALESCE(r.variance, 0),
            final_qty           = v_live + COALESCE(r.variance, 0),
            unit_value_snapshot = v_unit_value,
            variance_value      = CASE
                                      WHEN v_unit_value IS NULL THEN NULL
                                      ELSE round(COALESCE(r.variance, 0) * v_unit_value, 2)
                                  END
        WHERE id = r.id;

        v_total := v_total + 1;
    END LOOP;

    UPDATE public.stock_audits
    SET status            = 'completed',
        completed_by      = auth.uid(),
        completed_by_name = COALESCE(v_name, ''),
        completed_at      = now(),
        total_parts       = v_total,
        variance_parts    = v_var_parts,
        net_units         = v_net_units,
        net_value         = v_net_value,
        unvalued_parts    = v_unvalued
    WHERE id = p_audit_id;

    RETURN p_audit_id;
END;
$$;


ALTER FUNCTION public.complete_stock_audit(p_audit_id uuid) OWNER TO postgres;

--
-- Name: deduct_part_from_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.deduct_part_from_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card_type text;
    v_location_id   uuid;
BEGIN
    SELECT jc.type, jc.location_id INTO v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        RETURN NEW;
    END IF;

    PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, -NEW.quantity_used);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.deduct_part_from_inventory() OWNER TO postgres;

--
-- Name: delete_invoice_items_first(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_invoice_items_first() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    DELETE FROM public.purchase_invoice_items WHERE invoice_id = OLD.id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_invoice_items_first() OWNER TO postgres;

--
-- Name: delete_issue_part_with_scrap_check(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_blocking_scrap jsonb;
    v_reversed_ids   uuid[] := '{}';
    v_reversed_id    uuid;
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can remove parts.',
            'details',       null
        )::text;
    END IF;

    -- (b) Detect permanent-status scrap that would be orphaned by the delete
    SELECT public.get_blocking_scrap_for_issue_part(p_issue_part_id)
    INTO   v_blocking_scrap;

    IF v_blocking_scrap IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'SCRAP_BLOCKING_DELETE',
            'error_message', 'Cannot remove this part — the associated scrap record has been '
                             || (v_blocking_scrap->>'status')
                             || ' and cannot be undone.',
            'details',       v_blocking_scrap
                             || jsonb_build_object('issue_part_id', p_issue_part_id)
        )::text;
    END IF;

    -- (c) Auto-reverse any in_storage scrap entries for this part line.
    FOR v_reversed_id IN
        UPDATE public.scrap_inventory
        SET    status     = 'reversed',
               updated_at = now(),
               updated_by = auth.uid()
        WHERE  source_issue_part_id = p_issue_part_id
          AND  status = 'in_storage'
        RETURNING id
    LOOP
        v_reversed_ids := v_reversed_ids || v_reversed_id;
    END LOOP;

    -- (d) Delete the issue_part.  The existing trigger restores inventory stock.
    DELETE FROM public.issue_parts WHERE id = p_issue_part_id;

    RETURN jsonb_build_object(
        'success',               true,
        'deleted_issue_part_id', p_issue_part_id,
        'reversed_scrap_ids',    v_reversed_ids
    );
END;
$$;


ALTER FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) OWNER TO postgres;

--
-- Name: evaluate_acceptance_sla(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) RETURNS public.sla_status_enum
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_deadline timestamptz;
BEGIN
    SELECT COALESCE(acceptance_sla_end_date, acceptance_deadline(created_at AT TIME ZONE 'UTC'))
      INTO v_deadline
      FROM tickets WHERE id = p_ticket_id;

    IF p_first_issue_created <= v_deadline THEN
        RETURN 'Adhered'::sla_status_enum;
    ELSE
        RETURN 'Violated'::sla_status_enum;
    END IF;
END;
$$;


ALTER FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) OWNER TO postgres;

--
-- Name: finalize_outsource_invoice(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card job_cards%ROWTYPE;
    v_invoice  outsource_invoices%ROWTYPE;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can finalize outsource invoices.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id     = p_job_card_id
      AND  status = 'Completed - Invoice Pending'
      AND  type   = 'Outsource';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_ELIGIBLE',
            'error_message', 'Job card not found or is not an Outsource card with status "Completed - Invoice Pending".',
            'details',       null
        )::text;
    END IF;

    IF v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_FILE_REQUIRED',
            'error_message', 'An invoice file must be uploaded before finalizing.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_invoice
    FROM   public.outsource_invoices
    WHERE  job_card_id = p_job_card_id;

    IF NOT FOUND
       OR v_invoice.invoice_no       IS NULL
       OR v_invoice.invoice_value    IS NULL
       OR v_invoice.approved_amount  IS NULL
       OR v_invoice.advance_amount   IS NULL
       OR v_invoice.date_of_activity IS NULL
       OR v_invoice.payby_date       IS NULL
       OR v_invoice.payment_status   IS NULL
       OR v_invoice.paid_by          IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Invoice details are incomplete. Please fill in all required fields before finalizing.',
            'details',       null
        )::text;
    END IF;

    UPDATE public.job_cards
    SET    status  = 'Completed',
           remarks = coalesce(p_remarks, remarks)
    WHERE  id = p_job_card_id;

    RETURN json_build_object(
        'success',     true,
        'job_card_id', p_job_card_id
    );
END;
$$;


ALTER FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text) OWNER TO postgres;

--
-- Name: generate_issue_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_issue_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    ticket_num INTEGER;
    issue_count INTEGER;
BEGIN
    SELECT COALESCE(ticket_number, 0) INTO ticket_num FROM tickets WHERE id = NEW.ticket_id;
    SELECT COUNT(*) + 1 INTO issue_count FROM issues WHERE ticket_id = NEW.ticket_id;
    NEW.issue_number := 'T-' || ticket_num || '-' || LPAD(issue_count::text, 2, '0');
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.generate_issue_number() OWNER TO postgres;

--
-- Name: get_blocking_scrap_for_issue_part(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT jsonb_build_object(
        'is_blocking',           true,
        'scrap_inventory_id',    si.id,
        'part_name',             si.part_name_snapshot,
        'status',                si.status,
        'downstream_record_type', CASE
            WHEN si.status = 'sold'                  THEN 'disposal'
            WHEN si.status = 'written_off'           THEN 'writeoff'
            WHEN si.status IN ('refurbished',
                               'sent_for_refurbishment') THEN 'refurbishment'
            ELSE NULL
        END,
        'downstream_record_id', CASE
            WHEN si.status = 'sold' THEN (
                SELECT sdi.disposal_id
                FROM   public.scrap_disposal_items sdi
                WHERE  sdi.scrap_inventory_id = si.id
                LIMIT  1
            )
            WHEN si.status = 'written_off' THEN (
                SELECT swi.writeoff_id
                FROM   public.scrap_writeoff_items swi
                WHERE  swi.scrap_inventory_id = si.id
                LIMIT  1
            )
            ELSE NULL
        END
    )
    FROM  public.scrap_inventory si
    WHERE si.source_issue_part_id = p_issue_part_id
      AND si.status IN (
              'sold', 'written_off',
              'refurbished', 'sent_for_refurbishment'
          )
    LIMIT 1
$$;


ALTER FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) OWNER TO postgres;

--
-- Name: get_maintenance_stats(date, date, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_maintenance_stats(start_date_input date DEFAULT NULL::date, end_date_input date DEFAULT NULL::date, site_filter text DEFAULT NULL::text) RETURNS TABLE(total_tickets bigint, status_new bigint, status_pending bigint, status_accepted bigint, status_wip bigint, status_resolved bigint, status_closed bigint, status_rejected bigint, status_completed bigint, major_total bigint, major_electrical bigint, major_mechanical bigint, major_body bigint, major_tyre bigint, minor_total bigint, minor_electrical bigint, minor_mechanical bigint, minor_body bigint, minor_tyre bigint, type_in_house bigint, type_outsource bigint, accept_pending bigint, accept_adhered bigint, accept_violated bigint, accept_na bigint, comp_in_wip_within bigint, comp_in_adhered bigint, comp_in_violated bigint, comp_in_na bigint, comp_out_wip_within bigint, comp_out_adhered bigint, comp_out_violated bigint, comp_out_na bigint, rating_pending bigint, rating_collected bigint, rating_good bigint, rating_ok bigint, rating_bad bigint, csat_score_sum bigint, total_completed_tickets bigint)
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  WITH ticket_data AS (
    SELECT
      t.id,
      t.status,
      t.created_at,
      t.resolved_at,
      t.closed_at,
      t.final_sla_end_date,
      t.overall_sla_status,
      t.acceptance_sla_status,
      CASE
        WHEN t.overall_sla_status = 'NA' THEN 'NA'
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND now() > t.final_sla_end_date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_overall,
      CASE
        WHEN t.acceptance_sla_status = 'NA' THEN 'NA'
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND t.acceptance_sla_end_date IS NOT NULL
             AND now() > t.acceptance_sla_end_date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_accept,
      CASE
        WHEN EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'Outsource')
         AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'InHouse')
        THEN 'Outsource'
        ELSE 'InHouse'
      END AS dominant_work_type
    FROM tickets t
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  )
  SELECT
    COUNT(*)::BIGINT AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_pending,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT AS status_accepted,
    COUNT(*) FILTER (WHERE td.status = 'Work In Progress')::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT AS status_rejected,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS status_completed,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major')::BIGINT AS major_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Electrical')::BIGINT AS major_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Mechanical')::BIGINT AS major_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Body')::BIGINT AS major_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Tyre')::BIGINT AS major_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor')::BIGINT AS minor_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Electrical')::BIGINT AS minor_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Mechanical')::BIGINT AS minor_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Body')::BIGINT AS minor_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Tyre')::BIGINT AS minor_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'InHouse')::BIGINT AS type_in_house,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'Outsource')::BIGINT AS type_outsource,

    COUNT(*) FILTER (WHERE td.eff_accept = 'Pending')::BIGINT AS accept_pending,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Adhered')::BIGINT AS accept_adhered,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Violated')::BIGINT AS accept_violated,
    COUNT(*) FILTER (WHERE td.eff_accept = 'NA')::BIGINT AS accept_na,

    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'NA'       AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_na,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'NA'       AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_na,

    (SELECT COUNT(*) FROM issue_data
      JOIN ticket_data td2 ON td2.id = issue_data.ticket_id
      WHERE issue_data.rating IS NULL AND td2.status IN ('Resolved', 'Closed'))::BIGINT AS rating_pending,
    (SELECT COUNT(*) FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS rating_collected,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Good')::BIGINT AS rating_good,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Ok')::BIGINT AS rating_ok,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Bad')::BIGINT AS rating_bad,
    (SELECT COALESCE(SUM(CASE WHEN rating = 'Good' THEN 2 WHEN rating = 'Ok' THEN 1 ELSE 0 END), 0)
       FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS csat_score_sum,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS total_completed_tickets

  FROM ticket_data td;

END;
$$;


ALTER FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) OWNER TO postgres;

--
-- Name: get_outsource_invoice_summary(text[], text[], date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_outsource_invoice_summary(p_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date) RETURNS TABLE(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid) AS total_paid
        FROM   outsource_invoice_payments
        GROUP  BY outsource_invoice_id
    )
    SELECT
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_paid, 0)
            )
        ) FILTER (WHERE
            COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        ), 0)                                                    AS total_unpaid_payable,

        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        )                                                        AS overdue_count,

        COUNT(*) FILTER (WHERE oi.payment_status = 'Hold')      AS pending_approval_count

    FROM  outsource_invoices     oi
    JOIN  job_cards              jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE jc.status = 'Completed'
      AND (p_payment_status IS NULL OR oi.payment_status   = ANY(p_payment_status))
      AND (p_paid_by        IS NULL OR oi.paid_by          = ANY(p_paid_by))
      AND (p_date_from      IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to        IS NULL OR oi.date_of_activity <= p_date_to)
$$;


ALTER FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) OWNER TO postgres;

--
-- Name: guard_job_card_location_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guard_job_card_location_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_consumed integer;
BEGIN
    IF NEW.location_id IS NOT DISTINCT FROM OLD.location_id THEN
        RETURN NEW;
    END IF;

    IF NEW.type = 'Outsource' THEN
        RETURN NEW;
    END IF;

    SELECT count(*) INTO v_consumed
    FROM   public.issue_parts ip
    JOIN   public.issues      i ON i.id = ip.issue_id
    WHERE  i.job_card_id = NEW.id;

    IF v_consumed > 0 THEN
        RAISE EXCEPTION
            'This job card cannot be moved to another workshop: % part(s) have already been issued from the current one. Remove the parts first, or leave the card where it is.',
            v_consumed;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.guard_job_card_location_change() OWNER TO postgres;

--
-- Name: is_maintenance_exec(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_maintenance_exec() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec', 'super_admin')
  )
$$;


ALTER FUNCTION public.is_maintenance_exec() OWNER TO postgres;

--
-- Name: is_super_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_super_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'super_admin'
  )
$$;


ALTER FUNCTION public.is_super_admin() OWNER TO postgres;

--
-- Name: job_card_site_accessible_to_user(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.job_cards jc
        WHERE jc.id = p_job_card_id
          AND jc.site IN (
              SELECT s.name
              FROM public.user_sites us
              JOIN public.sites s ON s.id = us.site_id
              WHERE us.user_id = auth.uid()
          )
    );
$$;


ALTER FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) OWNER TO postgres;

--
-- Name: move_invoice_stock_on_location_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.move_invoice_stock_on_location_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    r RECORD;
BEGIN
    IF NEW.location_id IS NOT DISTINCT FROM OLD.location_id THEN
        RETURN NEW;
    END IF;

    FOR r IN
        SELECT part_id, quantity FROM public.purchase_invoice_items WHERE invoice_id = NEW.id
    LOOP
        PERFORM public.apply_part_stock_delta(r.part_id, OLD.location_id, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, NEW.location_id,  r.quantity);
    END LOOP;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.move_invoice_stock_on_location_change() OWNER TO postgres;

--
-- Name: recalculate_open_slas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recalculate_open_slas() RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    -- Issue deadlines. Scoped by BOTH the issue and its ticket: production carries a
    -- handful of issues left Open on tickets that were long since Resolved or Rejected,
    -- and a rule edit should not resurrect deadlines on work nobody is doing.
    --
    -- Every open issue is recomputed, not just those matching the rule that changed.
    -- Recomputation reads each issue's own current rule, so rows the edit did not touch
    -- come out unchanged - it is idempotent, and far simpler than working out which rows
    -- a given configuration change could have affected.
    UPDATE issues i
    SET sla_days     = r.sla_days,
        sla_end_date = add_working_days(i.created_at AT TIME ZONE 'UTC', r.sla_days)
    FROM tickets t, sla_rules_config r
    WHERE i.ticket_id = t.id
      AND r.category  = i.category
      AND r.severity  = i.severity
      AND i.status <> 'Done'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');

    -- Acceptance deadlines, for tickets still waiting to be accepted. Once acceptance has
    -- been judged Adhered or Violated the measurement stands.
    UPDATE tickets t
    SET acceptance_sla_end_date = acceptance_deadline(t.created_at AT TIME ZONE 'UTC')
    WHERE t.acceptance_sla_status = 'Pending'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');

    -- The issue UPDATE above fires trg_update_ticket_sla_agg, which rolls each changed
    -- sla_end_date up into tickets.final_sla_end_date and re-derives overall_sla_status.
    -- Nothing further is needed here.
END;
$$;


ALTER FUNCTION public.recalculate_open_slas() OWNER TO postgres;

--
-- Name: recalculate_ticket_sla_on_status_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recalculate_ticket_sla_on_status_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_final_sla   timestamptz;
    v_resolved_at timestamptz;
BEGIN
    SELECT final_sla_end_date, COALESCE(resolved_at, closed_at) AT TIME ZONE 'UTC'
    INTO v_final_sla, v_resolved_at
    FROM tickets WHERE id = NEW.id;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, now())
                THEN 'Adhered'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < now()
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.recalculate_ticket_sla_on_status_change() OWNER TO postgres;

--
-- Name: record_scrap_disposal(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_disposal_id       uuid;
    v_item              jsonb;
    v_scrap_id          uuid;
    v_item_id           uuid;
    v_disposal_item_ids uuid[] := '{}';
    v_payment_mode      text;
    v_total_value       numeric(10,2);
    v_items_sum         numeric(10,2) := 0;
    v_scrap_ids         uuid[];
    v_bad_items         jsonb := '[]'::jsonb;
    v_dup_check         uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap disposals.',
            'details',       null
        )::text;
    END IF;

    -- (b) buyer_name must be non-empty
    IF trim(coalesce(p_header->>'buyer_name', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_BUYER_NAME',
            'error_message', 'Buyer name is required.',
            'details',       null
        )::text;
    END IF;

    -- (c) payment_mode must be a valid enum value
    v_payment_mode := p_header->>'payment_mode';
    IF v_payment_mode NOT IN ('cash', 'upi', 'bank_transfer', 'cheque', 'other') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_PAYMENT_MODE',
            'error_message', 'Invalid payment mode.',
            'details',       json_build_object('received', v_payment_mode)
        )::text;
    END IF;

    -- (d) non-cash payments require a non-empty payment_reference
    IF v_payment_mode <> 'cash'
       AND trim(coalesce(p_header->>'payment_reference', '')) = ''
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_PAYMENT_REFERENCE',
            'error_message', 'Payment reference is required for non-cash payments.',
            'details',       json_build_object('payment_mode', v_payment_mode)
        )::text;
    END IF;

    -- (e) receipt_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_RECEIPT_PHOTO',
            'error_message', 'At least one receipt photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (f) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (g) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

    -- Check for non-existent or wrong-status IDs in one pass
    SELECT jsonb_agg(json_build_object('id', si.id::text, 'status', si.status::text))
    INTO v_bad_items
    FROM public.scrap_inventory si
    WHERE si.id = ANY(v_scrap_ids)
      AND si.status <> 'in_storage';

    IF (
        SELECT count(*)
        FROM unnest(v_scrap_ids) AS rid
        WHERE NOT EXISTS (SELECT 1 FROM public.scrap_inventory WHERE id = rid)
    ) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap inventory IDs do not exist.',
            'details',       json_build_object('offending_items', coalesce(v_bad_items, '[]'::jsonb))
        )::text;
    END IF;

    IF v_bad_items IS NOT NULL AND jsonb_array_length(v_bad_items) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap items are not in_storage status.',
            'details',       json_build_object('offending_items', v_bad_items)
        )::text;
    END IF;

    -- (h) no duplicate scrap_inventory_id in p_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;
        IF v_scrap_id = ANY(v_dup_check) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'DUPLICATE_SCRAP_ITEM',
                'error_message', 'The same scrap item appears more than once.',
                'details',       json_build_object('duplicate_id', v_scrap_id)
            )::text;
        END IF;
        v_dup_check := v_dup_check || v_scrap_id;
    END LOOP;

    -- (i) every value_allocated > 0; accumulate sum for step j
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'value_allocated')::numeric <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_VALUE_ALLOCATED',
                'error_message', 'value_allocated must be greater than zero.',
                'details',       json_build_object(
                    'offending_item_id', v_item->>'scrap_inventory_id',
                    'value',             v_item->>'value_allocated'
                )
            )::text;
        END IF;
        v_items_sum := v_items_sum + (v_item->>'value_allocated')::numeric(10,2);
    END LOOP;

    -- (j) sum(value_allocated) must equal p_header.total_value
    v_total_value := (p_header->>'total_value')::numeric(10,2);
    IF round(v_items_sum, 2) <> round(v_total_value, 2) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'TOTAL_VALUE_MISMATCH',
            'error_message', 'Sum of value_allocated does not match total_value.',
            'details',       json_build_object('expected', v_items_sum, 'received', v_total_value)
        )::text;
    END IF;

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_disposal header
    INSERT INTO public.scrap_disposal (
        disposal_date,
        buyer_name,
        buyer_contact,
        payment_mode,
        payment_reference,
        total_value,
        receipt_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'disposal_date')::date,
        p_header->>'buyer_name',
        p_header->>'buyer_contact',
        (p_header->>'payment_mode')::scrap_payment_mode,
        CASE WHEN v_payment_mode = 'cash' THEN NULL ELSE p_header->>'payment_reference' END,
        v_total_value,
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_disposal_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_disposal_items (
            disposal_id,
            scrap_inventory_id,
            value_allocated,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_disposal_id,
            si.id,
            (v_item->>'value_allocated')::numeric(10,2),
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_disposal_item_ids := v_disposal_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'sold',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',           true,
        'disposal_id',       v_disposal_id,
        'disposal_item_ids', v_disposal_item_ids
    );
END;
$$;


ALTER FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) OWNER TO postgres;

--
-- Name: record_scrap_writeoff(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_writeoff_id        uuid;
    v_item               jsonb;
    v_scrap_id           uuid;
    v_item_id            uuid;
    v_writeoff_item_ids  uuid[] := '{}';
    v_scrap_ids          uuid[];
    v_bad_items          jsonb := '[]'::jsonb;
    v_dup_check          uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap write-offs.',
            'details',       null
        )::text;
    END IF;

    -- (b) reason must be a valid enum value
    IF (p_header->>'reason') NOT IN (
        'lost', 'damaged_unsaleable', 'hazmat_disposal',
        'stocktake_adjustment', 'donated', 'other'
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_REASON',
            'error_message', 'Invalid write-off reason.',
            'details',       json_build_object('received', p_header->>'reason')
        )::text;
    END IF;

    -- (c) description must be non-empty
    IF trim(coalesce(p_header->>'description', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_DESCRIPTION',
            'error_message', 'Description is required.',
            'details',       null
        )::text;
    END IF;

    -- (d) evidence_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_EVIDENCE_PHOTO',
            'error_message', 'At least one evidence photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (e) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (f) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

    IF (
        SELECT count(*)
        FROM unnest(v_scrap_ids) AS rid
        WHERE NOT EXISTS (SELECT 1 FROM public.scrap_inventory WHERE id = rid)
    ) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap inventory IDs do not exist.',
            'details',       json_build_object('offending_items', coalesce(v_bad_items, '[]'::jsonb))
        )::text;
    END IF;

    SELECT jsonb_agg(json_build_object('id', si.id::text, 'status', si.status::text))
    INTO v_bad_items
    FROM public.scrap_inventory si
    WHERE si.id = ANY(v_scrap_ids)
      AND si.status <> 'in_storage';

    IF v_bad_items IS NOT NULL AND jsonb_array_length(v_bad_items) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap items are not in_storage status.',
            'details',       json_build_object('offending_items', v_bad_items)
        )::text;
    END IF;

    -- (g) no duplicate scrap_inventory_id in p_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;
        IF v_scrap_id = ANY(v_dup_check) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'DUPLICATE_SCRAP_ITEM',
                'error_message', 'The same scrap item appears more than once.',
                'details',       json_build_object('duplicate_id', v_scrap_id)
            )::text;
        END IF;
        v_dup_check := v_dup_check || v_scrap_id;
    END LOOP;

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_writeoff header
    INSERT INTO public.scrap_writeoff (
        writeoff_date,
        reason,
        description,
        evidence_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'writeoff_date')::date,
        (p_header->>'reason')::scrap_writeoff_reason,
        p_header->>'description',
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_writeoff_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_writeoff_items (
            writeoff_id,
            scrap_inventory_id,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_writeoff_id,
            si.id,
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_writeoff_item_ids := v_writeoff_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'written_off',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'writeoff_id',        v_writeoff_id,
        'writeoff_item_ids',  v_writeoff_item_ids
    );
END;
$$;


ALTER FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) OWNER TO postgres;

--
-- Name: restore_part_to_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_part_to_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card_type text;
    v_location_id   uuid;
BEGIN
    SELECT jc.type, jc.location_id INTO v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = OLD.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        RETURN OLD;
    END IF;

    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, OLD.quantity_used);
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.restore_part_to_inventory() OWNER TO postgres;

--
-- Name: reverse_part_inventory_on_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reverse_part_inventory_on_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = OLD.invoice_id;

    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, -OLD.quantity);
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.reverse_part_inventory_on_delete() OWNER TO postgres;

--
-- Name: seed_get_fk_deps(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seed_get_fk_deps() RETURNS TABLE(child_table text, parent_table text)
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT
    kcu.table_name::text  AS child_table,
    ccu.table_name::text  AS parent_table
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.constraint_schema = kcu.constraint_schema
  JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
   AND tc.constraint_schema = ccu.constraint_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.constraint_schema = 'public'
    AND kcu.table_name <> ccu.table_name;
$$;


ALTER FUNCTION public.seed_get_fk_deps() OWNER TO postgres;

--
-- Name: seed_get_table_columns(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seed_get_table_columns() RETURNS TABLE(table_name text, column_name text)
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT c.table_name::text, c.column_name::text
  FROM information_schema.columns c
  JOIN pg_tables t ON t.schemaname = 'public' AND t.tablename = c.table_name
  WHERE c.table_schema = 'public'
    AND c.is_generated = 'NEVER'
    AND NOT (c.is_identity = 'YES' AND c.identity_generation = 'ALWAYS')
  ORDER BY c.table_name, c.ordinal_position;
$$;


ALTER FUNCTION public.seed_get_table_columns() OWNER TO postgres;

--
-- Name: seed_truncate_public_tables(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seed_truncate_public_tables() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('TRUNCATE TABLE public.%I CASCADE', tbl);
  END LOOP;
END;
$$;


ALTER FUNCTION public.seed_truncate_public_tables() OWNER TO postgres;

--
-- Name: set_scrap_location_from_job_card(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_scrap_location_from_job_card() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    SELECT jc.location_id INTO NEW.location_id
    FROM   public.job_cards jc
    WHERE  jc.id = NEW.source_job_card_id;

    IF NEW.location_id IS NULL THEN
        NEW.location_id := 'a1e1d4c0-0000-4000-8000-000000000001';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_scrap_location_from_job_card() OWNER TO postgres;

--
-- Name: set_stock_audit_reasons(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role      text;
    v_status    text;
    r           RECORD;
    v_variance  numeric;
    v_part_name text;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can explain an audit mismatch.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Reasons can only be set while the audit is under review. This one is %.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid AS part_id,
               NULLIF(btrim(COALESCE(elem->>'reason', '')), '') AS reason,
               NULLIF(btrim(COALESCE(elem->>'notes',  '')), '') AS notes
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        SELECT variance, part_name_snapshot INTO v_variance, v_part_name
        FROM   public.stock_audit_items
        WHERE  audit_id = p_audit_id AND part_id = r.part_id;

        IF v_part_name IS NULL THEN
            RAISE EXCEPTION 'One of those parts is not part of this audit.';
        END IF;

        IF r.reason IS NOT NULL THEN
            IF r.reason NOT IN ('missing', 'stolen', 'damaged', 'found', 'other') THEN
                RAISE EXCEPTION 'Unknown reason "%".', r.reason;
            END IF;
            IF r.reason = 'other' AND r.notes IS NULL THEN
                RAISE EXCEPTION 'A note is required when the reason is Other (%).', v_part_name;
            END IF;
            IF r.reason = 'found' AND COALESCE(v_variance, 0) <= 0 THEN
                RAISE EXCEPTION 'Found / excess only applies where more was counted than expected (%).', v_part_name;
            END IF;
            IF r.reason IN ('missing', 'stolen', 'damaged') AND COALESCE(v_variance, 0) >= 0 THEN
                RAISE EXCEPTION 'Missing, Stolen and Damaged only apply to a shortfall (%).', v_part_name;
            END IF;
        END IF;

        UPDATE public.stock_audit_items
        SET reason = r.reason, reason_notes = r.notes
        WHERE audit_id = p_audit_id AND part_id = r.part_id;
    END LOOP;
END;
$$;


ALTER FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) OWNER TO postgres;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO postgres;

--
-- Name: stamp_rejected_at_and_evaluate_acceptance_sla(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_deadline    timestamptz;
  v_first_issue timestamptz;
BEGIN
  -- Only act when status transitions TO Rejected
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN

    NEW.rejected_at := NOW();

    -- Only evaluate if still Pending (not already resolved by the first-issue trigger)
    IF NEW.acceptance_sla_status = 'Pending' THEN

      v_deadline := COALESCE(
          NEW.acceptance_sla_end_date,
          acceptance_deadline(NEW.created_at AT TIME ZONE 'UTC')
      );

      SELECT MIN(created_at) AT TIME ZONE 'UTC'
        INTO v_first_issue
        FROM issues
       WHERE ticket_id = NEW.id;

      IF v_first_issue IS NOT NULL THEN
        -- First issue exists; evaluate against its creation time
        IF v_first_issue <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      ELSE
        -- No issues ever created; evaluate against rejection time
        IF NOW() <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() OWNER TO postgres;

--
-- Name: start_stock_audit(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_audit_id uuid;
    v_role     text;
    v_name     text;
    v_open_by  text;
    v_open_at  timestamp without time zone;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can run a stock audit.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.workshop_locations WHERE id = p_location_id AND is_active
    ) THEN
        RAISE EXCEPTION 'That workshop is not an active location.';
    END IF;

    SELECT started_by_name, started_at INTO v_open_by, v_open_at
    FROM   public.stock_audits
    WHERE  location_id = p_location_id
      AND  status IN ('counting', 'review');

    IF v_open_at IS NOT NULL THEN
        RAISE EXCEPTION 'An audit is already open at this workshop, started by % on %. Complete or cancel it before starting another.',
            COALESCE(NULLIF(v_open_by, ''), 'someone'),
            to_char(v_open_at, 'DD Mon YYYY');
    END IF;

    INSERT INTO public.stock_audits (location_id, started_by, started_by_name, notes)
    VALUES (p_location_id, auth.uid(), COALESCE(v_name, ''),
            NULLIF(btrim(COALESCE(p_notes, '')), ''))
    RETURNING id INTO v_audit_id;

    -- Only what is actually stocked here. Printing the whole catalogue would mean 300+
    -- rows of zeroes to write out by hand at a workshop that stocks seven parts, and a
    -- blank row blocks the upload. Anything physically present but unlisted comes back
    -- on one of the sheet's blank "found" rows instead.
    --
    -- A workshop with no stock at all yields an empty sheet on purpose: that is how a new
    -- workshop's opening stock gets entered, entirely through found rows.
    INSERT INTO public.stock_audit_items (
        audit_id, part_id, part_name_snapshot, part_number_snapshot, unit_snapshot, system_qty
    )
    SELECT v_audit_id, p.id, p.name, p.part_number, COALESCE(p.unit, 'pcs'), ps.quantity
    FROM   public.part_stock ps
    JOIN   public.parts p ON p.id = ps.part_id
    WHERE  ps.location_id = p_location_id
      AND  ps.quantity > 0;

    RETURN v_audit_id;
END;
$$;


ALTER FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text) OWNER TO postgres;

--
-- Name: stock_audit_movements(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.stock_audit_movements(p_audit_id uuid) RETURNS TABLE(part_id uuid, source text, quantity numeric, reference text, vehicle_number text, occurred_at timestamp without time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    WITH a AS (
        SELECT sa.id, sa.location_id, sa.started_at
        FROM   public.stock_audits sa
        WHERE  sa.id = p_audit_id
          -- Mirrors the SELECT policy on stock_audits.
          AND  EXISTS (
                   SELECT 1 FROM public.users u
                   WHERE u.id = auth.uid()
                     AND u.role IN ('finance', 'super_admin', 'maintenance_exec')
               )
    )
    -- Consumed on a job card. Outsource job cards never touch stock, so they are excluded
    -- here exactly as deduct_part_from_inventory() excludes them.
    SELECT ip.part_id,
           'consumption'::text,
           -ip.quantity_used,
           'JC-' || jc.job_card_number::text,
           jc.vehicle_number,
           ip.added_at
    FROM   a
    JOIN   public.job_cards   jc ON jc.location_id = a.location_id AND jc.type <> 'Outsource'
    JOIN   public.issues      i  ON i.job_card_id = jc.id
    JOIN   public.issue_parts ip ON ip.issue_id = i.id
    WHERE  ip.added_at > a.started_at

    UNION ALL

    -- Inwarded on a purchase invoice.
    SELECT pii.part_id,
           'purchase'::text,
           pii.quantity,
           pi.invoice_number,
           NULL::text,
           pi.created_at
    FROM   a
    JOIN   public.purchase_invoices      pi  ON pi.location_id = a.location_id
    JOIN   public.purchase_invoice_items pii ON pii.invoice_id = pi.id
    WHERE  pi.created_at > a.started_at

    UNION ALL

    -- Moved to or from another workshop.
    SELECT sti.part_id,
           CASE WHEN st.to_location_id = a.location_id
                THEN 'transfer_in' ELSE 'transfer_out' END,
           CASE WHEN st.to_location_id = a.location_id
                THEN sti.quantity ELSE -sti.quantity END,
           wl.name,
           NULL::text,
           st.transferred_at
    FROM   a
    JOIN   public.stock_transfers st
           ON (st.from_location_id = a.location_id OR st.to_location_id = a.location_id)
    JOIN   public.stock_transfer_items sti ON sti.transfer_id = st.id
    JOIN   public.workshop_locations wl
           ON wl.id = CASE WHEN st.to_location_id = a.location_id
                           THEN st.from_location_id ELSE st.to_location_id END
    WHERE  st.transferred_at > a.started_at

    ORDER BY 6 DESC;
$$;


ALTER FUNCTION public.stock_audit_movements(p_audit_id uuid) OWNER TO postgres;

--
-- Name: FUNCTION stock_audit_movements(p_audit_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.stock_audit_movements(p_audit_id uuid) IS 'Stock that legitimately moved at a workshop while an audit was open. SECURITY DEFINER, so it carries its own role check: returns nothing unless the caller is finance, super_admin or maintenance_exec.';


--
-- Name: submit_stock_audit_counts(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role     text;
    v_name     text;
    v_status   text;
    v_location uuid;
    r          RECORD;
    v_blank    integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can upload a count sheet.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status NOT IN ('counting', 'review') THEN
        RAISE EXCEPTION 'This audit is already % and cannot take new counts.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid        AS part_id,
               (elem->>'counted_qty')::numeric AS counted_qty
        FROM   jsonb_array_elements(p_counts) AS elem
    LOOP
        IF r.part_id IS NULL OR r.counted_qty IS NULL THEN
            RAISE EXCEPTION 'Every row on the sheet needs a part and a counted quantity.';
        END IF;
        IF r.counted_qty < 0 THEN
            RAISE EXCEPTION 'A counted quantity cannot be negative.';
        END IF;

        UPDATE public.stock_audit_items
        SET counted_qty  = r.counted_qty,
            reason       = CASE WHEN counted_qty IS DISTINCT FROM r.counted_qty
                                THEN NULL ELSE reason END,
            reason_notes = CASE WHEN counted_qty IS DISTINCT FROM r.counted_qty
                                THEN NULL ELSE reason_notes END
        WHERE audit_id = p_audit_id AND part_id = r.part_id;

        IF NOT FOUND THEN
            -- Written onto a blank row: stock the app did not know was here.
            INSERT INTO public.stock_audit_items (
                audit_id, part_id, part_name_snapshot, part_number_snapshot,
                unit_snapshot, system_qty, counted_qty, was_found_row
            )
            SELECT p_audit_id, p.id, p.name, p.part_number, COALESCE(p.unit, 'pcs'),
                   COALESCE(ps.quantity, 0), r.counted_qty, true
            FROM   public.parts p
            LEFT   JOIN public.part_stock ps
                   ON ps.part_id = p.id AND ps.location_id = v_location
            WHERE  p.id = r.part_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'A part written onto the sheet is not in the catalogue. Add it under Parts Catalog first, then upload again.';
            END IF;
        END IF;
    END LOOP;

    -- Nothing printed on the sheet may come back blank.
    SELECT count(*) INTO v_blank
    FROM   public.stock_audit_items
    WHERE  audit_id = p_audit_id AND counted_qty IS NULL;

    IF v_blank > 0 THEN
        RAISE EXCEPTION '% part(s) on the sheet have no counted quantity. Every row must be filled in before the sheet can be uploaded.', v_blank;
    END IF;

    UPDATE public.stock_audits
    SET status                  = 'review',
        counts_uploaded_by      = auth.uid(),
        counts_uploaded_by_name = COALESCE(v_name, ''),
        counts_uploaded_at      = now()
    WHERE id = p_audit_id;
END;
$$;


ALTER FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) OWNER TO postgres;

--
-- Name: sync_part_total_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_part_total_stock() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_part_id uuid := COALESCE(NEW.part_id, OLD.part_id);
BEGIN
    UPDATE public.parts p
    SET    quantity_in_stock = COALESCE(
               (SELECT SUM(ps.quantity) FROM public.part_stock ps WHERE ps.part_id = v_part_id),
               0)
    WHERE  p.id = v_part_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.sync_part_total_stock() OWNER TO postgres;

--
-- Name: transfer_stock(uuid, uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_transfer_id uuid;
    v_role        text;
    r             RECORD;
    v_count       integer := 0;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('maintenance_exec', 'super_admin') THEN
        RAISE EXCEPTION 'Only a maintenance executive or super admin can move stock between workshops.';
    END IF;

    IF p_from = p_to THEN
        RAISE EXCEPTION 'Source and destination workshop must be different.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_from AND is_active) THEN
        RAISE EXCEPTION 'The source workshop is not an active location.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_to AND is_active) THEN
        RAISE EXCEPTION 'The destination workshop is not an active location.';
    END IF;

    INSERT INTO public.stock_transfers (from_location_id, to_location_id, notes, transferred_by)
    VALUES (p_from, p_to, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid())
    RETURNING id INTO v_transfer_id;

    FOR r IN
        SELECT (elem->>'part_id')::uuid  AS part_id,
               (elem->>'quantity')::numeric AS quantity
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        IF r.part_id IS NULL OR r.quantity IS NULL OR r.quantity <= 0 THEN
            RAISE EXCEPTION 'Every line needs a part and a quantity greater than zero.';
        END IF;

        PERFORM public.apply_part_stock_delta(r.part_id, p_from, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, p_to,    r.quantity);

        INSERT INTO public.stock_transfer_items (transfer_id, part_id, quantity)
        VALUES (v_transfer_id, r.part_id, r.quantity);

        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one part to move.';
    END IF;

    RETURN v_transfer_id;
END;
$$;


ALTER FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text) OWNER TO postgres;

--
-- Name: trg_recalculate_open_slas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_recalculate_open_slas() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    PERFORM recalculate_open_slas();
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.trg_recalculate_open_slas() OWNER TO postgres;

--
-- Name: trg_set_acceptance_sla_on_first_issue(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_set_acceptance_sla_on_first_issue() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_prior_count INT;
BEGIN
    SELECT COUNT(*) INTO v_prior_count
    FROM issues WHERE ticket_id = NEW.ticket_id AND id != NEW.id;

    IF v_prior_count = 0 THEN
        UPDATE tickets
        SET acceptance_sla_status =
            evaluate_acceptance_sla(NEW.ticket_id, NEW.created_at AT TIME ZONE 'UTC')
        WHERE id = NEW.ticket_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_set_acceptance_sla_on_first_issue() OWNER TO postgres;

--
-- Name: trg_stamp_acceptance_deadline(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_stamp_acceptance_deadline() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    NEW.acceptance_sla_end_date := acceptance_deadline(NEW.created_at AT TIME ZONE 'UTC');
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_stamp_acceptance_deadline() OWNER TO postgres;

--
-- Name: update_ticket_status_on_issue_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_ticket_status_on_issue_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  ticket_status TEXT;
  total_issues INTEGER;
  done_issues INTEGER;
  rated_issues INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE rating IS NOT NULL)
  INTO total_issues, done_issues, rated_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT EXISTS(
    SELECT 1 FROM issues i 
    WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id) 
    AND i.job_card_id IS NOT NULL
  ) INTO has_job_cards;
  
  -- New → Accepted (on issue creation)
  IF ticket_status = 'New' AND total_issues > 0 AND TG_OP = 'INSERT' THEN
    UPDATE tickets SET status = 'Accepted' WHERE id = NEW.ticket_id;
  END IF;
  
  -- Accepted → Work In Progress (on job card assignment)
  IF ticket_status = 'Accepted' AND has_job_cards THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Work In Progress → Resolved (all issues done)
  IF ticket_status = 'Work In Progress' AND total_issues > 0 AND done_issues = total_issues THEN
    UPDATE tickets SET status = 'Resolved' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Resolved → Closed (all issues have rating/feedback)
  IF ticket_status = 'Resolved' AND total_issues > 0 AND rated_issues = total_issues THEN
    UPDATE tickets SET status = 'Closed' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.update_ticket_status_on_issue_change() OWNER TO postgres;

--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
    -- Regclass of the table e.g. public.notes
    entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

    -- I, U, D, T: insert, update ...
    action realtime.action = (
        case wal ->> 'action'
            when 'I' then 'INSERT'
            when 'U' then 'UPDATE'
            when 'D' then 'DELETE'
            else 'ERROR'
        end
    );

    -- Is row level security enabled for the table
    is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

    subscriptions realtime.subscription[] = array_agg(subs)
        from
            realtime.subscription subs
        where
            subs.entity = entity_
            -- Filter by action early - only get subscriptions interested in this action
            -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
            and (subs.action_filter = '*' or subs.action_filter = action::text);

    -- Subscription vars
    working_role regrole;
    working_selected_columns text[];
    claimed_role regrole;
    claims jsonb;

    subscription_id uuid;
    subscription_has_access bool;
    visible_to_subscription_ids uuid[] = '{}';

    -- structured info for wal's columns
    columns realtime.wal_column[];
    -- previous identity values for update/delete
    old_columns realtime.wal_column[];

    error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

    -- Primary jsonb output for record
    output jsonb;

    -- Loop record for iterating unique roles (outer loop)
    role_record record;
    -- Loop record for iterating unique selected_columns within a role (inner loop)
    cols_record record;
    -- Subscription ids visible at the role level (before fanning out by selected_columns)
    visible_role_sub_ids uuid[] = '{}';

begin
    perform set_config('role', null, true);

    columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'columns') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    old_columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'identity') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    for role_record in
        select claims_role
        from (select distinct claims_role from unnest(subscriptions)) t
        order by claims_role::text
    loop
        working_role := role_record.claims_role;

        -- Update `is_selectable` for columns and old_columns (once per role)
        columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(columns) c;

        old_columns =
                array_agg(
                    (
                        c.name,
                        c.type_name,
                        c.type_oid,
                        c.value,
                        c.is_pkey,
                        pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                    )::realtime.wal_column
                )
                from
                    unnest(old_columns) c;

        if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
            -- Fan out 400 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 400: Bad Request, no primary key']
                )::realtime.wal_rls;
            end loop;

        -- The claims role does not have SELECT permission to the primary key of entity
        elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
            -- Fan out 401 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 401: Unauthorized']
                )::realtime.wal_rls;
            end loop;

        else
            -- Create the prepared statement (once per role)
            if is_rls_enabled and action <> 'DELETE' then
                if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                    deallocate walrus_rls_stmt;
                end if;
                execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
            end if;

            -- Collect all visible subscription IDs for this role (filter check + RLS check)
            visible_role_sub_ids = '{}';

            for subscription_id, claims in (
                    select
                        subs.subscription_id,
                        subs.claims
                    from
                        unnest(subscriptions) subs
                    where
                        subs.entity = entity_
                        and subs.claims_role = working_role
                        and (
                            realtime.is_visible_through_filters(columns, subs.filters)
                            or (
                              action = 'DELETE'
                              and realtime.is_visible_through_filters(old_columns, subs.filters)
                            )
                        )
            ) loop

                if not is_rls_enabled or action = 'DELETE' then
                    visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                else
                    -- Check if RLS allows the role to see the record
                    perform
                        -- Trim leading and trailing quotes from working_role because set_config
                        -- doesn't recognize the role as valid if they are included
                        set_config('role', trim(both '"' from working_role::text), true),
                        set_config('request.jwt.claims', claims::text, true);

                    execute 'execute walrus_rls_stmt' into subscription_has_access;

                    -- Reset the role on every FOR..LOOP batch execution.
                    -- The first batch of 10 rows is pre-fetched using the current connection role (PG internal behaviour)
                    -- then we have to reset it again otherwise it would use the role defined in the `set_config` above
                    -- to fetch the remaining rows when rows>10, which could be a user-defined role that lacks execution grants.
                    -- The flow is:
                    --   1. run batch with conn role
                    --   2. set_config working_role
                    --   3. execute walrus
                    --   4. reset role (revert)
                    --   5. repeat
                    perform set_config('role', null, true);

                    if subscription_has_access then
                        visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                    end if;
                end if;
            end loop;

            perform set_config('role', null, true);

            -- Inner loop: per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;

                output = jsonb_build_object(
                    'schema', wal ->> 'schema',
                    'table', wal ->> 'table',
                    'type', action,
                    'commit_timestamp', to_char(
                        ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                    ),
                    'columns', (
                        select
                            jsonb_agg(
                                jsonb_build_object(
                                    'name', pa.attname,
                                    'type', pt.typname
                                )
                                order by pa.attnum asc
                            )
                        from
                            pg_attribute pa
                            join pg_type pt
                                on pa.atttypid = pt.oid
                            left join (
                                select unnest(conkey) as pkey_attnum
                                from pg_constraint
                                where conrelid = entity_ and contype = 'p'
                            ) pk on pk.pkey_attnum = pa.attnum
                        where
                            attrelid = entity_
                            and attnum > 0
                            and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
                            and (working_selected_columns is null or pa.attname = any(working_selected_columns) or pk.pkey_attnum is not null)
                    )
                )
                -- Add "record" key for insert and update
                || case
                    when action in ('INSERT', 'UPDATE') then
                        jsonb_build_object(
                            'record',
                            (
                                select
                                    jsonb_object_agg(
                                        -- if unchanged toast, get column name and value from old record
                                        coalesce((c).name, (oc).name),
                                        case
                                            when (c).name is null then (oc).value
                                            else (c).value
                                        end
                                    )
                                from
                                    unnest(columns) c
                                    full outer join unnest(old_columns) oc
                                        on (c).name = (oc).name
                                where
                                    coalesce((c).is_selectable, (oc).is_selectable)
                                    and (working_selected_columns is null or coalesce((c).name, (oc).name) = any(working_selected_columns) or coalesce((c).is_pkey, (oc).is_pkey))
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            )
                        )
                    else '{}'::jsonb
                end
                -- Add "old_record" key for update and delete
                || case
                    when action = 'UPDATE' then
                        jsonb_build_object(
                                'old_record',
                                (
                                    select jsonb_object_agg((c).name, (c).value)
                                    from unnest(old_columns) c
                                    where
                                        (c).is_selectable
                                        and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                        and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                )
                            )
                    when action = 'DELETE' then
                        jsonb_build_object(
                            'old_record',
                            (
                                select jsonb_object_agg((c).name, (c).value)
                                from unnest(old_columns) c
                                where
                                    (c).is_selectable
                                    and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                    and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                            )
                        )
                    else '{}'::jsonb
                end;

                -- Filter visible_role_sub_ids to those matching the current selected_columns group
                visible_to_subscription_ids = coalesce(
                    (
                        select array_agg(s.subscription_id)
                        from unnest(subscriptions) s
                        where s.claims_role = working_role
                          and (s.selected_columns is not distinct from working_selected_columns)
                          and s.subscription_id = any(visible_role_sub_ids)
                    ),
                    '{}'::uuid[]
                );

                return next (
                    output,
                    is_rls_enabled,
                    visible_to_subscription_ids,
                    case
                        when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                        else '{}'
                    end
                )::realtime.wal_rls;
            end loop;

        end if;
    end loop;

    perform set_config('role', null, true);
end;
$$;


ALTER FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) OWNER TO supabase_realtime_admin;

--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


ALTER FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) OWNER TO supabase_realtime_admin;

--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


ALTER FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) OWNER TO supabase_realtime_admin;

--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  res jsonb;
begin
  if type_::text = 'bytea' then
    return to_jsonb(val);
  end if;
  execute format('select to_jsonb(%L::'|| type_::text || ')', val) into res;
  return res;
end
$$;


ALTER FUNCTION realtime."cast"(val text, type_ regtype) OWNER TO supabase_realtime_admin;

--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
/*
Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
*/
declare
    op_symbol text = (
        case
            when op = 'eq' then '='
            when op = 'neq' then '!='
            when op = 'lt' then '<'
            when op = 'lte' then '<='
            when op = 'gt' then '>'
            when op = 'gte' then '>='
            when op = 'in' then '= any'
            else 'UNKNOWN OP'
        end
    );
    res boolean;
begin
    execute format(
        'select %L::'|| type_::text || ' ' || op_symbol
        || ' ( %L::'
        || (
            case
                when op = 'in' then type_::text || '[]'
                else type_::text end
        )
        || ')', val_1, val_2) into res;
    return res;
end;
$$;


ALTER FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) OWNER TO supabase_realtime_admin;

--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
    op_symbol text;
    res boolean;
begin
    -- IS DISTINCT FROM / IS NOT DISTINCT FROM: infix, both sides typed literals
    if op = 'isdistinct' then
        execute format(
            'select %L::%s %s %L::%s',
            val_1,
            type_::text,
            case when negate then 'IS NOT DISTINCT FROM' else 'IS DISTINCT FROM' end,
            val_2,
            type_::text
        ) into res;
        return res;
    end if;

    -- IS requires a keyword RHS (NULL, TRUE, FALSE, UNKNOWN), not a typed literal
    if op = 'is' then
        if val_2 not in ('null', 'true', 'false', 'unknown') then
            raise exception 'invalid value for is filter: must be null, true, false, or unknown';
        end if;
        execute format(
            'select %L::%s %s %s',
            val_1,
            type_::text,
            case when negate then 'IS NOT' else 'IS' end,
            upper(val_2)
        ) into res;
        return res;
    end if;

    op_symbol = case
        when op = 'eq'    then '='
        when op = 'neq'   then '!='
        when op = 'lt'    then '<'
        when op = 'lte'   then '<='
        when op = 'gt'    then '>'
        when op = 'gte'   then '>='
        when op = 'in'    then '= any'
        when op = 'like'   then 'LIKE'
        when op = 'ilike'  then 'ILIKE'
        when op = 'match'  then '~'
        when op = 'imatch' then '~*'
        else null
    end;

    if op_symbol is null then
        raise exception 'unsupported equality operator: %', op::text;
    end if;

    execute format(
        'select %L::%s %s (%L::%s)',
        val_1,
        type_::text,
        op_symbol,
        val_2,
        case when op = 'in' then type_::text || '[]' else type_::text end
    ) into res;

    return case when negate then not res else res end;
end;
$$;


ALTER FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) OWNER TO supabase_realtime_admin;

--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    select
        filters is null
        or array_length(filters, 1) is null
        or coalesce(
            count(col.name) = count(1)
            and sum(
                realtime.check_equality_op(
                    op:=f.op,
                    type_:=coalesce(col.type_oid::regtype, col.type_name::regtype),
                    val_1:=col.value #>> '{}',
                    val_2:=f.value,
                    negate:=coalesce(f.negate, false)
                )::int
            ) filter (where col.name is not null) = count(col.name),
            false
        )
    from
        unnest(filters) f
        left join unnest(columns) col
            on f.column_name = col.name;
$$;


ALTER FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) OWNER TO supabase_realtime_admin;

--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS TABLE(wal jsonb, is_rls_enabled boolean, subscription_ids uuid[], errors text[], slot_changes_count bigint)
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
  WITH pub AS (
    SELECT
      concat_ws(
        ',',
        CASE WHEN bool_or(pubinsert) THEN 'insert' ELSE NULL END,
        CASE WHEN bool_or(pubupdate) THEN 'update' ELSE NULL END,
        CASE WHEN bool_or(pubdelete) THEN 'delete' ELSE NULL END
      ) AS w2j_actions,
      coalesce(
        string_agg(
          realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
          ','
        ) filter (WHERE ppt.tablename IS NOT NULL),
        ''
      ) AS w2j_add_tables
    FROM pg_publication pp
    LEFT JOIN pg_publication_tables ppt ON pp.pubname = ppt.pubname
    WHERE pp.pubname = publication
    GROUP BY pp.pubname
    LIMIT 1
  ),
  -- MATERIALIZED ensures pg_logical_slot_get_changes is called exactly once
  w2j AS MATERIALIZED (
    SELECT x.*, pub.w2j_add_tables
    FROM pub,
         pg_logical_slot_get_changes(
           slot_name, null, max_changes,
           'include-pk', 'true',
           'include-transaction', 'false',
           'include-timestamp', 'true',
           'include-type-oids', 'true',
           'format-version', '2',
           'actions', pub.w2j_actions,
           'add-tables', pub.w2j_add_tables
         ) x
  ),
  slot_count AS (
    SELECT count(*)::bigint AS cnt
    FROM w2j
    WHERE w2j.w2j_add_tables <> ''
  ),
  rls_filtered AS (
    SELECT xyz.wal, xyz.is_rls_enabled, xyz.subscription_ids, xyz.errors
    FROM w2j,
         realtime.apply_rls(
           wal := w2j.data::jsonb,
           max_record_bytes := max_record_bytes
         ) xyz(wal, is_rls_enabled, subscription_ids, errors)
    WHERE w2j.w2j_add_tables <> ''
      AND xyz.subscription_ids[1] IS NOT NULL
  )
  SELECT rf.wal, rf.is_rls_enabled, rf.subscription_ids, rf.errors, sc.cnt
  FROM rls_filtered rf, slot_count sc

  UNION ALL

  SELECT null, null, null, null, sc.cnt
  FROM slot_count sc
  WHERE NOT EXISTS (SELECT 1 FROM rls_filtered)
$$;


ALTER FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) OWNER TO supabase_realtime_admin;

--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  SELECT
    realtime.wal2json_escape_identifier(nsp.nspname::text)
    || '.'
    || realtime.wal2json_escape_identifier(pc.relname::text)
  FROM pg_class pc
  JOIN pg_namespace nsp ON pc.relnamespace = nsp.oid
  WHERE pc.oid = entity
$$;


ALTER FUNCTION realtime.quote_wal2json(entity regclass) OWNER TO supabase_realtime_admin;

--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) OWNER TO supabase_realtime_admin;

--
-- Name: send_binary(bytea, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, binary_payload, event, topic, private, extension)
    VALUES (generated_id, payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean) OWNER TO supabase_realtime_admin;

--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    col_names text[] = coalesce(
            array_agg(a.attname order by a.attnum),
            '{}'::text[]
        )
        from
            pg_catalog.pg_attribute a
        where
            a.attrelid = new.entity
            and a.attnum > 0
            and not a.attisdropped
            and pg_catalog.has_column_privilege(
                (new.claims ->> 'role'),
                a.attrelid,
                a.attnum,
                'SELECT'
            );
    filter realtime.user_defined_filter;
    col_type regtype;
    in_val jsonb;
    selected_col text;
begin
    for filter in select * from unnest(new.filters) loop
        if not filter.column_name = any(col_names) then
            raise exception 'invalid column for filter %', filter.column_name;
        end if;

        col_type = (
            select atttypid::regtype
            from pg_catalog.pg_attribute
            where attrelid = new.entity
                  and attname = filter.column_name
        );
        if col_type is null then
            raise exception 'failed to lookup type for column %', filter.column_name;
        end if;

        if filter.op = 'in'::realtime.equality_op then
            in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
            if coalesce(jsonb_array_length(in_val), 0) > 100 then
                raise exception 'too many values for `in` filter. Maximum 100';
            end if;
        elsif filter.op = 'is'::realtime.equality_op then
            -- `is` requires a keyword RHS rather than a typed literal
            if filter.value not in ('null', 'true', 'false', 'unknown') then
                raise exception 'invalid value for is filter: must be null, true, false, or unknown';
            end if;
            -- IS NULL works for any type, but IS TRUE/FALSE/UNKNOWN require a boolean
            -- operand. Reject the non-null keywords on non-boolean columns here so they
            -- don't abort apply_rls at WAL time.
            if filter.value <> 'null' and col_type <> 'boolean'::regtype then
                raise exception 'is % filter requires a boolean column, got %', filter.value, col_type::text;
            end if;
        elsif filter.op in ('like'::realtime.equality_op, 'ilike'::realtime.equality_op) then
            -- like/ilike apply the text pattern operator (~~); reject column types that
            -- have no such operator instead of failing at WAL time
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = '~~' and oprleft = col_type
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
        elsif filter.op in ('match'::realtime.equality_op, 'imatch'::realtime.equality_op) then
            -- match/imatch apply the regex operators ~ / ~*; reject column types that have
            -- no such operator (e.g. integer) instead of failing at WAL time, mirroring the
            -- like/ilike guard above.
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = case when filter.op = 'imatch'::realtime.equality_op then '~*' else '~' end
                  and oprleft = col_type
                  and oprright = col_type
                  and oprresult = 'boolean'::regtype
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
            -- validate the regex eagerly so a bad pattern is rejected here, not inside
            -- apply_rls where it would abort the WAL stream for the entity
            begin
                perform '' ~ filter.value;
            exception when others then
                raise exception 'invalid regular expression for % filter: %', filter.op::text, sqlerrm;
            end;
        else
            -- eq/neq/lt/lte/gt/gte: value must be coercable to the type
            perform realtime.cast(filter.value, col_type);
        end if;
    end loop;

    if new.selected_columns is not null then
        for selected_col in select * from unnest(new.selected_columns) loop
            if not selected_col = any(col_names) then
                raise exception 'invalid column for select %', selected_col;
            end if;
        end loop;
    end if;

    -- Apply consistent order to filters so the unique constraint can't be tricked by a
    -- different filter order. negate is part of the sort key.
    new.filters = coalesce(
        array_agg(f order by f.column_name, f.op, f.value, f.negate),
        '{}'
    ) from unnest(new.filters) f;

    new.selected_columns = (
        select array_agg(c order by c)
        from unnest(new.selected_columns) c
    );

    return new;
end;
$$;


ALTER FUNCTION realtime.subscription_check_filters() OWNER TO supabase_realtime_admin;

--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


ALTER FUNCTION realtime.to_regrole(role_name text) OWNER TO supabase_realtime_admin;

--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


ALTER FUNCTION realtime.topic() OWNER TO supabase_realtime_admin;

--
-- Name: wal2json_escape_identifier(text); Type: FUNCTION; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE FUNCTION realtime.wal2json_escape_identifier(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  -- Prefix `\`, `,`, `.`, and any whitespace with `\`
  SELECT regexp_replace(name, '([\\,.[:space:]])', '\\\1', 'g')
$$;


ALTER FUNCTION realtime.wal2json_escape_identifier(name text) OWNER TO supabase_realtime_admin;

--
-- Name: allow_any_operation(text[]); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.allow_any_operation(expected_operations text[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION storage.allow_any_operation(expected_operations text[]) OWNER TO supabase_storage_admin;

--
-- Name: allow_only_operation(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.allow_only_operation(expected_operation text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION storage.allow_only_operation(expected_operation text) OWNER TO supabase_storage_admin;

--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) OWNER TO supabase_storage_admin;

--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION storage.enforce_bucket_name_length() OWNER TO supabase_storage_admin;

--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION storage.extension(name text) OWNER TO supabase_storage_admin;

--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION storage.filename(name text) OWNER TO supabase_storage_admin;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION storage.foldername(name text) OWNER TO supabase_storage_admin;

--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) OWNER TO supabase_storage_admin;

--
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION storage.get_size_by_bucket() OWNER TO supabase_storage_admin;

--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) OWNER TO supabase_storage_admin;

--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text, sort_order text) OWNER TO supabase_storage_admin;

--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION storage.operation() OWNER TO supabase_storage_admin;

--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION storage.protect_delete() OWNER TO supabase_storage_admin;

--
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) OWNER TO supabase_storage_admin;

--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) OWNER TO supabase_storage_admin;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: supabase_storage_admin
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION storage.update_updated_at_column() OWNER TO supabase_storage_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE auth.audit_log_entries OWNER TO supabase_auth_admin;

--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: custom_oauth_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.custom_oauth_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_type text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    acceptable_client_ids text[] DEFAULT '{}'::text[] NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL,
    pkce_enabled boolean DEFAULT true NOT NULL,
    attribute_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorization_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    email_optional boolean DEFAULT false NOT NULL,
    issuer text,
    discovery_url text,
    skip_nonce_check boolean DEFAULT false NOT NULL,
    cached_discovery jsonb,
    discovery_cached_at timestamp with time zone,
    authorization_url text,
    token_url text,
    userinfo_url text,
    jwks_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    custom_claims_allowlist text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT custom_oauth_providers_authorization_url_https CHECK (((authorization_url IS NULL) OR (authorization_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_authorization_url_length CHECK (((authorization_url IS NULL) OR (char_length(authorization_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_client_id_length CHECK (((char_length(client_id) >= 1) AND (char_length(client_id) <= 512))),
    CONSTRAINT custom_oauth_providers_discovery_url_length CHECK (((discovery_url IS NULL) OR (char_length(discovery_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_identifier_format CHECK ((identifier ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::text)),
    CONSTRAINT custom_oauth_providers_issuer_length CHECK (((issuer IS NULL) OR ((char_length(issuer) >= 1) AND (char_length(issuer) <= 2048)))),
    CONSTRAINT custom_oauth_providers_jwks_uri_https CHECK (((jwks_uri IS NULL) OR (jwks_uri ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_jwks_uri_length CHECK (((jwks_uri IS NULL) OR (char_length(jwks_uri) <= 2048))),
    CONSTRAINT custom_oauth_providers_name_length CHECK (((char_length(name) >= 1) AND (char_length(name) <= 100))),
    CONSTRAINT custom_oauth_providers_oauth2_requires_endpoints CHECK (((provider_type <> 'oauth2'::text) OR ((authorization_url IS NOT NULL) AND (token_url IS NOT NULL) AND (userinfo_url IS NOT NULL)))),
    CONSTRAINT custom_oauth_providers_oidc_discovery_url_https CHECK (((provider_type <> 'oidc'::text) OR (discovery_url IS NULL) OR (discovery_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_issuer_https CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NULL) OR (issuer ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_requires_issuer CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NOT NULL))),
    CONSTRAINT custom_oauth_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['oauth2'::text, 'oidc'::text]))),
    CONSTRAINT custom_oauth_providers_token_url_https CHECK (((token_url IS NULL) OR (token_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_token_url_length CHECK (((token_url IS NULL) OR (char_length(token_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_userinfo_url_https CHECK (((userinfo_url IS NULL) OR (userinfo_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_userinfo_url_length CHECK (((userinfo_url IS NULL) OR (char_length(userinfo_url) <= 2048)))
);


ALTER TABLE auth.custom_oauth_providers OWNER TO supabase_auth_admin;

--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


ALTER TABLE auth.flow_state OWNER TO supabase_auth_admin;

--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


ALTER TABLE auth.identities OWNER TO supabase_auth_admin;

--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE auth.instances OWNER TO supabase_auth_admin;

--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


ALTER TABLE auth.mfa_amr_claims OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


ALTER TABLE auth.mfa_challenges OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


ALTER TABLE auth.mfa_factors OWNER TO supabase_auth_admin;

--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


ALTER TABLE auth.oauth_authorizations OWNER TO supabase_auth_admin;

--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


ALTER TABLE auth.oauth_client_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


ALTER TABLE auth.oauth_clients OWNER TO supabase_auth_admin;

--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


ALTER TABLE auth.oauth_consents OWNER TO supabase_auth_admin;

--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


ALTER TABLE auth.one_time_tokens OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


ALTER TABLE auth.refresh_tokens OWNER TO supabase_auth_admin;

--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: supabase_auth_admin
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE auth.refresh_tokens_id_seq OWNER TO supabase_auth_admin;

--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: supabase_auth_admin
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


ALTER TABLE auth.saml_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


ALTER TABLE auth.saml_relay_states OWNER TO supabase_auth_admin;

--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE auth.schema_migrations OWNER TO supabase_auth_admin;

--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


ALTER TABLE auth.sessions OWNER TO supabase_auth_admin;

--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


ALTER TABLE auth.sso_domains OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


ALTER TABLE auth.sso_providers OWNER TO supabase_auth_admin;

--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


ALTER TABLE auth.users OWNER TO supabase_auth_admin;

--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: webauthn_challenges; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.webauthn_challenges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    challenge_type text NOT NULL,
    session_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT webauthn_challenges_challenge_type_check CHECK ((challenge_type = ANY (ARRAY['signup'::text, 'registration'::text, 'authentication'::text])))
);


ALTER TABLE auth.webauthn_challenges OWNER TO supabase_auth_admin;

--
-- Name: webauthn_credentials; Type: TABLE; Schema: auth; Owner: supabase_auth_admin
--

CREATE TABLE auth.webauthn_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    credential_id bytea NOT NULL,
    public_key bytea NOT NULL,
    attestation_type text DEFAULT ''::text NOT NULL,
    aaguid uuid,
    sign_count bigint DEFAULT 0 NOT NULL,
    transports jsonb DEFAULT '[]'::jsonb NOT NULL,
    backup_eligible boolean DEFAULT false NOT NULL,
    backed_up boolean DEFAULT false NOT NULL,
    friendly_name text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


ALTER TABLE auth.webauthn_credentials OWNER TO supabase_auth_admin;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    table_name text NOT NULL,
    record_id uuid NOT NULL,
    action text NOT NULL,
    old_data jsonb,
    new_data jsonb,
    changed_fields text[],
    performed_by uuid,
    performed_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_logs_action_check CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: finance_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.finance_entries (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    work_type text NOT NULL,
    activity_date date NOT NULL,
    vehicle_number text,
    job_sheet_id text,
    ticket_id uuid,
    site text,
    vendor_name text,
    vendor_contact text,
    work_description text NOT NULL,
    approved_amount numeric,
    invoice_number text,
    km_reading integer,
    work_inspected_by text,
    payable_amount numeric,
    advance_amount numeric,
    invoice_value numeric,
    paid_amount numeric,
    payment_date date,
    payment_status text DEFAULT 'Pending'::text,
    transaction_details text,
    payment_via text,
    bill_attachment text,
    approval_screenshot text,
    job_card_upload text,
    created_by_user_id uuid NOT NULL,
    accounting_status text DEFAULT 'Pending'::text,
    CONSTRAINT finance_entries_accounting_status_check CHECK ((accounting_status = ANY (ARRAY['Pending'::text, 'Processed'::text, 'Closed'::text]))),
    CONSTRAINT finance_entries_payment_status_check CHECK ((payment_status = ANY (ARRAY['Pending'::text, 'Partial'::text, 'Paid'::text]))),
    CONSTRAINT finance_entries_work_type_check CHECK ((work_type = ANY (ARRAY['Spare Purchases'::text, 'Outsourced Work'::text, 'Job Card'::text])))
);


ALTER TABLE public.finance_entries OWNER TO postgres;

--
-- Name: holidays; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.holidays (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    date date NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.holidays OWNER TO postgres;

--
-- Name: issue_parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.issue_parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    issue_id uuid NOT NULL,
    part_id uuid NOT NULL,
    quantity_used numeric(10,2) NOT NULL,
    added_by uuid,
    added_at timestamp without time zone DEFAULT now(),
    outsource_part_disposition public.outsource_part_disposition,
    outsource_vendor_credit_amount numeric(10,2),
    CONSTRAINT issue_parts_outsource_credit_consistency CHECK (((outsource_part_disposition = 'retained_by_vendor_with_credit'::public.outsource_part_disposition) = (outsource_vendor_credit_amount IS NOT NULL))),
    CONSTRAINT issue_parts_quantity_used_check CHECK ((quantity_used > (0)::numeric))
);


ALTER TABLE public.issue_parts OWNER TO postgres;

--
-- Name: issues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.issues (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    issue_number text,
    created_at timestamp without time zone DEFAULT now(),
    ticket_id uuid NOT NULL,
    job_card_id uuid,
    description text NOT NULL,
    category public.issue_category NOT NULL,
    severity public.issue_severity DEFAULT 'Minor'::public.issue_severity,
    work_type public.work_type_enum,
    status public.issue_status DEFAULT 'Open'::public.issue_status,
    sla_days integer,
    sla_end_date timestamp with time zone,
    sla_status public.sla_status_enum DEFAULT 'Pending'::public.sla_status_enum,
    rating public.rating_enum,
    rating_remarks text,
    rated_at timestamp without time zone,
    labour_hours numeric(5,2),
    CONSTRAINT check_rated_at_after_created CHECK (((rated_at IS NULL) OR (rated_at >= created_at)))
);


ALTER TABLE public.issues OWNER TO postgres;

--
-- Name: job_cards; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.job_cards (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    job_card_number integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    type public.work_type_enum NOT NULL,
    assigned_mechanic_id uuid,
    vehicle_number text NOT NULL,
    site text NOT NULL,
    status public.job_card_status DEFAULT 'Open'::public.job_card_status,
    completed_at timestamp without time zone,
    remarks text,
    supplier_id uuid,
    invoice_url text,
    odometer integer,
    location_id uuid DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'::uuid NOT NULL,
    CONSTRAINT check_completed_after_created CHECK (((completed_at IS NULL) OR (completed_at >= created_at))),
    CONSTRAINT job_cards_odometer_check CHECK (((odometer IS NULL) OR (odometer >= 0))),
    CONSTRAINT outsource_completion_requires_invoice CHECK (((status <> 'Completed'::public.job_card_status) OR (type <> 'Outsource'::public.work_type_enum) OR (invoice_url IS NOT NULL)))
);


ALTER TABLE public.job_cards OWNER TO postgres;

--
-- Name: COLUMN job_cards.location_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.job_cards.location_id IS 'Workshop where the repair happens. InHouse cards consume stock from this location. Distinct from job_cards.site, which is the customer site the vehicle runs at.';


--
-- Name: job_cards_job_card_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.job_cards ALTER COLUMN job_card_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_cards_job_card_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tickets (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    ticket_number integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    site text NOT NULL,
    vehicle_number text NOT NULL,
    supervisor_name text NOT NULL,
    supervisor_id text NOT NULL,
    supervisor_contact text,
    photos text[],
    status public.ticket_status_new DEFAULT 'New'::public.ticket_status_new,
    tat_days integer,
    is_duplicate boolean DEFAULT false,
    merged_into_ticket_id uuid,
    created_by_user_id uuid NOT NULL,
    rating_comment text,
    rated_at timestamp with time zone,
    initial_remarks text,
    rejected_reason text,
    resolved_at timestamp without time zone,
    closed_at timestamp without time zone,
    final_sla_end_date timestamp with time zone,
    overall_sla_status public.sla_status_enum,
    rejection_reason text,
    rejection_comment text,
    acceptance_sla_status public.sla_status_enum DEFAULT 'Pending'::public.sla_status_enum,
    rejected_at timestamp with time zone,
    acceptance_sla_end_date timestamp with time zone,
    CONSTRAINT check_closed_after_resolved CHECK (((closed_at IS NULL) OR (resolved_at IS NULL) OR (closed_at >= resolved_at))),
    CONSTRAINT check_resolved_after_created CHECK (((resolved_at IS NULL) OR (resolved_at >= created_at)))
);


ALTER TABLE public.tickets OWNER TO postgres;

--
-- Name: COLUMN tickets.acceptance_sla_end_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.tickets.acceptance_sla_end_date IS 'When acceptance is due, in working days from creation. Stamped on insert; recomputed if acceptance_sla_days changes while the ticket is still awaiting acceptance.';


--
-- Name: maintenance_dashboard_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.maintenance_dashboard_stats AS
 SELECT count(*) AS total_tickets,
    count(*) FILTER (WHERE ((status)::text = 'New'::text)) AS pending_tickets,
    count(*) FILTER (WHERE ((overall_sla_status)::text = 'Violated'::text)) AS completion_sla_violated,
    ( SELECT count(*) AS count
           FROM public.job_cards
          WHERE ((job_cards.type)::text = 'InHouse'::text)) AS inhouse_count,
    ( SELECT count(*) AS count
           FROM public.job_cards
          WHERE ((job_cards.type)::text = 'Outsource'::text)) AS outsource_count,
    COALESCE(avg(EXTRACT(day FROM (
        CASE
            WHEN ((status)::text = 'Resolved'::text) THEN (resolved_at)::timestamp with time zone
            ELSE now()
        END - (created_at)::timestamp with time zone))), (0)::numeric) AS avg_tat_days
   FROM public.tickets;


ALTER VIEW public.maintenance_dashboard_stats OWNER TO postgres;

--
-- Name: outsource_invoice_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.outsource_invoice_payments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    outsource_invoice_id uuid NOT NULL,
    paid_on date NOT NULL,
    amount_paid numeric(12,2) NOT NULL,
    notes text,
    attachment_urls text[] DEFAULT '{}'::text[] NOT NULL,
    recorded_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.outsource_invoice_payments OWNER TO postgres;

--
-- Name: outsource_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.outsource_invoices (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    job_card_id uuid,
    date_of_activity date,
    invoice_no text,
    paid_by text,
    invoice_value numeric(12,2),
    approved_amount numeric(12,2),
    advance_amount numeric(12,2),
    payment_status text,
    payby_date date,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT outsource_invoices_paid_by_check CHECK ((paid_by = ANY (ARRAY['Accounts'::text, 'Nithin'::text, 'Manjunath'::text]))),
    CONSTRAINT outsource_invoices_payment_status_check CHECK ((payment_status = ANY (ARRAY['Approved'::text, 'Hold'::text, 'Reject'::text])))
);


ALTER TABLE public.outsource_invoices OWNER TO postgres;

--
-- Name: part_stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.part_stock (
    part_id uuid NOT NULL,
    location_id uuid NOT NULL,
    quantity numeric(10,2) DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT part_stock_quantity_nonneg CHECK ((quantity >= (0)::numeric))
);


ALTER TABLE public.part_stock OWNER TO postgres;

--
-- Name: TABLE part_stock; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.part_stock IS 'Authoritative stock per part per workshop location. parts.quantity_in_stock is the derived total.';


--
-- Name: part_units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.part_units (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    sort_order integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.part_units OWNER TO postgres;

--
-- Name: parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    part_number text,
    unit text DEFAULT 'pcs'::text,
    quantity_in_stock numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    created_via text DEFAULT 'manual'::text NOT NULL,
    CONSTRAINT parts_created_via_check CHECK ((created_via = ANY (ARRAY['manual'::text, 'outsource_jobcard'::text])))
);


ALTER TABLE public.parts OWNER TO postgres;

--
-- Name: purchase_invoice_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_invoice_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    invoice_id uuid NOT NULL,
    part_id uuid NOT NULL,
    quantity numeric(10,2) NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    gst_rate numeric(5,2) DEFAULT 0 NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    line_total numeric(12,2) GENERATED ALWAYS AS (round((((quantity * unit_price) - discount_amount) * ((1)::numeric + (gst_rate / 100.0))), 2)) STORED,
    CONSTRAINT purchase_invoice_items_discount_max CHECK ((discount_amount <= (quantity * unit_price))),
    CONSTRAINT purchase_invoice_items_discount_nonneg CHECK ((discount_amount >= (0)::numeric)),
    CONSTRAINT purchase_invoice_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT purchase_invoice_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


ALTER TABLE public.purchase_invoice_items OWNER TO postgres;

--
-- Name: purchase_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_invoices (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    invoice_number text NOT NULL,
    supplier_name text NOT NULL,
    invoice_date date NOT NULL,
    total_amount numeric(12,2),
    notes text,
    created_by uuid,
    created_at timestamp without time zone DEFAULT now(),
    invoice_file_url text,
    location_id uuid DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'::uuid NOT NULL
);


ALTER TABLE public.purchase_invoices OWNER TO postgres;

--
-- Name: COLUMN purchase_invoices.location_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.purchase_invoices.location_id IS 'Workshop all line items on this invoice are inwarded to. One invoice cannot span two locations.';


--
-- Name: scrap_disposal; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_disposal (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    disposal_date date NOT NULL,
    buyer_name text NOT NULL,
    buyer_contact text,
    payment_mode public.scrap_payment_mode NOT NULL,
    payment_reference text,
    total_value numeric(10,2) NOT NULL,
    receipt_photos text[] DEFAULT '{}'::text[] NOT NULL,
    notes text,
    recorded_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scrap_disposal_payment_reference_consistency CHECK ((((payment_mode = 'cash'::public.scrap_payment_mode) AND (payment_reference IS NULL)) OR ((payment_mode <> 'cash'::public.scrap_payment_mode) AND (payment_reference IS NOT NULL))))
);


ALTER TABLE public.scrap_disposal OWNER TO postgres;

--
-- Name: scrap_disposal_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_disposal_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    disposal_id uuid NOT NULL,
    scrap_inventory_id uuid NOT NULL,
    value_allocated numeric(10,2) NOT NULL,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scrap_disposal_items_value_allocated_positive CHECK ((value_allocated > (0)::numeric))
);


ALTER TABLE public.scrap_disposal_items OWNER TO postgres;

--
-- Name: scrap_excluded_parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_excluded_parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    source_job_card_id uuid NOT NULL,
    source_issue_id uuid NOT NULL,
    source_issue_part_id uuid,
    part_id_snapshot uuid,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    reason public.scrap_exclusion_reason NOT NULL,
    notes text,
    excluded_by uuid NOT NULL,
    excluded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_excluded_parts OWNER TO postgres;

--
-- Name: scrap_inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_inventory (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    source_ticket_id uuid NOT NULL,
    source_job_card_id uuid NOT NULL,
    source_issue_id uuid NOT NULL,
    source_issue_part_id uuid,
    source_vehicle_number text NOT NULL,
    part_id_snapshot uuid,
    part_name_snapshot text NOT NULL,
    part_number_snapshot text,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    description text,
    notes text,
    estimated_value numeric(10,2),
    photos text[] DEFAULT '{}'::text[] NOT NULL,
    status public.scrap_item_status DEFAULT 'in_storage'::public.scrap_item_status NOT NULL,
    received_by uuid,
    received_at timestamp with time zone,
    current_location text,
    outsource_part_disposition_snapshot public.outsource_part_disposition,
    outsource_vendor_credit_amount_snapshot numeric(10,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    location_id uuid DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'::uuid NOT NULL
);


ALTER TABLE public.scrap_inventory OWNER TO postgres;

--
-- Name: COLUMN scrap_inventory.location_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scrap_inventory.location_id IS 'Workshop holding this salvage item, inherited from the source job card. Supersedes the unused free-text current_location column.';


--
-- Name: scrap_writeoff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_writeoff (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    writeoff_date date NOT NULL,
    reason public.scrap_writeoff_reason NOT NULL,
    description text NOT NULL,
    evidence_photos text[] DEFAULT '{}'::text[] NOT NULL,
    notes text,
    recorded_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_writeoff OWNER TO postgres;

--
-- Name: scrap_writeoff_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_writeoff_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    writeoff_id uuid NOT NULL,
    scrap_inventory_id uuid NOT NULL,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_writeoff_items OWNER TO postgres;

--
-- Name: sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sites (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    display_name text,
    corp_id integer
);


ALTER TABLE public.sites OWNER TO postgres;

--
-- Name: COLUMN sites.display_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.sites.display_name IS 'Full school name (corpName) from the Roorides corporation mapping. Display only; NULL until the sync finds a matching corpShortName.';


--
-- Name: COLUMN sites.corp_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.sites.corp_id IS 'Roorides corpId for this site. Display only; NULL until the sync finds a matching corpShortName.';


--
-- Name: sla_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sla_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid,
    event_type text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    metadata jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT sla_events_event_type_check CHECK ((event_type = ANY (ARRAY['CREATED'::text, 'ASSIGNED'::text, 'COMPLETED'::text, 'STATUS_CHANGE'::text, 'REJECTED'::text, 'COMMENT'::text])))
);


ALTER TABLE public.sla_events OWNER TO postgres;

--
-- Name: sla_rules_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sla_rules_config (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    category public.issue_category NOT NULL,
    severity public.issue_severity NOT NULL,
    sla_days integer NOT NULL
);


ALTER TABLE public.sla_rules_config OWNER TO postgres;

--
-- Name: stock_audit_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_audit_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    audit_id uuid NOT NULL,
    part_id uuid NOT NULL,
    part_name_snapshot text DEFAULT ''::text NOT NULL,
    part_number_snapshot text,
    unit_snapshot text DEFAULT 'pcs'::text NOT NULL,
    system_qty numeric(10,2) DEFAULT 0 NOT NULL,
    counted_qty numeric(10,2),
    variance numeric(10,2) GENERATED ALWAYS AS ((counted_qty - system_qty)) STORED,
    was_found_row boolean DEFAULT false NOT NULL,
    reason text,
    reason_notes text,
    moved_during_audit numeric(10,2),
    applied_delta numeric(10,2),
    final_qty numeric(10,2),
    unit_value_snapshot numeric(12,2),
    variance_value numeric(14,2),
    CONSTRAINT stock_audit_items_counted_nonneg CHECK (((counted_qty IS NULL) OR (counted_qty >= (0)::numeric))),
    CONSTRAINT stock_audit_items_reason_check CHECK (((reason IS NULL) OR (reason = ANY (ARRAY['missing'::text, 'stolen'::text, 'damaged'::text, 'found'::text, 'other'::text]))))
);


ALTER TABLE public.stock_audit_items OWNER TO postgres;

--
-- Name: TABLE stock_audit_items; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.stock_audit_items IS 'One counted part per audit. system_qty is frozen when the count sheet is generated; variance is measured against it, not against live stock, so parts consumed mid-audit are not silently reversed.';


--
-- Name: COLUMN stock_audit_items.system_qty; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.stock_audit_items.system_qty IS 'What the app believed was here when the count sheet was generated. Never updated.';


--
-- Name: COLUMN stock_audit_items.was_found_row; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.stock_audit_items.was_found_row IS 'The part was written onto a blank row on the sheet rather than printed on it — stock the app did not know was here.';


--
-- Name: COLUMN stock_audit_items.moved_during_audit; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.stock_audit_items.moved_during_audit IS 'Live stock minus system_qty at the moment of completion — legitimate consumption, purchases and transfers that happened while the audit was open. Recorded for explanation only; the variance is applied on top of it.';


--
-- Name: COLUMN stock_audit_items.unit_value_snapshot; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.stock_audit_items.unit_value_snapshot IS 'Latest purchase price per unit, net of discount and before GST, frozen at completion. NULL when the part has never been purchased.';


--
-- Name: stock_audits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_audits (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    location_id uuid NOT NULL,
    status text DEFAULT 'counting'::text NOT NULL,
    notes text,
    started_by uuid,
    started_by_name text DEFAULT ''::text NOT NULL,
    started_at timestamp without time zone DEFAULT now() NOT NULL,
    counts_uploaded_by uuid,
    counts_uploaded_by_name text DEFAULT ''::text NOT NULL,
    counts_uploaded_at timestamp without time zone,
    completed_by uuid,
    completed_by_name text DEFAULT ''::text NOT NULL,
    completed_at timestamp without time zone,
    cancelled_by uuid,
    cancelled_by_name text DEFAULT ''::text NOT NULL,
    cancelled_at timestamp without time zone,
    cancel_reason text,
    total_parts integer DEFAULT 0 NOT NULL,
    variance_parts integer DEFAULT 0 NOT NULL,
    net_units numeric(12,2) DEFAULT 0 NOT NULL,
    net_value numeric(14,2) DEFAULT 0 NOT NULL,
    unvalued_parts integer DEFAULT 0 NOT NULL,
    audit_number integer NOT NULL,
    CONSTRAINT stock_audits_status_check CHECK ((status = ANY (ARRAY['counting'::text, 'review'::text, 'completed'::text, 'cancelled'::text])))
);


ALTER TABLE public.stock_audits OWNER TO postgres;

--
-- Name: TABLE stock_audits; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.stock_audits IS 'Physical stock counts, one per workshop at a time. Immutable once completed: a wrong count is corrected by running another audit, never by editing this one.';


--
-- Name: COLUMN stock_audits.audit_number; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.stock_audits.audit_number IS 'Human-readable reference, shown in the app as AUD-<n>. Sequential across all workshops.';


--
-- Name: stock_audits_audit_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_audits_audit_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_audits_audit_number_seq OWNER TO postgres;

--
-- Name: stock_audits_audit_number_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_audits_audit_number_seq OWNED BY public.stock_audits.audit_number;


--
-- Name: stock_transfer_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_transfer_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    transfer_id uuid NOT NULL,
    part_id uuid NOT NULL,
    quantity numeric(10,2) NOT NULL,
    CONSTRAINT stock_transfer_items_quantity_positive CHECK ((quantity > (0)::numeric))
);


ALTER TABLE public.stock_transfer_items OWNER TO postgres;

--
-- Name: stock_transfers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_transfers (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    from_location_id uuid NOT NULL,
    to_location_id uuid NOT NULL,
    notes text,
    transferred_by uuid,
    transferred_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_transfers_distinct_locations CHECK ((from_location_id <> to_location_id))
);


ALTER TABLE public.stock_transfers OWNER TO postgres;

--
-- Name: TABLE stock_transfers; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.stock_transfers IS 'Audit trail of parts moved between workshops. Immutable: correct a mistake with a transfer in the opposite direction.';


--
-- Name: supervisor_dashboard_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.supervisor_dashboard_stats AS
 SELECT t.site,
    count(*) FILTER (WHERE ((t.status)::text = 'New'::text)) AS pending_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Accepted'::text)) AS accepted_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Resolved'::text)) AS completed_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Rejected'::text)) AS rejected_count,
    count(*) FILTER (WHERE ((t.overall_sla_status)::text = 'Violated'::text)) AS sla_violated_count,
    COALESCE(avg(
        CASE
            WHEN ((i.rating)::text = 'Good'::text) THEN 2
            WHEN ((i.rating)::text = 'Ok'::text) THEN 1
            WHEN ((i.rating)::text = 'Bad'::text) THEN 0
            ELSE NULL::integer
        END), (0)::numeric) AS avg_csat_score
   FROM (public.tickets t
     LEFT JOIN public.issues i ON ((i.ticket_id = t.id)))
  GROUP BY t.site;


ALTER VIEW public.supervisor_dashboard_stats OWNER TO postgres;

--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'pending'::text,
    email text,
    entity_name text NOT NULL,
    entity_type text,
    entity_type_other text,
    registered_office_address text NOT NULL,
    nature_of_work text NOT NULL,
    workshop_address text,
    owner_name text NOT NULL,
    owner_contact text NOT NULL,
    owner_email text,
    accounts_contact_name text,
    accounts_contact_number text,
    accounts_email text,
    sales_contact_name text,
    sales_contact_number text,
    sales_email text,
    po_communication_emails text,
    pan_number text,
    pan_copy_url text,
    gstin text,
    gst_registration_type text,
    gst_certificate_url text,
    msme_udyam_number text,
    udyam_certificate_url text,
    pf_registration_number text,
    pf_certificate_url text,
    esi_registration_number text,
    esi_certificate_url text,
    labour_license_number text,
    bank_name text,
    bank_branch text,
    account_holder_name text,
    account_number text,
    ifsc_code text,
    account_type text,
    cancelled_cheque_url text,
    years_of_experience text,
    major_clients text,
    skilled_manpower_available boolean,
    brand_spares_usage text,
    payment_terms_days text,
    submitted_by text,
    created_via text DEFAULT 'registration'::text NOT NULL,
    created_by uuid,
    CONSTRAINT suppliers_created_via_check CHECK ((created_via = ANY (ARRAY['registration'::text, 'quick_add'::text]))),
    CONSTRAINT suppliers_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_settings (
    key text NOT NULL,
    value text NOT NULL,
    description text,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.system_settings OWNER TO postgres;

--
-- Name: tickets_ticket_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tickets ALTER COLUMN ticket_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tickets_ticket_number_seq
    START WITH 1434
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    target_user_id uuid NOT NULL,
    target_name text DEFAULT ''::text NOT NULL,
    target_email text DEFAULT ''::text NOT NULL,
    action text DEFAULT 'UPDATE'::text NOT NULL,
    changed_fields text[] DEFAULT '{}'::text[] NOT NULL,
    old_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    new_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    performed_by uuid,
    performed_by_name text DEFAULT ''::text NOT NULL,
    performed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_audit_logs_action_check CHECK ((action = ANY (ARRAY['CREATE'::text, 'UPDATE'::text, 'ACTIVATE'::text, 'DEACTIVATE'::text])))
);


ALTER TABLE public.user_audit_logs OWNER TO postgres;

--
-- Name: user_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_settings (
    user_id uuid NOT NULL,
    notify_daily_digest boolean DEFAULT false,
    digest_preferences jsonb DEFAULT '{"created_24h": true, "rejected_24h": true, "sla_expiring": true}'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.user_settings OWNER TO postgres;

--
-- Name: user_sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    site_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_sites OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    name text NOT NULL,
    employee_id text,
    contact text,
    role text NOT NULL,
    site text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['supervisor'::text, 'maintenance_exec'::text, 'finance'::text, 'mechanic'::text, 'electrician'::text, 'super_admin'::text])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: vehicle_sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicle_sites (
    vehicle_id uuid NOT NULL,
    site_name text NOT NULL
);


ALTER TABLE public.vehicle_sites OWNER TO postgres;

--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicles (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    registration_number text NOT NULL,
    type text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    make text,
    model text,
    year integer,
    notes text,
    raw_data jsonb
);


ALTER TABLE public.vehicles OWNER TO postgres;

--
-- Name: workshop_locations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workshop_locations (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    address text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.workshop_locations OWNER TO postgres;

--
-- Name: TABLE workshop_locations; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.workshop_locations IS 'Physical workshops. Parts stock, job cards and scrap are located at one of these. Not the same as public.sites.';


--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea
)
PARTITION BY RANGE (inserted_at);


ALTER TABLE realtime.messages OWNER TO supabase_realtime_admin;

--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: supabase_admin
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE realtime.schema_migrations OWNER TO supabase_admin;

--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    selected_columns text[],
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE realtime.subscription OWNER TO supabase_realtime_admin;

--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


ALTER TABLE storage.buckets OWNER TO supabase_storage_admin;

--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


ALTER TABLE storage.buckets_analytics OWNER TO supabase_storage_admin;

--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.buckets_vectors OWNER TO supabase_storage_admin;

--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE storage.migrations OWNER TO supabase_storage_admin;

--
-- Name: objects; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb
);


ALTER TABLE storage.objects OWNER TO supabase_storage_admin;

--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: supabase_storage_admin
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb,
    metadata jsonb
);


ALTER TABLE storage.s3_multipart_uploads OWNER TO supabase_storage_admin;

--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.s3_multipart_uploads_parts OWNER TO supabase_storage_admin;

--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: supabase_storage_admin
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE storage.vector_indexes OWNER TO supabase_storage_admin;

--
-- Name: schema_migrations; Type: TABLE; Schema: supabase_migrations; Owner: postgres
--

CREATE TABLE supabase_migrations.schema_migrations (
    version text NOT NULL,
    statements text[],
    name text,
    created_by text,
    idempotency_key text,
    rollback text[]
);


ALTER TABLE supabase_migrations.schema_migrations OWNER TO postgres;

--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Name: stock_audits audit_number; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits ALTER COLUMN audit_number SET DEFAULT nextval('public.stock_audits_audit_number_seq'::regclass);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: custom_oauth_providers custom_oauth_providers_identifier_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_identifier_key UNIQUE (identifier);


--
-- Name: custom_oauth_providers custom_oauth_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: webauthn_challenges webauthn_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_pkey PRIMARY KEY (id);


--
-- Name: webauthn_credentials webauthn_credentials_pkey; Type: CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: finance_entries finance_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_pkey PRIMARY KEY (id);


--
-- Name: holidays holidays_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT holidays_date_key UNIQUE (date);


--
-- Name: holidays holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT holidays_pkey PRIMARY KEY (id);


--
-- Name: issue_parts issue_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_pkey PRIMARY KEY (id);


--
-- Name: issues issues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_pkey PRIMARY KEY (id);


--
-- Name: job_cards job_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_pkey PRIMARY KEY (id);


--
-- Name: outsource_invoice_payments outsource_invoice_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_pkey PRIMARY KEY (id);


--
-- Name: outsource_invoices outsource_invoices_job_card_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_job_card_id_key UNIQUE (job_card_id);


--
-- Name: outsource_invoices outsource_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_pkey PRIMARY KEY (id);


--
-- Name: part_stock part_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_stock
    ADD CONSTRAINT part_stock_pkey PRIMARY KEY (part_id, location_id);


--
-- Name: part_units part_units_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_units
    ADD CONSTRAINT part_units_name_key UNIQUE (name);


--
-- Name: part_units part_units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_units
    ADD CONSTRAINT part_units_pkey PRIMARY KEY (id);


--
-- Name: parts parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parts
    ADD CONSTRAINT parts_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoice_items purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoices purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_pkey PRIMARY KEY (id);


--
-- Name: scrap_disposal_items scrap_disposal_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_pkey PRIMARY KEY (id);


--
-- Name: scrap_disposal_items scrap_disposal_items_unique_item_per_disposal; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_unique_item_per_disposal UNIQUE (disposal_id, scrap_inventory_id);


--
-- Name: scrap_disposal scrap_disposal_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal
    ADD CONSTRAINT scrap_disposal_pkey PRIMARY KEY (id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_pkey PRIMARY KEY (id);


--
-- Name: scrap_inventory scrap_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_pkey PRIMARY KEY (id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_pkey PRIMARY KEY (id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_unique_item_per_writeoff; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_unique_item_per_writeoff UNIQUE (writeoff_id, scrap_inventory_id);


--
-- Name: scrap_writeoff scrap_writeoff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff
    ADD CONSTRAINT scrap_writeoff_pkey PRIMARY KEY (id);


--
-- Name: sites sites_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_name_key UNIQUE (name);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: sla_events sla_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_pkey PRIMARY KEY (id);


--
-- Name: sla_rules_config sla_rules_config_category_severity_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules_config
    ADD CONSTRAINT sla_rules_config_category_severity_key UNIQUE (category, severity);


--
-- Name: sla_rules_config sla_rules_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules_config
    ADD CONSTRAINT sla_rules_config_pkey PRIMARY KEY (id);


--
-- Name: stock_audit_items stock_audit_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audit_items
    ADD CONSTRAINT stock_audit_items_pkey PRIMARY KEY (id);


--
-- Name: stock_audit_items stock_audit_items_unique_part; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audit_items
    ADD CONSTRAINT stock_audit_items_unique_part UNIQUE (audit_id, part_id);


--
-- Name: stock_audits stock_audits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_pkey PRIMARY KEY (id);


--
-- Name: stock_transfer_items stock_transfer_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_pkey PRIMARY KEY (id);


--
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pan_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pan_number_key UNIQUE (pan_number);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (key);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: user_audit_logs user_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_audit_logs
    ADD CONSTRAINT user_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: user_settings user_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_pkey PRIMARY KEY (user_id);


--
-- Name: user_sites user_sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_pkey PRIMARY KEY (id);


--
-- Name: user_sites user_sites_user_id_site_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_user_id_site_id_key UNIQUE (user_id, site_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vehicle_sites vehicle_sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_pkey PRIMARY KEY (vehicle_id, site_name);


--
-- Name: vehicles vehicles_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_number_key UNIQUE (registration_number);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);


--
-- Name: workshop_locations workshop_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workshop_locations
    ADD CONSTRAINT workshop_locations_pkey PRIMARY KEY (id);


--
-- Name: messages messages_payload_exclusive; Type: CHECK CONSTRAINT; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE realtime.messages
    ADD CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL))) NOT VALID;


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: supabase_admin
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_idempotency_key_key; Type: CONSTRAINT; Schema: supabase_migrations; Owner: postgres
--

ALTER TABLE ONLY supabase_migrations.schema_migrations
    ADD CONSTRAINT schema_migrations_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: supabase_migrations; Owner: postgres
--

ALTER TABLE ONLY supabase_migrations.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: custom_oauth_providers_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX custom_oauth_providers_created_at_idx ON auth.custom_oauth_providers USING btree (created_at);


--
-- Name: custom_oauth_providers_enabled_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX custom_oauth_providers_enabled_idx ON auth.custom_oauth_providers USING btree (enabled);


--
-- Name: custom_oauth_providers_identifier_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX custom_oauth_providers_identifier_idx ON auth.custom_oauth_providers USING btree (identifier);


--
-- Name: custom_oauth_providers_provider_type_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX custom_oauth_providers_provider_type_idx ON auth.custom_oauth_providers USING btree (provider_type);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: idx_users_created_at_desc; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_users_created_at_desc ON auth.users USING btree (created_at DESC);


--
-- Name: idx_users_email; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_users_email ON auth.users USING btree (email);


--
-- Name: idx_users_last_sign_in_at_desc; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_users_last_sign_in_at_desc ON auth.users USING btree (last_sign_in_at DESC);


--
-- Name: idx_users_name; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX idx_users_name ON auth.users USING btree (((raw_user_meta_data ->> 'name'::text))) WHERE ((raw_user_meta_data ->> 'name'::text) IS NOT NULL);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: supabase_auth_admin
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: webauthn_challenges_expires_at_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX webauthn_challenges_expires_at_idx ON auth.webauthn_challenges USING btree (expires_at);


--
-- Name: webauthn_challenges_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX webauthn_challenges_user_id_idx ON auth.webauthn_challenges USING btree (user_id);


--
-- Name: webauthn_credentials_credential_id_key; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE UNIQUE INDEX webauthn_credentials_credential_id_key ON auth.webauthn_credentials USING btree (credential_id);


--
-- Name: webauthn_credentials_user_id_idx; Type: INDEX; Schema: auth; Owner: supabase_auth_admin
--

CREATE INDEX webauthn_credentials_user_id_idx ON auth.webauthn_credentials USING btree (user_id);


--
-- Name: idx_finance_job_sheet_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_job_sheet_id ON public.finance_entries USING btree (job_sheet_id);


--
-- Name: idx_finance_site; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_site ON public.finance_entries USING btree (site);


--
-- Name: idx_finance_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_ticket_id ON public.finance_entries USING btree (ticket_id);


--
-- Name: idx_issues_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_job_card_id ON public.issues USING btree (job_card_id);


--
-- Name: idx_issues_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_status ON public.issues USING btree (status);


--
-- Name: idx_issues_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_ticket_id ON public.issues USING btree (ticket_id);


--
-- Name: idx_job_cards_mechanic; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_job_cards_mechanic ON public.job_cards USING btree (assigned_mechanic_id);


--
-- Name: idx_job_cards_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_job_cards_status ON public.job_cards USING btree (status);


--
-- Name: idx_scrap_disposal_disposal_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_disposal_date ON public.scrap_disposal USING btree (disposal_date DESC);


--
-- Name: idx_scrap_disposal_items_disposal_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_items_disposal_id ON public.scrap_disposal_items USING btree (disposal_id);


--
-- Name: idx_scrap_disposal_items_scrap_inventory_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_items_scrap_inventory_id ON public.scrap_disposal_items USING btree (scrap_inventory_id);


--
-- Name: idx_scrap_disposal_recorded_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_recorded_by ON public.scrap_disposal USING btree (recorded_by);


--
-- Name: idx_scrap_excluded_parts_issue_part_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_excluded_parts_issue_part_id ON public.scrap_excluded_parts USING btree (source_issue_part_id);


--
-- Name: idx_scrap_excluded_parts_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_excluded_parts_job_card_id ON public.scrap_excluded_parts USING btree (source_job_card_id);


--
-- Name: idx_scrap_inventory_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_created_at ON public.scrap_inventory USING btree (created_at DESC);


--
-- Name: idx_scrap_inventory_issue_part_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_issue_part_id ON public.scrap_inventory USING btree (source_issue_part_id);


--
-- Name: idx_scrap_inventory_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_job_card_id ON public.scrap_inventory USING btree (source_job_card_id);


--
-- Name: idx_scrap_inventory_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_status ON public.scrap_inventory USING btree (status);


--
-- Name: idx_scrap_inventory_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_ticket_id ON public.scrap_inventory USING btree (source_ticket_id);


--
-- Name: idx_scrap_writeoff_items_scrap_inventory_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_items_scrap_inventory_id ON public.scrap_writeoff_items USING btree (scrap_inventory_id);


--
-- Name: idx_scrap_writeoff_items_writeoff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_items_writeoff_id ON public.scrap_writeoff_items USING btree (writeoff_id);


--
-- Name: idx_scrap_writeoff_recorded_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_recorded_by ON public.scrap_writeoff USING btree (recorded_by);


--
-- Name: idx_scrap_writeoff_writeoff_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_writeoff_date ON public.scrap_writeoff USING btree (writeoff_date DESC);


--
-- Name: idx_sla_events_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sla_events_ticket_id ON public.sla_events USING btree (ticket_id);


--
-- Name: idx_tickets_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_created_at ON public.tickets USING btree (created_at DESC);


--
-- Name: idx_tickets_created_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_created_by ON public.tickets USING btree (created_by_user_id);


--
-- Name: idx_tickets_site; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_site ON public.tickets USING btree (site);


--
-- Name: idx_tickets_site_new; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_site_new ON public.tickets USING btree (site);


--
-- Name: idx_tickets_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_status ON public.tickets USING btree (status);


--
-- Name: idx_tickets_status_new; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_status_new ON public.tickets USING btree (status);


--
-- Name: idx_tickets_vehicle_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_vehicle_number ON public.tickets USING btree (vehicle_number);


--
-- Name: job_cards_location_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX job_cards_location_idx ON public.job_cards USING btree (location_id);


--
-- Name: outsource_invoice_payments_invoice_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoice_payments_invoice_id_idx ON public.outsource_invoice_payments USING btree (outsource_invoice_id);


--
-- Name: outsource_invoices_job_card_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_job_card_id_idx ON public.outsource_invoices USING btree (job_card_id);


--
-- Name: outsource_invoices_paid_by_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_paid_by_idx ON public.outsource_invoices USING btree (paid_by);


--
-- Name: outsource_invoices_payby_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_payby_date_idx ON public.outsource_invoices USING btree (payby_date);


--
-- Name: outsource_invoices_payment_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_payment_status_idx ON public.outsource_invoices USING btree (payment_status);


--
-- Name: part_stock_location_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX part_stock_location_idx ON public.part_stock USING btree (location_id);


--
-- Name: purchase_invoices_location_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX purchase_invoices_location_idx ON public.purchase_invoices USING btree (location_id);


--
-- Name: scrap_inventory_location_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX scrap_inventory_location_idx ON public.scrap_inventory USING btree (location_id);


--
-- Name: stock_audit_items_audit_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_audit_items_audit_idx ON public.stock_audit_items USING btree (audit_id);


--
-- Name: stock_audit_items_part_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_audit_items_part_idx ON public.stock_audit_items USING btree (part_id);


--
-- Name: stock_audits_location_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_audits_location_idx ON public.stock_audits USING btree (location_id);


--
-- Name: stock_audits_number_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX stock_audits_number_key ON public.stock_audits USING btree (audit_number);


--
-- Name: stock_audits_one_open_per_location; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX stock_audits_one_open_per_location ON public.stock_audits USING btree (location_id) WHERE (status = ANY (ARRAY['counting'::text, 'review'::text]));


--
-- Name: stock_audits_started_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_audits_started_idx ON public.stock_audits USING btree (started_at DESC);


--
-- Name: stock_audits_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_audits_status_idx ON public.stock_audits USING btree (status);


--
-- Name: stock_transfer_items_part_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_transfer_items_part_idx ON public.stock_transfer_items USING btree (part_id);


--
-- Name: stock_transfer_items_transfer_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_transfer_items_transfer_idx ON public.stock_transfer_items USING btree (transfer_id);


--
-- Name: stock_transfers_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_transfers_date_idx ON public.stock_transfers USING btree (transferred_at DESC);


--
-- Name: stock_transfers_from_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_transfers_from_idx ON public.stock_transfers USING btree (from_location_id);


--
-- Name: stock_transfers_to_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stock_transfers_to_idx ON public.stock_transfers USING btree (to_location_id);


--
-- Name: user_audit_logs_performed_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_audit_logs_performed_at_idx ON public.user_audit_logs USING btree (performed_at DESC);


--
-- Name: user_audit_logs_target_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_audit_logs_target_idx ON public.user_audit_logs USING btree (target_user_id);


--
-- Name: workshop_locations_name_lower_key; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX workshop_locations_name_lower_key ON public.workshop_locations USING btree (lower(name));


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_selec; Type: INDEX; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_selec ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter, COALESCE(selected_columns, '{}'::text[]));


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: supabase_storage_admin
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: outsource_invoices outsource_invoices_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER outsource_invoices_set_updated_at BEFORE UPDATE ON public.outsource_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: issues trg_acceptance_sla_on_first_issue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_acceptance_sla_on_first_issue AFTER INSERT ON public.issues FOR EACH ROW EXECUTE FUNCTION public.trg_set_acceptance_sla_on_first_issue();


--
-- Name: issues trg_generate_issue_number; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_generate_issue_number BEFORE INSERT ON public.issues FOR EACH ROW WHEN ((new.issue_number IS NULL)) EXECUTE FUNCTION public.generate_issue_number();


--
-- Name: holidays trg_holidays_recalc; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_holidays_recalc AFTER INSERT OR DELETE OR UPDATE ON public.holidays FOR EACH STATEMENT EXECUTE FUNCTION public.trg_recalculate_open_slas();


--
-- Name: issues trg_issue_sla_dynamic; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_issue_sla_dynamic BEFORE INSERT OR UPDATE ON public.issues FOR EACH ROW EXECUTE FUNCTION public.calculate_issue_sla_dynamic();


--
-- Name: scrap_inventory trg_set_scrap_location; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_set_scrap_location BEFORE INSERT ON public.scrap_inventory FOR EACH ROW EXECUTE FUNCTION public.set_scrap_location_from_job_card();


--
-- Name: sla_rules_config trg_sla_rules_config_recalc; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sla_rules_config_recalc AFTER INSERT OR DELETE OR UPDATE ON public.sla_rules_config FOR EACH STATEMENT EXECUTE FUNCTION public.trg_recalculate_open_slas();


--
-- Name: tickets trg_stamp_acceptance_deadline; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_stamp_acceptance_deadline BEFORE INSERT ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.trg_stamp_acceptance_deadline();


--
-- Name: tickets trg_stamp_rejected_at_and_acceptance_sla; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_stamp_rejected_at_and_acceptance_sla BEFORE UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla();


--
-- Name: part_stock trg_sync_part_total_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_part_total_stock AFTER INSERT OR DELETE OR UPDATE ON public.part_stock FOR EACH ROW EXECUTE FUNCTION public.sync_part_total_stock();


--
-- Name: system_settings trg_system_settings_sla_recalc; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_system_settings_sla_recalc AFTER INSERT OR UPDATE ON public.system_settings FOR EACH ROW WHEN ((new.key = ANY (ARRAY['sla_weekly_offs'::text, 'acceptance_sla_days'::text]))) EXECUTE FUNCTION public.trg_recalculate_open_slas();


--
-- Name: tickets trg_ticket_sla_on_status_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_ticket_sla_on_status_change AFTER UPDATE OF status ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.recalculate_ticket_sla_on_status_change();


--
-- Name: issues trg_update_ticket_sla_agg; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_ticket_sla_agg AFTER INSERT OR UPDATE OF sla_end_date, status, category, severity ON public.issues FOR EACH ROW EXECUTE FUNCTION public.calculate_ticket_overall_sla();


--
-- Name: purchase_invoice_items trigger_add_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_add_part_inventory AFTER INSERT ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.add_part_to_inventory();


--
-- Name: purchase_invoice_items trigger_adjust_part_inventory_on_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_adjust_part_inventory_on_update AFTER UPDATE ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.adjust_part_inventory_on_update();


--
-- Name: issue_parts trigger_deduct_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_deduct_part_inventory AFTER INSERT ON public.issue_parts FOR EACH ROW EXECUTE FUNCTION public.deduct_part_from_inventory();


--
-- Name: purchase_invoices trigger_delete_invoice_items_first; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_delete_invoice_items_first BEFORE DELETE ON public.purchase_invoices FOR EACH ROW EXECUTE FUNCTION public.delete_invoice_items_first();


--
-- Name: job_cards trigger_guard_job_card_location_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_guard_job_card_location_change BEFORE UPDATE OF location_id ON public.job_cards FOR EACH ROW EXECUTE FUNCTION public.guard_job_card_location_change();


--
-- Name: purchase_invoices trigger_move_invoice_stock_on_location_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_move_invoice_stock_on_location_change AFTER UPDATE OF location_id ON public.purchase_invoices FOR EACH ROW EXECUTE FUNCTION public.move_invoice_stock_on_location_change();


--
-- Name: issue_parts trigger_restore_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_restore_part_inventory AFTER DELETE ON public.issue_parts FOR EACH ROW EXECUTE FUNCTION public.restore_part_to_inventory();


--
-- Name: purchase_invoice_items trigger_reverse_part_inventory_on_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_reverse_part_inventory_on_delete AFTER DELETE ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.reverse_part_inventory_on_delete();


--
-- Name: issues trigger_update_ticket_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_ticket_status AFTER INSERT OR UPDATE ON public.issues FOR EACH ROW EXECUTE FUNCTION public.update_ticket_status_on_issue_change();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: supabase_realtime_admin
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: supabase_storage_admin
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: webauthn_challenges webauthn_challenges_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: webauthn_credentials webauthn_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: audit_logs audit_logs_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: finance_entries finance_entries_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id);


--
-- Name: finance_entries finance_entries_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: finance_entries finance_entries_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: issue_parts issue_parts_added_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.users(id);


--
-- Name: issue_parts issue_parts_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issues(id) ON DELETE CASCADE;


--
-- Name: issue_parts issue_parts_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: issues issues_job_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_job_card_id_fkey FOREIGN KEY (job_card_id) REFERENCES public.job_cards(id) ON DELETE SET NULL;


--
-- Name: issues issues_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: job_cards job_cards_assigned_mechanic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_assigned_mechanic_id_fkey FOREIGN KEY (assigned_mechanic_id) REFERENCES public.users(id);


--
-- Name: job_cards job_cards_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.workshop_locations(id);


--
-- Name: job_cards job_cards_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


--
-- Name: outsource_invoice_payments outsource_invoice_payments_outsource_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_outsource_invoice_id_fkey FOREIGN KEY (outsource_invoice_id) REFERENCES public.outsource_invoices(id) ON DELETE CASCADE;


--
-- Name: outsource_invoice_payments outsource_invoice_payments_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: outsource_invoices outsource_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: outsource_invoices outsource_invoices_job_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_job_card_id_fkey FOREIGN KEY (job_card_id) REFERENCES public.job_cards(id) ON DELETE CASCADE;


--
-- Name: part_stock part_stock_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_stock
    ADD CONSTRAINT part_stock_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.workshop_locations(id);


--
-- Name: part_stock part_stock_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_stock
    ADD CONSTRAINT part_stock_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id) ON DELETE CASCADE;


--
-- Name: purchase_invoice_items purchase_invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.purchase_invoices(id) ON DELETE CASCADE;


--
-- Name: purchase_invoice_items purchase_invoice_items_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: purchase_invoices purchase_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: purchase_invoices purchase_invoices_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.workshop_locations(id);


--
-- Name: scrap_disposal_items scrap_disposal_items_disposal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_disposal_fkey FOREIGN KEY (disposal_id) REFERENCES public.scrap_disposal(id);


--
-- Name: scrap_disposal_items scrap_disposal_items_scrap_inventory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_scrap_inventory_fkey FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id);


--
-- Name: scrap_disposal scrap_disposal_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal
    ADD CONSTRAINT scrap_disposal_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_excluded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_excluded_by_fkey FOREIGN KEY (excluded_by) REFERENCES public.users(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_issue_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_issue_fkey FOREIGN KEY (source_issue_id) REFERENCES public.issues(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_issue_part_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_issue_part_fkey FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id) ON DELETE SET NULL;


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_job_card_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_job_card_fkey FOREIGN KEY (source_job_card_id) REFERENCES public.job_cards(id);


--
-- Name: scrap_inventory scrap_inventory_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: scrap_inventory scrap_inventory_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.workshop_locations(id);


--
-- Name: scrap_inventory scrap_inventory_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(id);


--
-- Name: scrap_inventory scrap_inventory_source_issue_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_issue_fkey FOREIGN KEY (source_issue_id) REFERENCES public.issues(id);


--
-- Name: scrap_inventory scrap_inventory_source_issue_part_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_issue_part_fkey FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id) ON DELETE SET NULL;


--
-- Name: scrap_inventory scrap_inventory_source_job_card_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_job_card_fkey FOREIGN KEY (source_job_card_id) REFERENCES public.job_cards(id);


--
-- Name: scrap_inventory scrap_inventory_source_ticket_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_ticket_fkey FOREIGN KEY (source_ticket_id) REFERENCES public.tickets(id);


--
-- Name: scrap_inventory scrap_inventory_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_scrap_inventory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_scrap_inventory_fkey FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_writeoff_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_writeoff_fkey FOREIGN KEY (writeoff_id) REFERENCES public.scrap_writeoff(id);


--
-- Name: scrap_writeoff scrap_writeoff_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff
    ADD CONSTRAINT scrap_writeoff_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: sla_events sla_events_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: sla_events sla_events_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: stock_audit_items stock_audit_items_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audit_items
    ADD CONSTRAINT stock_audit_items_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.stock_audits(id) ON DELETE CASCADE;


--
-- Name: stock_audit_items stock_audit_items_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audit_items
    ADD CONSTRAINT stock_audit_items_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: stock_audits stock_audits_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.users(id);


--
-- Name: stock_audits stock_audits_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.users(id);


--
-- Name: stock_audits stock_audits_counts_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_counts_uploaded_by_fkey FOREIGN KEY (counts_uploaded_by) REFERENCES public.users(id);


--
-- Name: stock_audits stock_audits_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.workshop_locations(id);


--
-- Name: stock_audits stock_audits_started_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_audits
    ADD CONSTRAINT stock_audits_started_by_fkey FOREIGN KEY (started_by) REFERENCES public.users(id);


--
-- Name: stock_transfer_items stock_transfer_items_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: stock_transfer_items stock_transfer_items_transfer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_transfer_id_fkey FOREIGN KEY (transfer_id) REFERENCES public.stock_transfers(id) ON DELETE CASCADE;


--
-- Name: stock_transfers stock_transfers_from_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_from_location_id_fkey FOREIGN KEY (from_location_id) REFERENCES public.workshop_locations(id);


--
-- Name: stock_transfers stock_transfers_to_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_to_location_id_fkey FOREIGN KEY (to_location_id) REFERENCES public.workshop_locations(id);


--
-- Name: stock_transfers stock_transfers_transferred_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_transferred_by_fkey FOREIGN KEY (transferred_by) REFERENCES public.users(id);


--
-- Name: suppliers suppliers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: tickets tickets_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id);


--
-- Name: tickets tickets_merged_into_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_merged_into_ticket_id_fkey FOREIGN KEY (merged_into_ticket_id) REFERENCES public.tickets(id);


--
-- Name: tickets tickets_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: user_settings user_settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: user_sites user_sites_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: user_sites user_sites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: users users_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: vehicle_sites vehicle_sites_site_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_site_name_fkey FOREIGN KEY (site_name) REFERENCES public.sites(name) ON DELETE CASCADE;


--
-- Name: vehicle_sites vehicle_sites_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: supabase_auth_admin
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: sites All authenticated users see sites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "All authenticated users see sites" ON public.sites FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: vehicles All authenticated users see vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "All authenticated users see vehicles" ON public.vehicles FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: part_units Authenticated read part_units; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read part_units" ON public.part_units FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: workshop_locations Authenticated read workshop_locations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read workshop_locations" ON public.workshop_locations FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: vehicle_sites Authenticated users can read vehicle_sites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can read vehicle_sites" ON public.vehicle_sites FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: part_stock Authenticated users view part_stock; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users view part_stock" ON public.part_stock FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: parts Authenticated users view parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users view parts" ON public.parts FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: vehicles Authenticated users view vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users view vehicles" ON public.vehicles FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: outsource_invoice_payments Authenticated view invoice payments; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated view invoice payments" ON public.outsource_invoice_payments FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: outsource_invoices Authenticated view outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated view outsource invoices" ON public.outsource_invoices FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: tickets Creators can rate tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Creators can rate tickets" ON public.tickets FOR UPDATE TO authenticated USING ((auth.uid() = created_by_user_id)) WITH CHECK ((auth.uid() = created_by_user_id));


--
-- Name: sla_rules_config Everyone can read SLA rules config; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read SLA rules config" ON public.sla_rules_config FOR SELECT USING (true);


--
-- Name: holidays Everyone can read holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read holidays" ON public.holidays FOR SELECT USING (true);


--
-- Name: system_settings Everyone can read settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read settings" ON public.system_settings FOR SELECT USING (true);


--
-- Name: purchase_invoice_items Exec and finance delete invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance delete invoice items" ON public.purchase_invoice_items FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance insert invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance insert invoice items" ON public.purchase_invoice_items FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance insert invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance insert invoices" ON public.purchase_invoices FOR INSERT WITH CHECK (((auth.uid() = created_by) AND (EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text])))))));


--
-- Name: part_stock Exec and finance manage part_stock; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance manage part_stock" ON public.part_stock USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['maintenance_exec'::text, 'super_admin'::text, 'finance'::text]))))));


--
-- Name: parts Exec and finance manage parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance manage parts" ON public.parts USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: vehicles Exec and finance manage vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance manage vehicles" ON public.vehicles USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance update invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance update invoice items" ON public.purchase_invoice_items FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance update invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance update invoices" ON public.purchase_invoices FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance view invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view invoice items" ON public.purchase_invoice_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance view invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view invoices" ON public.purchase_invoices FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: stock_audit_items Exec and finance view stock_audit_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view stock_audit_items" ON public.stock_audit_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'super_admin'::text, 'maintenance_exec'::text]))))));


--
-- Name: stock_audits Exec and finance view stock_audits; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view stock_audits" ON public.stock_audits FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'super_admin'::text, 'maintenance_exec'::text]))))));


--
-- Name: stock_transfer_items Exec and finance view stock_transfer_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view stock_transfer_items" ON public.stock_transfer_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['maintenance_exec'::text, 'super_admin'::text, 'finance'::text]))))));


--
-- Name: stock_transfers Exec and finance view stock_transfers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view stock_transfers" ON public.stock_transfers FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['maintenance_exec'::text, 'super_admin'::text, 'finance'::text]))))));


--
-- Name: outsource_invoice_payments Exec finance insert invoice payments; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance insert invoice payments" ON public.outsource_invoice_payments FOR INSERT WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'finance'::text))))));


--
-- Name: outsource_invoices Exec finance supervisor insert outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance supervisor insert outsource invoices" ON public.outsource_invoices FOR INSERT WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text])))))));


--
-- Name: outsource_invoices Exec finance supervisor update outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance supervisor update outsource invoices" ON public.outsource_invoices FOR UPDATE USING ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text]))))))) WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text])))))));


--
-- Name: users Execs can read all profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can read all profiles" ON public.users FOR SELECT USING (public.is_maintenance_exec());


--
-- Name: tickets Execs can see all tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can see all tickets" ON public.tickets FOR SELECT USING (public.is_maintenance_exec());


--
-- Name: tickets Execs can update tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can update tickets" ON public.tickets FOR UPDATE USING (public.is_maintenance_exec());


--
-- Name: users Execs can update users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can update users" ON public.users FOR UPDATE USING (public.is_maintenance_exec());


--
-- Name: issues Execs manage issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage issues" ON public.issues USING (public.is_maintenance_exec());


--
-- Name: job_cards Execs manage job cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage job cards" ON public.job_cards USING (public.is_maintenance_exec());


--
-- Name: part_units Execs manage part_units; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage part_units" ON public.part_units USING (public.is_maintenance_exec());


--
-- Name: scrap_disposal Execs manage scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_disposal" ON public.scrap_disposal TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_disposal_items Execs manage scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_disposal_items" ON public.scrap_disposal_items TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_inventory Execs manage scrap_inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_inventory" ON public.scrap_inventory TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_writeoff Execs manage scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_writeoff" ON public.scrap_writeoff TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_writeoff_items Execs manage scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_writeoff_items" ON public.scrap_writeoff_items TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_excluded_parts Execs view scrap_excluded_parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs view scrap_excluded_parts" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING (public.is_maintenance_exec());


--
-- Name: finance_entries Finance creates entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance creates entries" ON public.finance_entries FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'super_admin'::text]))))));


--
-- Name: finance_entries Finance sees all entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance sees all entries" ON public.finance_entries FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'maintenance_exec'::text, 'super_admin'::text]))))));


--
-- Name: finance_entries Finance updates entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance updates entries" ON public.finance_entries FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'super_admin'::text]))))));


--
-- Name: job_cards Finance view job cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view job cards" ON public.job_cards FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_disposal Finance view scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_disposal" ON public.scrap_disposal FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_disposal_items Finance view scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_disposal_items" ON public.scrap_disposal_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_excluded_parts Finance view scrap_excluded_parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_excluded_parts" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_inventory Finance view scrap_inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_inventory" ON public.scrap_inventory FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_writeoff Finance view scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_writeoff" ON public.scrap_writeoff FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_writeoff_items Finance view scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_writeoff_items" ON public.scrap_writeoff_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: tickets Maintenance exec sees all tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Maintenance exec sees all tickets" ON public.tickets FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'maintenance_exec'::text)))));


--
-- Name: tickets Maintenance exec updates tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Maintenance exec updates tickets" ON public.tickets FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'maintenance_exec'::text)))));


--
-- Name: issue_parts Mechanics delete issue parts on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics delete issue parts on assigned cards" ON public.issue_parts FOR DELETE USING ((EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec())))));


--
-- Name: issue_parts Mechanics insert issue parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics insert issue parts" ON public.issue_parts FOR INSERT WITH CHECK (((auth.uid() = added_by) AND (EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec()))))));


--
-- Name: job_cards Mechanics update assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics update assigned cards" ON public.job_cards FOR UPDATE USING ((assigned_mechanic_id = auth.uid()));


--
-- Name: issues Mechanics update issues on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics update issues on assigned cards" ON public.issues FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.job_cards
  WHERE ((job_cards.id = issues.job_card_id) AND (job_cards.assigned_mechanic_id = auth.uid())))));


--
-- Name: job_cards Mechanics view assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics view assigned cards" ON public.job_cards FOR SELECT USING (((assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec()));


--
-- Name: issues Mechanics view issues on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics view issues on assigned cards" ON public.issues FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.job_cards
  WHERE ((job_cards.id = issues.job_card_id) AND (job_cards.assigned_mechanic_id = auth.uid())))));


--
-- Name: holidays Super admins can delete holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can delete holidays" ON public.holidays FOR DELETE USING (public.is_super_admin());


--
-- Name: holidays Super admins can insert holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can insert holidays" ON public.holidays FOR INSERT WITH CHECK (public.is_super_admin());


--
-- Name: system_settings Super admins can insert settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can insert settings" ON public.system_settings FOR INSERT WITH CHECK (public.is_super_admin());


--
-- Name: sla_rules_config Super admins can update SLA rules config; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update SLA rules config" ON public.sla_rules_config FOR UPDATE USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());


--
-- Name: holidays Super admins can update holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update holidays" ON public.holidays FOR UPDATE USING (public.is_super_admin());


--
-- Name: system_settings Super admins can update settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update settings" ON public.system_settings FOR UPDATE USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());


--
-- Name: workshop_locations Super admins insert workshop_locations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins insert workshop_locations" ON public.workshop_locations FOR INSERT WITH CHECK (public.is_super_admin());


--
-- Name: workshop_locations Super admins update workshop_locations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins update workshop_locations" ON public.workshop_locations FOR UPDATE USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());


--
-- Name: tickets Supervisors and execs create tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors and execs create tickets" ON public.tickets FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['supervisor'::text, 'maintenance_exec'::text, 'super_admin'::text]))))));


--
-- Name: issues Supervisors create issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors create issues" ON public.issues FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM (public.tickets t
     JOIN public.users u ON ((u.id = auth.uid())))
  WHERE ((t.id = issues.ticket_id) AND (u.role = 'supervisor'::text) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: tickets Supervisors see own site tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors see own site tickets" ON public.tickets FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (site IN ( SELECT s.name
   FROM (public.user_sites us
     JOIN public.sites s ON ((s.id = us.site_id)))
  WHERE (us.user_id = auth.uid())))));


--
-- Name: issues Supervisors update own ratings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors update own ratings" ON public.issues FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tickets t
  WHERE ((t.id = issues.ticket_id) AND (EXISTS ( SELECT 1
           FROM public.users
          WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: issues Supervisors view site issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site issues" ON public.issues FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tickets t
  WHERE ((t.id = issues.ticket_id) AND (EXISTS ( SELECT 1
           FROM public.users
          WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: scrap_inventory Supervisors view site scrap; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap" ON public.scrap_inventory FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND public.job_card_site_accessible_to_user(source_job_card_id)));


--
-- Name: scrap_excluded_parts Supervisors view site scrap excluded; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap excluded" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND public.job_card_site_accessible_to_user(source_job_card_id)));


--
-- Name: scrap_disposal Supervisors view site scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_disposal" ON public.scrap_disposal FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM (public.scrap_disposal_items sdi
     JOIN public.scrap_inventory si ON ((si.id = sdi.scrap_inventory_id)))
  WHERE ((sdi.disposal_id = scrap_disposal.id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_disposal_items Supervisors view site scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_disposal_items" ON public.scrap_disposal_items FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM public.scrap_inventory si
  WHERE ((si.id = scrap_disposal_items.scrap_inventory_id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_writeoff Supervisors view site scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_writeoff" ON public.scrap_writeoff FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM (public.scrap_writeoff_items swi
     JOIN public.scrap_inventory si ON ((si.id = swi.scrap_inventory_id)))
  WHERE ((swi.writeoff_id = scrap_writeoff.id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_writeoff_items Supervisors view site scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_writeoff_items" ON public.scrap_writeoff_items FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM public.scrap_inventory si
  WHERE ((si.id = scrap_writeoff_items.scrap_inventory_id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: audit_logs Users can insert audit logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert audit logs" ON public.audit_logs FOR INSERT WITH CHECK ((auth.uid() = performed_by));


--
-- Name: sla_events Users can insert events; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert events" ON public.sla_events FOR INSERT WITH CHECK ((auth.uid() = created_by));


--
-- Name: user_settings Users can insert their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert their own settings" ON public.user_settings FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: users Users can read own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own profile" ON public.users FOR SELECT USING ((auth.uid() = id));


--
-- Name: user_settings Users can update their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update their own settings" ON public.user_settings FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: audit_logs Users can view audit logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view audit logs" ON public.audit_logs FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: sla_events Users can view events for tickets they can access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view events for tickets they can access" ON public.sla_events FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tickets
  WHERE (tickets.id = sla_events.ticket_id))));


--
-- Name: user_settings Users can view their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view their own settings" ON public.user_settings FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: issue_parts View issue parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "View issue parts" ON public.issue_parts FOR SELECT USING ((EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec())))));


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: finance_entries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.finance_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: holidays; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

--
-- Name: issue_parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.issue_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: issues; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.issues ENABLE ROW LEVEL SECURITY;

--
-- Name: job_cards; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.job_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: outsource_invoice_payments; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.outsource_invoice_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: outsource_invoices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.outsource_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: part_stock; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.part_stock ENABLE ROW LEVEL SECURITY;

--
-- Name: part_units; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.part_units ENABLE ROW LEVEL SECURITY;

--
-- Name: parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.parts ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoice_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_disposal; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_disposal ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_disposal_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_disposal_items ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_excluded_parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_excluded_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_inventory; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_writeoff; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_writeoff ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_writeoff_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_writeoff_items ENABLE ROW LEVEL SECURITY;

--
-- Name: sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sla_events ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_rules_config; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sla_rules_config ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_audit_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stock_audit_items ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_audits; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stock_audits ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_transfer_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stock_transfer_items ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_transfers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers suppliers_auth_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_auth_select ON public.suppliers FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text])) AND (users.is_active = true)))));


--
-- Name: suppliers suppliers_exec_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_exec_update ON public.suppliers FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'super_admin'::text])) AND (users.is_active = true)))));


--
-- Name: suppliers suppliers_public_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_public_insert ON public.suppliers FOR INSERT WITH CHECK (true);


--
-- Name: system_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: tickets; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_audit_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: user_audit_logs user_audit_logs_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_audit_logs_select ON public.user_audit_logs FOR SELECT USING (public.is_super_admin());


--
-- Name: user_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: user_sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_sites ENABLE ROW LEVEL SECURITY;

--
-- Name: user_sites user_sites_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_delete ON public.user_sites FOR DELETE USING (public.is_maintenance_exec());


--
-- Name: user_sites user_sites_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_insert ON public.user_sites FOR INSERT WITH CHECK (public.is_maintenance_exec());


--
-- Name: user_sites user_sites_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_select ON public.user_sites FOR SELECT USING (((user_id = auth.uid()) OR public.is_maintenance_exec()));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: vehicle_sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.vehicle_sites ENABLE ROW LEVEL SECURITY;

--
-- Name: vehicles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

--
-- Name: workshop_locations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.workshop_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: supabase_realtime_admin
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: supabase_storage_admin
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: postgres
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION supabase_realtime OWNER TO postgres;

--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA auth TO dashboard_user;
GRANT USAGE ON SCHEMA auth TO postgres;


--
-- Name: SCHEMA cron; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA cron TO postgres WITH GRANT OPTION;


--
-- Name: SCHEMA extensions; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA extensions TO anon;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA extensions TO service_role;
GRANT ALL ON SCHEMA extensions TO dashboard_user;


--
-- Name: SCHEMA net; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA net TO supabase_functions_admin;
GRANT USAGE ON SCHEMA net TO postgres;
GRANT USAGE ON SCHEMA net TO anon;
GRANT USAGE ON SCHEMA net TO authenticated;
GRANT USAGE ON SCHEMA net TO service_role;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA realtime; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA realtime TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA realtime TO anon;
GRANT USAGE ON SCHEMA realtime TO authenticated;
GRANT USAGE ON SCHEMA realtime TO service_role;
GRANT ALL ON SCHEMA realtime TO supabase_realtime_admin;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA storage TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON SCHEMA storage TO dashboard_user;


--
-- Name: SCHEMA vault; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;
GRANT USAGE ON SCHEMA vault TO service_role;


--
-- Name: FUNCTION email(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.email() TO dashboard_user;


--
-- Name: FUNCTION jwt(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.jwt() TO postgres;
GRANT ALL ON FUNCTION auth.jwt() TO dashboard_user;


--
-- Name: FUNCTION role(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.role() TO dashboard_user;


--
-- Name: FUNCTION uid(); Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON FUNCTION auth.uid() TO dashboard_user;


--
-- Name: FUNCTION alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION job_cache_invalidate(); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.job_cache_invalidate() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(job_name text, schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(job_name text, schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_id bigint); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_id bigint) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_name text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_name text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION armor(bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.armor(bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.armor(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea) TO dashboard_user;


--
-- Name: FUNCTION armor(bytea, text[], text[]); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.armor(bytea, text[], text[]) FROM postgres;
GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.armor(bytea, text[], text[]) TO dashboard_user;


--
-- Name: FUNCTION crypt(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.crypt(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.crypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.crypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION dearmor(text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.dearmor(text) FROM postgres;
GRANT ALL ON FUNCTION extensions.dearmor(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.dearmor(text) TO dashboard_user;


--
-- Name: FUNCTION decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION decrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.digest(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION digest(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.digest(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.digest(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.digest(text, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION encrypt_iv(bytea, bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION gen_random_bytes(integer); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_random_bytes(integer) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_bytes(integer) TO dashboard_user;


--
-- Name: FUNCTION gen_random_uuid(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_random_uuid() FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_random_uuid() TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_salt(text) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_salt(text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text) TO dashboard_user;


--
-- Name: FUNCTION gen_salt(text, integer); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.gen_salt(text, integer) FROM postgres;
GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.gen_salt(text, integer) TO dashboard_user;


--
-- Name: FUNCTION grant_pg_cron_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_cron_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_cron_access() TO dashboard_user;


--
-- Name: FUNCTION grant_pg_graphql_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.grant_pg_graphql_access() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION grant_pg_net_access(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION extensions.grant_pg_net_access() FROM supabase_admin;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO supabase_admin WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.grant_pg_net_access() TO dashboard_user;


--
-- Name: FUNCTION hmac(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.hmac(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION hmac(text, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.hmac(text, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.hmac(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone) TO dashboard_user;


--
-- Name: FUNCTION pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) FROM postgres;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) TO dashboard_user;


--
-- Name: FUNCTION pgp_armor_headers(text, OUT key text, OUT value text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text) TO dashboard_user;


--
-- Name: FUNCTION pgp_key_id(bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_key_id(bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_key_id(bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_decrypt_bytea(bytea, bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt(text, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt(text, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea) TO dashboard_user;


--
-- Name: FUNCTION pgp_pub_encrypt_bytea(bytea, bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_decrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt(text, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt(text, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text) TO dashboard_user;


--
-- Name: FUNCTION pgp_sym_encrypt_bytea(bytea, text, text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) FROM postgres;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text) TO dashboard_user;


--
-- Name: FUNCTION pgrst_ddl_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_ddl_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION pgrst_drop_watch(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.pgrst_drop_watch() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION set_graphql_placeholder(); Type: ACL; Schema: extensions; Owner: supabase_admin
--

GRANT ALL ON FUNCTION extensions.set_graphql_placeholder() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION uuid_generate_v1(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v1() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v1mc(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v1mc() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v1mc() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v3(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v3(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v4(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v4() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v4() TO dashboard_user;


--
-- Name: FUNCTION uuid_generate_v5(namespace uuid, name text); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_generate_v5(namespace uuid, name text) TO dashboard_user;


--
-- Name: FUNCTION uuid_nil(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_nil() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_nil() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_nil() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_dns(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_dns() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_dns() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_oid(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_oid() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_oid() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_url(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_url() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_url() TO dashboard_user;


--
-- Name: FUNCTION uuid_ns_x500(); Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON FUNCTION extensions.uuid_ns_x500() FROM postgres;
GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION extensions.uuid_ns_x500() TO dashboard_user;


--
-- Name: FUNCTION graphql("operationName" text, query text, variables jsonb, extensions jsonb); Type: ACL; Schema: graphql_public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO postgres;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO anon;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO authenticated;
GRANT ALL ON FUNCTION graphql_public.graphql("operationName" text, query text, variables jsonb, extensions jsonb) TO service_role;


--
-- Name: FUNCTION pg_reload_conf(); Type: ACL; Schema: pg_catalog; Owner: supabase_admin
--

GRANT ALL ON FUNCTION pg_catalog.pg_reload_conf() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION get_auth(p_usename text); Type: ACL; Schema: pgbouncer; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION pgbouncer.get_auth(p_usename text) FROM PUBLIC;
GRANT ALL ON FUNCTION pgbouncer.get_auth(p_usename text) TO pgbouncer;


--
-- Name: FUNCTION acceptance_deadline(p_created_at timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.acceptance_deadline(p_created_at timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.acceptance_deadline(p_created_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.acceptance_deadline(p_created_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION add_part_to_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_part_to_inventory() TO anon;
GRANT ALL ON FUNCTION public.add_part_to_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.add_part_to_inventory() TO service_role;


--
-- Name: FUNCTION add_working_days(start_ts timestamp with time zone, n_days integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer) TO anon;
GRANT ALL ON FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer) TO authenticated;
GRANT ALL ON FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer) TO service_role;


--
-- Name: FUNCTION adjust_part_inventory_on_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO anon;
GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO authenticated;
GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO service_role;


--
-- Name: FUNCTION apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric) TO anon;
GRANT ALL ON FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric) TO authenticated;
GRANT ALL ON FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_delta numeric) TO service_role;


--
-- Name: FUNCTION calculate_issue_sla_dynamic(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO anon;
GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO service_role;


--
-- Name: FUNCTION calculate_ticket_overall_sla(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO anon;
GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO service_role;


--
-- Name: FUNCTION cancel_stock_audit(p_audit_id uuid, p_reason text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.cancel_stock_audit(p_audit_id uuid, p_reason text) TO anon;
GRANT ALL ON FUNCTION public.cancel_stock_audit(p_audit_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_stock_audit(p_audit_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION check_pan_exists(p_pan text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO anon;
GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO authenticated;
GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO service_role;


--
-- Name: FUNCTION close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO anon;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO service_role;


--
-- Name: FUNCTION close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean) TO anon;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean) TO authenticated;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean) TO service_role;


--
-- Name: FUNCTION complete_stock_audit(p_audit_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.complete_stock_audit(p_audit_id uuid) TO anon;
GRANT ALL ON FUNCTION public.complete_stock_audit(p_audit_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.complete_stock_audit(p_audit_id uuid) TO service_role;


--
-- Name: FUNCTION deduct_part_from_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO anon;
GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO service_role;


--
-- Name: FUNCTION delete_invoice_items_first(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.delete_invoice_items_first() TO anon;
GRANT ALL ON FUNCTION public.delete_invoice_items_first() TO authenticated;
GRANT ALL ON FUNCTION public.delete_invoice_items_first() TO service_role;


--
-- Name: FUNCTION delete_issue_part_with_scrap_check(p_issue_part_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO anon;
GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO service_role;


--
-- Name: FUNCTION evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO service_role;


--
-- Name: FUNCTION finalize_outsource_invoice(p_job_card_id uuid, p_remarks text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text) TO anon;
GRANT ALL ON FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text) TO authenticated;
GRANT ALL ON FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text) TO service_role;


--
-- Name: FUNCTION generate_issue_number(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.generate_issue_number() TO anon;
GRANT ALL ON FUNCTION public.generate_issue_number() TO authenticated;
GRANT ALL ON FUNCTION public.generate_issue_number() TO service_role;


--
-- Name: FUNCTION get_blocking_scrap_for_issue_part(p_issue_part_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO service_role;


--
-- Name: FUNCTION get_maintenance_stats(start_date_input date, end_date_input date, site_filter text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO anon;
GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO authenticated;
GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO service_role;


--
-- Name: FUNCTION get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO anon;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO authenticated;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO service_role;


--
-- Name: FUNCTION guard_job_card_location_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.guard_job_card_location_change() TO anon;
GRANT ALL ON FUNCTION public.guard_job_card_location_change() TO authenticated;
GRANT ALL ON FUNCTION public.guard_job_card_location_change() TO service_role;


--
-- Name: FUNCTION is_maintenance_exec(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.is_maintenance_exec() TO anon;
GRANT ALL ON FUNCTION public.is_maintenance_exec() TO authenticated;
GRANT ALL ON FUNCTION public.is_maintenance_exec() TO service_role;


--
-- Name: FUNCTION is_super_admin(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.is_super_admin() TO anon;
GRANT ALL ON FUNCTION public.is_super_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_super_admin() TO service_role;


--
-- Name: FUNCTION job_card_site_accessible_to_user(p_job_card_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO anon;
GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO service_role;


--
-- Name: FUNCTION move_invoice_stock_on_location_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.move_invoice_stock_on_location_change() TO anon;
GRANT ALL ON FUNCTION public.move_invoice_stock_on_location_change() TO authenticated;
GRANT ALL ON FUNCTION public.move_invoice_stock_on_location_change() TO service_role;


--
-- Name: FUNCTION recalculate_open_slas(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.recalculate_open_slas() TO anon;
GRANT ALL ON FUNCTION public.recalculate_open_slas() TO authenticated;
GRANT ALL ON FUNCTION public.recalculate_open_slas() TO service_role;


--
-- Name: FUNCTION recalculate_ticket_sla_on_status_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO anon;
GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO authenticated;
GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO service_role;


--
-- Name: FUNCTION record_scrap_disposal(p_header jsonb, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO service_role;


--
-- Name: FUNCTION record_scrap_writeoff(p_header jsonb, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO service_role;


--
-- Name: FUNCTION restore_part_to_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO anon;
GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO service_role;


--
-- Name: FUNCTION reverse_part_inventory_on_delete(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO anon;
GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO authenticated;
GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO service_role;


--
-- Name: FUNCTION seed_get_fk_deps(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.seed_get_fk_deps() TO anon;
GRANT ALL ON FUNCTION public.seed_get_fk_deps() TO authenticated;
GRANT ALL ON FUNCTION public.seed_get_fk_deps() TO service_role;


--
-- Name: FUNCTION seed_get_table_columns(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.seed_get_table_columns() TO anon;
GRANT ALL ON FUNCTION public.seed_get_table_columns() TO authenticated;
GRANT ALL ON FUNCTION public.seed_get_table_columns() TO service_role;


--
-- Name: FUNCTION seed_truncate_public_tables(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.seed_truncate_public_tables() TO anon;
GRANT ALL ON FUNCTION public.seed_truncate_public_tables() TO authenticated;
GRANT ALL ON FUNCTION public.seed_truncate_public_tables() TO service_role;


--
-- Name: FUNCTION set_scrap_location_from_job_card(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_scrap_location_from_job_card() TO anon;
GRANT ALL ON FUNCTION public.set_scrap_location_from_job_card() TO authenticated;
GRANT ALL ON FUNCTION public.set_scrap_location_from_job_card() TO service_role;


--
-- Name: FUNCTION set_stock_audit_reasons(p_audit_id uuid, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) TO anon;
GRANT ALL ON FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) TO service_role;


--
-- Name: FUNCTION set_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_updated_at() TO anon;
GRANT ALL ON FUNCTION public.set_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.set_updated_at() TO service_role;


--
-- Name: FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO anon;
GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO authenticated;
GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO service_role;


--
-- Name: FUNCTION start_stock_audit(p_location_id uuid, p_notes text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text) TO anon;
GRANT ALL ON FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text) TO service_role;


--
-- Name: FUNCTION stock_audit_movements(p_audit_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.stock_audit_movements(p_audit_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.stock_audit_movements(p_audit_id uuid) TO service_role;


--
-- Name: FUNCTION submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) TO anon;
GRANT ALL ON FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) TO service_role;


--
-- Name: FUNCTION sync_part_total_stock(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.sync_part_total_stock() TO anon;
GRANT ALL ON FUNCTION public.sync_part_total_stock() TO authenticated;
GRANT ALL ON FUNCTION public.sync_part_total_stock() TO service_role;


--
-- Name: FUNCTION transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text) TO anon;
GRANT ALL ON FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text) TO service_role;


--
-- Name: FUNCTION trg_recalculate_open_slas(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_recalculate_open_slas() TO anon;
GRANT ALL ON FUNCTION public.trg_recalculate_open_slas() TO authenticated;
GRANT ALL ON FUNCTION public.trg_recalculate_open_slas() TO service_role;


--
-- Name: FUNCTION trg_set_acceptance_sla_on_first_issue(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO anon;
GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO authenticated;
GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO service_role;


--
-- Name: FUNCTION trg_stamp_acceptance_deadline(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_stamp_acceptance_deadline() TO anon;
GRANT ALL ON FUNCTION public.trg_stamp_acceptance_deadline() TO authenticated;
GRANT ALL ON FUNCTION public.trg_stamp_acceptance_deadline() TO service_role;


--
-- Name: FUNCTION update_ticket_status_on_issue_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO anon;
GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO authenticated;
GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO service_role;


--
-- Name: FUNCTION apply_rls(wal jsonb, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO anon;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO authenticated;
GRANT ALL ON FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer) TO service_role;


--
-- Name: FUNCTION broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO postgres;
GRANT ALL ON FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) TO dashboard_user;


--
-- Name: FUNCTION build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO postgres;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO anon;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) TO service_role;


--
-- Name: FUNCTION "cast"(val text, type_ regtype); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO postgres;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO dashboard_user;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO anon;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO authenticated;
GRANT ALL ON FUNCTION realtime."cast"(val text, type_ regtype) TO service_role;


--
-- Name: FUNCTION check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO postgres;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO anon;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO authenticated;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) TO service_role;


--
-- Name: FUNCTION check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) TO postgres;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) TO anon;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) TO authenticated;
GRANT ALL ON FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) TO service_role;


--
-- Name: FUNCTION is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO postgres;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO anon;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO authenticated;
GRANT ALL ON FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) TO service_role;


--
-- Name: FUNCTION list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO postgres;
GRANT ALL ON FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) TO dashboard_user;


--
-- Name: FUNCTION quote_wal2json(entity regclass); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO postgres;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO anon;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO authenticated;
GRANT ALL ON FUNCTION realtime.quote_wal2json(entity regclass) TO service_role;


--
-- Name: FUNCTION send(payload jsonb, event text, topic text, private boolean); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO postgres;
GRANT ALL ON FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean) TO dashboard_user;


--
-- Name: FUNCTION send_binary(payload bytea, event text, topic text, private boolean); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean) TO postgres;
GRANT ALL ON FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean) TO dashboard_user;


--
-- Name: FUNCTION subscription_check_filters(); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO postgres;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO dashboard_user;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO anon;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO authenticated;
GRANT ALL ON FUNCTION realtime.subscription_check_filters() TO service_role;


--
-- Name: FUNCTION to_regrole(role_name text); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO postgres;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO dashboard_user;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO anon;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO authenticated;
GRANT ALL ON FUNCTION realtime.to_regrole(role_name text) TO service_role;


--
-- Name: FUNCTION topic(); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.topic() TO postgres;
GRANT ALL ON FUNCTION realtime.topic() TO dashboard_user;


--
-- Name: FUNCTION wal2json_escape_identifier(name text); Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON FUNCTION realtime.wal2json_escape_identifier(name text) TO postgres;
GRANT ALL ON FUNCTION realtime.wal2json_escape_identifier(name text) TO dashboard_user;


--
-- Name: FUNCTION _crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) TO service_role;


--
-- Name: FUNCTION create_secret(new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: FUNCTION update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid); Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO postgres WITH GRANT OPTION;
GRANT ALL ON FUNCTION vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) TO service_role;


--
-- Name: TABLE audit_log_entries; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.audit_log_entries TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.audit_log_entries TO postgres;
GRANT SELECT ON TABLE auth.audit_log_entries TO postgres WITH GRANT OPTION;


--
-- Name: TABLE custom_oauth_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.custom_oauth_providers TO postgres;
GRANT ALL ON TABLE auth.custom_oauth_providers TO dashboard_user;


--
-- Name: TABLE flow_state; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.flow_state TO postgres;
GRANT SELECT ON TABLE auth.flow_state TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.flow_state TO dashboard_user;


--
-- Name: TABLE identities; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.identities TO postgres;
GRANT SELECT ON TABLE auth.identities TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.identities TO dashboard_user;


--
-- Name: TABLE instances; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.instances TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.instances TO postgres;
GRANT SELECT ON TABLE auth.instances TO postgres WITH GRANT OPTION;


--
-- Name: TABLE mfa_amr_claims; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_amr_claims TO postgres;
GRANT SELECT ON TABLE auth.mfa_amr_claims TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_amr_claims TO dashboard_user;


--
-- Name: TABLE mfa_challenges; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_challenges TO postgres;
GRANT SELECT ON TABLE auth.mfa_challenges TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_challenges TO dashboard_user;


--
-- Name: TABLE mfa_factors; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.mfa_factors TO postgres;
GRANT SELECT ON TABLE auth.mfa_factors TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.mfa_factors TO dashboard_user;


--
-- Name: TABLE oauth_authorizations; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_authorizations TO postgres;
GRANT ALL ON TABLE auth.oauth_authorizations TO dashboard_user;


--
-- Name: TABLE oauth_client_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_client_states TO postgres;
GRANT ALL ON TABLE auth.oauth_client_states TO dashboard_user;


--
-- Name: TABLE oauth_clients; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_clients TO postgres;
GRANT ALL ON TABLE auth.oauth_clients TO dashboard_user;


--
-- Name: TABLE oauth_consents; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.oauth_consents TO postgres;
GRANT ALL ON TABLE auth.oauth_consents TO dashboard_user;


--
-- Name: TABLE one_time_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.one_time_tokens TO postgres;
GRANT SELECT ON TABLE auth.one_time_tokens TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.one_time_tokens TO dashboard_user;


--
-- Name: TABLE refresh_tokens; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.refresh_tokens TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.refresh_tokens TO postgres;
GRANT SELECT ON TABLE auth.refresh_tokens TO postgres WITH GRANT OPTION;


--
-- Name: SEQUENCE refresh_tokens_id_seq; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO dashboard_user;
GRANT ALL ON SEQUENCE auth.refresh_tokens_id_seq TO postgres;


--
-- Name: TABLE saml_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_providers TO postgres;
GRANT SELECT ON TABLE auth.saml_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_providers TO dashboard_user;


--
-- Name: TABLE saml_relay_states; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.saml_relay_states TO postgres;
GRANT SELECT ON TABLE auth.saml_relay_states TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.saml_relay_states TO dashboard_user;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT SELECT ON TABLE auth.schema_migrations TO postgres WITH GRANT OPTION;


--
-- Name: TABLE sessions; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sessions TO postgres;
GRANT SELECT ON TABLE auth.sessions TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sessions TO dashboard_user;


--
-- Name: TABLE sso_domains; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_domains TO postgres;
GRANT SELECT ON TABLE auth.sso_domains TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_domains TO dashboard_user;


--
-- Name: TABLE sso_providers; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.sso_providers TO postgres;
GRANT SELECT ON TABLE auth.sso_providers TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE auth.sso_providers TO dashboard_user;


--
-- Name: TABLE users; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.users TO dashboard_user;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE auth.users TO postgres;
GRANT SELECT ON TABLE auth.users TO postgres WITH GRANT OPTION;


--
-- Name: TABLE webauthn_challenges; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.webauthn_challenges TO postgres;
GRANT ALL ON TABLE auth.webauthn_challenges TO dashboard_user;


--
-- Name: TABLE webauthn_credentials; Type: ACL; Schema: auth; Owner: supabase_auth_admin
--

GRANT ALL ON TABLE auth.webauthn_credentials TO postgres;
GRANT ALL ON TABLE auth.webauthn_credentials TO dashboard_user;


--
-- Name: TABLE job; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT SELECT ON TABLE cron.job TO postgres WITH GRANT OPTION;


--
-- Name: TABLE job_run_details; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON TABLE cron.job_run_details TO postgres WITH GRANT OPTION;


--
-- Name: TABLE pg_stat_statements; Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON TABLE extensions.pg_stat_statements FROM postgres;
GRANT ALL ON TABLE extensions.pg_stat_statements TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements TO dashboard_user;


--
-- Name: TABLE pg_stat_statements_info; Type: ACL; Schema: extensions; Owner: postgres
--

REVOKE ALL ON TABLE extensions.pg_stat_statements_info FROM postgres;
GRANT ALL ON TABLE extensions.pg_stat_statements_info TO postgres WITH GRANT OPTION;
GRANT ALL ON TABLE extensions.pg_stat_statements_info TO dashboard_user;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.audit_logs TO anon;
GRANT ALL ON TABLE public.audit_logs TO authenticated;
GRANT ALL ON TABLE public.audit_logs TO service_role;


--
-- Name: TABLE finance_entries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.finance_entries TO anon;
GRANT ALL ON TABLE public.finance_entries TO authenticated;
GRANT ALL ON TABLE public.finance_entries TO service_role;


--
-- Name: TABLE holidays; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.holidays TO anon;
GRANT ALL ON TABLE public.holidays TO authenticated;
GRANT ALL ON TABLE public.holidays TO service_role;


--
-- Name: TABLE issue_parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.issue_parts TO anon;
GRANT ALL ON TABLE public.issue_parts TO authenticated;
GRANT ALL ON TABLE public.issue_parts TO service_role;


--
-- Name: TABLE issues; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.issues TO anon;
GRANT ALL ON TABLE public.issues TO authenticated;
GRANT ALL ON TABLE public.issues TO service_role;


--
-- Name: TABLE job_cards; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.job_cards TO anon;
GRANT ALL ON TABLE public.job_cards TO authenticated;
GRANT ALL ON TABLE public.job_cards TO service_role;


--
-- Name: SEQUENCE job_cards_job_card_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO anon;
GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO service_role;


--
-- Name: TABLE tickets; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tickets TO anon;
GRANT ALL ON TABLE public.tickets TO authenticated;
GRANT ALL ON TABLE public.tickets TO service_role;


--
-- Name: TABLE maintenance_dashboard_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.maintenance_dashboard_stats TO anon;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO authenticated;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO service_role;


--
-- Name: TABLE outsource_invoice_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.outsource_invoice_payments TO anon;
GRANT ALL ON TABLE public.outsource_invoice_payments TO authenticated;
GRANT ALL ON TABLE public.outsource_invoice_payments TO service_role;


--
-- Name: TABLE outsource_invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.outsource_invoices TO anon;
GRANT ALL ON TABLE public.outsource_invoices TO authenticated;
GRANT ALL ON TABLE public.outsource_invoices TO service_role;


--
-- Name: TABLE part_stock; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.part_stock TO anon;
GRANT ALL ON TABLE public.part_stock TO authenticated;
GRANT ALL ON TABLE public.part_stock TO service_role;


--
-- Name: TABLE part_units; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.part_units TO anon;
GRANT ALL ON TABLE public.part_units TO authenticated;
GRANT ALL ON TABLE public.part_units TO service_role;


--
-- Name: TABLE parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.parts TO anon;
GRANT ALL ON TABLE public.parts TO authenticated;
GRANT ALL ON TABLE public.parts TO service_role;


--
-- Name: TABLE purchase_invoice_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_invoice_items TO anon;
GRANT ALL ON TABLE public.purchase_invoice_items TO authenticated;
GRANT ALL ON TABLE public.purchase_invoice_items TO service_role;


--
-- Name: TABLE purchase_invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_invoices TO anon;
GRANT ALL ON TABLE public.purchase_invoices TO authenticated;
GRANT ALL ON TABLE public.purchase_invoices TO service_role;


--
-- Name: TABLE scrap_disposal; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_disposal TO anon;
GRANT ALL ON TABLE public.scrap_disposal TO authenticated;
GRANT ALL ON TABLE public.scrap_disposal TO service_role;


--
-- Name: TABLE scrap_disposal_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_disposal_items TO anon;
GRANT ALL ON TABLE public.scrap_disposal_items TO authenticated;
GRANT ALL ON TABLE public.scrap_disposal_items TO service_role;


--
-- Name: TABLE scrap_excluded_parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_excluded_parts TO anon;
GRANT ALL ON TABLE public.scrap_excluded_parts TO authenticated;
GRANT ALL ON TABLE public.scrap_excluded_parts TO service_role;


--
-- Name: TABLE scrap_inventory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_inventory TO anon;
GRANT ALL ON TABLE public.scrap_inventory TO authenticated;
GRANT ALL ON TABLE public.scrap_inventory TO service_role;


--
-- Name: TABLE scrap_writeoff; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_writeoff TO anon;
GRANT ALL ON TABLE public.scrap_writeoff TO authenticated;
GRANT ALL ON TABLE public.scrap_writeoff TO service_role;


--
-- Name: TABLE scrap_writeoff_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_writeoff_items TO anon;
GRANT ALL ON TABLE public.scrap_writeoff_items TO authenticated;
GRANT ALL ON TABLE public.scrap_writeoff_items TO service_role;


--
-- Name: TABLE sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sites TO anon;
GRANT ALL ON TABLE public.sites TO authenticated;
GRANT ALL ON TABLE public.sites TO service_role;


--
-- Name: TABLE sla_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sla_events TO anon;
GRANT ALL ON TABLE public.sla_events TO authenticated;
GRANT ALL ON TABLE public.sla_events TO service_role;


--
-- Name: TABLE sla_rules_config; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE public.sla_rules_config TO anon;
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE public.sla_rules_config TO authenticated;
GRANT ALL ON TABLE public.sla_rules_config TO service_role;


--
-- Name: TABLE stock_audit_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stock_audit_items TO anon;
GRANT ALL ON TABLE public.stock_audit_items TO authenticated;
GRANT ALL ON TABLE public.stock_audit_items TO service_role;


--
-- Name: TABLE stock_audits; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stock_audits TO anon;
GRANT ALL ON TABLE public.stock_audits TO authenticated;
GRANT ALL ON TABLE public.stock_audits TO service_role;


--
-- Name: SEQUENCE stock_audits_audit_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stock_audits_audit_number_seq TO anon;
GRANT ALL ON SEQUENCE public.stock_audits_audit_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.stock_audits_audit_number_seq TO service_role;


--
-- Name: TABLE stock_transfer_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stock_transfer_items TO anon;
GRANT ALL ON TABLE public.stock_transfer_items TO authenticated;
GRANT ALL ON TABLE public.stock_transfer_items TO service_role;


--
-- Name: TABLE stock_transfers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stock_transfers TO anon;
GRANT ALL ON TABLE public.stock_transfers TO authenticated;
GRANT ALL ON TABLE public.stock_transfers TO service_role;


--
-- Name: TABLE supervisor_dashboard_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.supervisor_dashboard_stats TO anon;
GRANT ALL ON TABLE public.supervisor_dashboard_stats TO authenticated;
GRANT ALL ON TABLE public.supervisor_dashboard_stats TO service_role;


--
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO anon;
GRANT ALL ON TABLE public.suppliers TO authenticated;
GRANT ALL ON TABLE public.suppliers TO service_role;


--
-- Name: TABLE system_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.system_settings TO anon;
GRANT ALL ON TABLE public.system_settings TO authenticated;
GRANT ALL ON TABLE public.system_settings TO service_role;


--
-- Name: SEQUENCE tickets_ticket_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO anon;
GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO service_role;


--
-- Name: TABLE user_audit_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_audit_logs TO anon;
GRANT ALL ON TABLE public.user_audit_logs TO authenticated;
GRANT ALL ON TABLE public.user_audit_logs TO service_role;


--
-- Name: TABLE user_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_settings TO anon;
GRANT ALL ON TABLE public.user_settings TO authenticated;
GRANT ALL ON TABLE public.user_settings TO service_role;


--
-- Name: TABLE user_sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_sites TO anon;
GRANT ALL ON TABLE public.user_sites TO authenticated;
GRANT ALL ON TABLE public.user_sites TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: TABLE vehicle_sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vehicle_sites TO anon;
GRANT ALL ON TABLE public.vehicle_sites TO authenticated;
GRANT ALL ON TABLE public.vehicle_sites TO service_role;


--
-- Name: TABLE vehicles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vehicles TO anon;
GRANT ALL ON TABLE public.vehicles TO authenticated;
GRANT ALL ON TABLE public.vehicles TO service_role;


--
-- Name: TABLE workshop_locations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.workshop_locations TO anon;
GRANT ALL ON TABLE public.workshop_locations TO authenticated;
GRANT ALL ON TABLE public.workshop_locations TO service_role;


--
-- Name: TABLE messages; Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON TABLE realtime.messages TO postgres;
GRANT ALL ON TABLE realtime.messages TO dashboard_user;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE realtime.messages TO service_role;


--
-- Name: TABLE subscription; Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON TABLE realtime.subscription TO postgres;
GRANT ALL ON TABLE realtime.subscription TO dashboard_user;
GRANT SELECT ON TABLE realtime.subscription TO anon;
GRANT SELECT ON TABLE realtime.subscription TO authenticated;
GRANT SELECT ON TABLE realtime.subscription TO service_role;


--
-- Name: SEQUENCE subscription_id_seq; Type: ACL; Schema: realtime; Owner: supabase_realtime_admin
--

GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO postgres;
GRANT ALL ON SEQUENCE realtime.subscription_id_seq TO dashboard_user;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO anon;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE realtime.subscription_id_seq TO service_role;


--
-- Name: TABLE buckets; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.buckets FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.buckets TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.buckets TO service_role;
GRANT ALL ON TABLE storage.buckets TO authenticated;
GRANT ALL ON TABLE storage.buckets TO anon;
GRANT ALL ON TABLE storage.buckets TO postgres WITH GRANT OPTION;


--
-- Name: TABLE buckets_analytics; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.buckets_analytics TO service_role;
GRANT ALL ON TABLE storage.buckets_analytics TO authenticated;
GRANT ALL ON TABLE storage.buckets_analytics TO anon;


--
-- Name: TABLE buckets_vectors; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.buckets_vectors TO service_role;
GRANT SELECT ON TABLE storage.buckets_vectors TO authenticated;
GRANT SELECT ON TABLE storage.buckets_vectors TO anon;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

REVOKE ALL ON TABLE storage.objects FROM supabase_storage_admin;
GRANT ALL ON TABLE storage.objects TO supabase_storage_admin WITH GRANT OPTION;
GRANT ALL ON TABLE storage.objects TO service_role;
GRANT ALL ON TABLE storage.objects TO authenticated;
GRANT ALL ON TABLE storage.objects TO anon;
GRANT ALL ON TABLE storage.objects TO postgres WITH GRANT OPTION;


--
-- Name: TABLE s3_multipart_uploads; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads TO anon;


--
-- Name: TABLE s3_multipart_uploads_parts; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT ALL ON TABLE storage.s3_multipart_uploads_parts TO service_role;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO authenticated;
GRANT SELECT ON TABLE storage.s3_multipart_uploads_parts TO anon;


--
-- Name: TABLE vector_indexes; Type: ACL; Schema: storage; Owner: supabase_storage_admin
--

GRANT SELECT ON TABLE storage.vector_indexes TO service_role;
GRANT SELECT ON TABLE storage.vector_indexes TO authenticated;
GRANT SELECT ON TABLE storage.vector_indexes TO anon;


--
-- Name: TABLE secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.secrets TO service_role;


--
-- Name: TABLE decrypted_secrets; Type: ACL; Schema: vault; Owner: supabase_admin
--

GRANT SELECT,REFERENCES,DELETE,TRUNCATE ON TABLE vault.decrypted_secrets TO postgres WITH GRANT OPTION;
GRANT SELECT,DELETE ON TABLE vault.decrypted_secrets TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: auth; Owner: supabase_auth_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: extensions; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: graphql_public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA graphql_public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON SEQUENCES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON FUNCTIONS TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: realtime; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA realtime GRANT ALL ON TABLES TO dashboard_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: storage; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT ALL ON TABLES TO service_role;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


ALTER EVENT TRIGGER issue_graphql_placeholder OWNER TO supabase_admin;

--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


ALTER EVENT TRIGGER issue_pg_cron_access OWNER TO supabase_admin;

--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


ALTER EVENT TRIGGER issue_pg_graphql_access OWNER TO supabase_admin;

--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


ALTER EVENT TRIGGER issue_pg_net_access OWNER TO supabase_admin;

--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


ALTER EVENT TRIGGER pgrst_ddl_watch OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


ALTER EVENT TRIGGER pgrst_drop_watch OWNER TO supabase_admin;

--
-- PostgreSQL database dump complete
--


