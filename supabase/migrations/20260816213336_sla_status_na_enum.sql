-- MAIN-45, part 1 of 4: add the NA verdict.
--
-- Decision 3 on the ticket: SLA deadlines computed before the timestamptz migration are
-- discarded rather than reinterpreted, and the tickets they belonged to keep no verdict.
-- Reporting must be able to say "no SLA data" instead of quietly reading as Adhered or
-- Pending, so the enum needs a value for it.
--
-- This is deliberately alone in its own migration: ALTER TYPE ... ADD VALUE commits the
-- new label, but Postgres refuses to let that label be *used* in the same transaction.
-- The backfill that uses it is part 4.

ALTER TYPE public.sla_status_enum ADD VALUE IF NOT EXISTS 'NA';
