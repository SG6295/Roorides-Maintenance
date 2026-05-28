BEGIN;

-- Helper functions used by the seed-staging-from-prod edge function.
-- Safe to have in prod — they are never called from there.

-- Truncates all user-owned public tables in one shot (CASCADE handles FK order).
CREATE OR REPLACE FUNCTION public.seed_truncate_public_tables()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Returns column names for every real table in the public schema.
-- Excludes views (by joining pg_tables) and generated/computed columns.
CREATE OR REPLACE FUNCTION public.seed_get_table_columns()
RETURNS TABLE(table_name text, column_name text)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT c.table_name::text, c.column_name::text
  FROM information_schema.columns c
  JOIN pg_tables t ON t.schemaname = 'public' AND t.tablename = c.table_name
  WHERE c.table_schema = 'public'
    AND c.is_generated = 'NEVER'
    AND NOT (c.is_identity = 'YES' AND c.identity_generation = 'ALWAYS')
  ORDER BY c.table_name, c.ordinal_position;
$$;

-- Returns FK dependencies as (child_table, parent_table) pairs for public schema.
CREATE OR REPLACE FUNCTION public.seed_get_fk_deps()
RETURNS TABLE(child_table text, parent_table text)
LANGUAGE sql
SECURITY DEFINER
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

SELECT 'seed helper functions created' AS result;

ROLLBACK; -- change to COMMIT once output looks correct
