-- Migration: Add feedback_date column to issues table
-- Run this in Supabase SQL Editor

ALTER TABLE issues ADD COLUMN IF NOT EXISTS feedback_date TIMESTAMPTZ DEFAULT NULL;

-- Create index for efficient sorting
CREATE INDEX IF NOT EXISTS idx_issues_feedback_date ON issues(feedback_date DESC NULLS LAST);
