-- Allow mechanics to view issues linked to their assigned job cards
CREATE POLICY "Mechanics view issues on assigned cards" ON issues
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM job_cards
            WHERE job_cards.id = issues.job_card_id
            AND job_cards.assigned_mechanic_id = auth.uid()
        )
    );
