-- MAIN-127: SECURITY DEFINER functions were executable by PUBLIC, anon and
-- authenticated, so anyone holding the public key could run them signed out.
-- Each function carried separate grants to PUBLIC, anon and authenticated, so
-- all three are revoked by name.

-- Seed helpers: only seed-staging-from-prod calls them, through the service role.
REVOKE EXECUTE ON FUNCTION public.seed_truncate_public_tables() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_get_table_columns()      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_get_fk_deps()            FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.seed_truncate_public_tables(),
                           public.seed_get_table_columns(),
                           public.seed_get_fk_deps() TO service_role;

-- Every caller (the stock triggers, transfer_stock, complete_stock_audit) is
-- SECURITY DEFINER owned by postgres, so the nested call is checked against
-- postgres, not the signed-in user. The app never calls it directly.
REVOKE EXECUTE ON FUNCTION public.apply_part_stock_delta(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;

-- The Outsource Invoices page calls it signed in; authenticated keeps its own grant.
REVOKE EXECUTE ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[]) FROM PUBLIC, anon;

-- check_pan_exists stays open: /supplier-registration calls it signed out.
