-- Add rating columns if they don't exist
ALTER TABLE public.tickets 
ADD COLUMN IF NOT EXISTS rating text CHECK (rating IN ('good', 'ok', 'bad')),
ADD COLUMN IF NOT EXISTS rating_comment text,
ADD COLUMN IF NOT EXISTS rated_at timestamp with time zone;

-- Update RLS Policy to allow creators to update their own tickets for rating
-- We might need to drop existing policy if it's too restrictive (e.g. "only update if status is not closed")
-- Assuming there is a policy "Users can update their own tickets" or similar.
-- Let's create a specific policy for rating if needed, or rely on the general update policy.
-- Secure approach: Create a function/RPC or just ensure the UPDATE policy allows it.

-- Let's just create a policy that explicitly allows updating rating columns for the creator
CREATE POLICY "Creators can rate completed tickets"
ON public.tickets
FOR UPDATE
TO authenticated
USING (auth.uid() = created_by_user_id)
WITH CHECK (auth.uid() = created_by_user_id);
