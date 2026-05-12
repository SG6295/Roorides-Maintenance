-- ── Scrap Inventory Module — Phase 2 ─────────────────────────────────────────
-- Migration 1/5: Create enum types for disposal payment mode and write-off reason.

CREATE TYPE public.scrap_payment_mode AS ENUM (
    'cash',
    'upi',
    'bank_transfer',
    'cheque',
    'other'
);

CREATE TYPE public.scrap_writeoff_reason AS ENUM (
    'lost',
    'damaged_unsaleable',
    'hazmat_disposal',
    'stocktake_adjustment',
    'donated',
    'other'
);
