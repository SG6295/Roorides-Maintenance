-- MAIN-139: the prod→staging seed copies rows exactly as prod has them.
--
-- The seed used to insert through PostgREST, so every trigger re-derived data as if the
-- rows were new work (stock added twice, issue_parts refused for "not enough stock",
-- acceptance re-judged) and every GENERATED ALWAYS identity was renumbered. Rows now go
-- through seed_insert_rows, which inserts them with triggers off and identities kept.
--
-- These functions land on prod too. Each one that writes refuses to run unless the
-- database carries the staging marker: a Vault secret named seed_target_environment
-- whose value is 'staging'. Vault is per project and the seed never copies it, so prod
-- (which has no such secret) fails closed. Create it once on staging with
--   select vault.create_secret('staging', 'seed_target_environment', 'MAIN-139 seed guard');

CREATE OR REPLACE FUNCTION public.seed_assert_staging()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vault.decrypted_secrets
    WHERE name = 'seed_target_environment' AND decrypted_secret = 'staging'
  ) THEN
    RAISE EXCEPTION 'NOT_STAGING: this database is not marked as staging; the seed refuses to run'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

-- Empties every public table and restarts its identity sequences, so a table that is
-- empty in prod (e.g. batch_services) numbers from 1 again.
CREATE OR REPLACE FUNCTION public.seed_truncate_public_tables()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  tbl text;
BEGIN
  PERFORM public.seed_assert_staging();

  FOR tbl IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE', tbl);
  END LOOP;
END;
$$;

-- Primary key columns per public table, so the seed can page prod reads in a stable order.
CREATE OR REPLACE FUNCTION public.seed_get_primary_keys()
RETURNS TABLE(table_name text, column_name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.relname::text, a.attname::text
  FROM pg_catalog.pg_constraint k
  JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL unnest(k.conkey) WITH ORDINALITY AS u(attnum, ord)
  JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = u.attnum
  WHERE n.nspname = 'public' AND k.contype = 'p'
  ORDER BY c.relname, u.ord;
$$;

-- Inserts one batch of prod rows into a staging table as given:
--   * session_replication_role = replica for this transaction only, so no user trigger
--     fires (and, as a consequence, no FK is checked — the seed still copies in FK order);
--   * OVERRIDING SYSTEM VALUE, so job_card_number, ticket_number, batch_number,
--     purchase_number and supplier_number keep prod's values;
--   * stored generated columns are left out — their inputs are copied and staging
--     recomputes them;
--   * keys that staging doesn't have are ignored, and staging-only columns get their default.
-- Afterwards each identity sequence on the table is moved to the highest copied value,
-- so the next record created on staging continues from prod's number.
CREATE OR REPLACE FUNCTION public.seed_insert_rows(p_table text, p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_rel regclass;
  v_cols text;
  v_count integer;
  v_ident record;
BEGIN
  PERFORM public.seed_assert_staging();

  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'seed_insert_rows: p_rows must be a jsonb array';
  END IF;
  IF jsonb_array_length(p_rows) = 0 THEN
    RETURN 0;
  END IF;

  SELECT c.oid INTO v_rel
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = p_table AND c.relkind = 'r';
  IF v_rel IS NULL THEN
    RAISE EXCEPTION 'seed_insert_rows: no public table named %', p_table;
  END IF;

  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) INTO v_cols
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = v_rel
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND a.attgenerated = ''
    AND p_rows -> 0 ? a.attname;

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'seed_insert_rows: no matching columns for %', p_table;
  END IF;

  SET LOCAL session_replication_role = replica;

  EXECUTE format(
    'INSERT INTO %s (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM jsonb_populate_recordset(NULL::%s, $1)',
    v_rel, v_cols, v_cols, v_rel
  ) USING p_rows;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  FOR v_ident IN
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = v_rel AND a.attidentity <> '' AND NOT a.attisdropped
  LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), max(%I)) FROM %s HAVING max(%I) IS NOT NULL',
      v_rel::text, v_ident.attname, v_ident.attname, v_rel, v_ident.attname
    );
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_assert_staging() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.seed_truncate_public_tables() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.seed_get_primary_keys() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.seed_insert_rows(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seed_assert_staging() TO service_role;
GRANT EXECUTE ON FUNCTION public.seed_truncate_public_tables() TO service_role;
GRANT EXECUTE ON FUNCTION public.seed_get_primary_keys() TO service_role;
GRANT EXECUTE ON FUNCTION public.seed_insert_rows(text, jsonb) TO service_role;
