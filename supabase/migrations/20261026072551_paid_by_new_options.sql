-- MAIN-89: accounts needs two more "Paid By" options on outsource invoices —
-- Gokilavannan, and NVS Maintenance account (a different account from "Accounts").
--
-- Mirrors PAID_BY_OPTIONS in src/constants/outsourceInvoices.js — keep in step.
-- Existing rows all hold one of the original three values, so the new constraint
-- validates without touching data.

alter table public.outsource_invoices
  drop constraint outsource_invoices_paid_by_check;

alter table public.outsource_invoices
  add constraint outsource_invoices_paid_by_check
  check (paid_by = any (array[
    'Accounts'::text,
    'Nithin'::text,
    'Manjunath'::text,
    'Gokilavannan'::text,
    'NVS Maintenance account'::text
  ]));
