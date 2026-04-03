-- Allow mechanics to update issues linked to their assigned job cards
-- (needed for: labour hours, status changes via IssueWorkCard)
CREATE POLICY "Mechanics update issues on assigned cards" ON issues
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM job_cards
            WHERE job_cards.id = issues.job_card_id
            AND job_cards.assigned_mechanic_id = auth.uid()
        )
    );
