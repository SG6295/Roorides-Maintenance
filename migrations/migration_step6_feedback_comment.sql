-- Migration: Add feedback_comment column to issues table
-- Run this in Supabase SQL Editor

ALTER TABLE issues ADD COLUMN IF NOT EXISTS feedback_comment TEXT DEFAULT NULL;
