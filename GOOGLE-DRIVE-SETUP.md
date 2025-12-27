# Google Drive Photo Upload Setup

This guide explains how to deploy the Google Drive photo upload feature to Supabase.

## Prerequisites

1. **Supabase CLI installed**
   ```bash
   npm install -g supabase
   ```

2. **Google Service Account** (Already created)
   - Email: `nvs-maintenance-uploader@roorides-maintenance.iam.gserviceaccount.com`
   - Drive Folder ID: `1bgGuYGs2zdTTlTZdCD0_gwuSVsDxtr4U`
   - Private key JSON file: `./google-credentials/service-account.json`

## Step 1: Link Supabase Project

```bash
cd nvs-maintenance
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

To get your project ref:
1. Go to Supabase Dashboard → Project Settings → General
2. Copy the "Reference ID"

## Step 2: Set Environment Variables in Supabase

You need to add three secrets to your Supabase project:

### Method 1: Using Supabase Dashboard (Recommended)
1. Go to Supabase Dashboard → Project Settings → Edge Functions
2. Click "Manage secrets"
3. Add these three secrets:

```
GOOGLE_SERVICE_ACCOUNT_EMAIL=nvs-maintenance-uploader@roorides-maintenance.iam.gserviceaccount.com
GOOGLE_DRIVE_FOLDER_ID=1bgGuYGs2zdTTlTZdCD0_gwuSVsDxtr4U
GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY=<paste the private_key from service-account.json>
```

**Getting the private key:**
1. Open `google-credentials/service-account.json`
2. Find the `private_key` field
3. Copy the ENTIRE value including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`
4. Paste it as the value (keep the newlines - `\n` characters)

### Method 2: Using Supabase CLI

```bash
# Read the private key from your service account file
PRIVATE_KEY=$(cat google-credentials/service-account.json | jq -r .private_key)

# Set the secrets
supabase secrets set GOOGLE_SERVICE_ACCOUNT_EMAIL="nvs-maintenance-uploader@roorides-maintenance.iam.gserviceaccount.com"
supabase secrets set GOOGLE_DRIVE_FOLDER_ID="1bgGuYGs2zdTTlTZdCD0_gwuSVsDxtr4U"
supabase secrets set GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY="$PRIVATE_KEY"
```

## Step 3: Deploy the Edge Function

```bash
supabase functions deploy upload-to-drive
```

This will:
- Deploy the function to your Supabase project
- Make it available at: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/upload-to-drive`

## Step 4: Test the Function

You can test the deployment using curl:

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/upload-to-drive' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -F 'file=@/path/to/test-image.jpg'
```

Expected response:
```json
{
  "success": true,
  "fileId": "1abc...",
  "url": "https://drive.google.com/file/d/1abc.../view",
  "fileName": "1234567890-test-image.jpg"
}
```

## Step 5: Verify in Production

1. Go to your deployed app: https://roorides-maintenance.vercel.app/
2. Create a new ticket
3. Click "Camera" or "Gallery" button
4. Select/take a photo
5. Watch it upload automatically
6. Submit the ticket
7. View the ticket detail - photos should be visible as links

## Troubleshooting

### Error: "Missing Google Drive configuration"
- Make sure all three environment variables are set correctly in Supabase
- Verify the private key includes the full PEM format with BEGIN/END markers

### Error: "Failed to upload to Google Drive"
- Check that the service account has edit permissions on the Drive folder
- Verify the folder ID is correct
- Check the Supabase function logs: Dashboard → Edge Functions → upload-to-drive → Logs

### Error: "Upload failed"
- Check browser console for detailed error
- Verify VITE_SUPABASE_URL is set correctly in Vercel
- Ensure user is authenticated

### Photos not appearing
- Check that photos array is being saved to database
- Verify Google Drive links are shareable (anyone with link can view)
- Check browser console for CORS errors

## How It Works

1. **User takes/selects photo** → PhotoUpload component
2. **Photo is uploaded** → Supabase Edge Function (upload-to-drive)
3. **Edge Function:**
   - Authenticates with Google using service account
   - Uploads file to specified Google Drive folder
   - Makes file publicly accessible (anyone with link)
   - Returns shareable link
4. **Link is saved** → Stored in tickets.photos array in Supabase
5. **Link is displayed** → TicketDetail component shows clickable links

## Security Notes

- ✅ Service account credentials are stored as Supabase secrets (encrypted)
- ✅ Edge Function requires authentication (Supabase token)
- ✅ Files are uploaded to a dedicated folder with restricted access
- ✅ Files are made publicly accessible but links are not guessable
- ✅ google-credentials/ folder is gitignored (never committed)
- ✅ 10MB file size limit enforced
- ✅ Only image files accepted

## Files Structure

```
nvs-maintenance/
├── supabase/
│   └── functions/
│       └── upload-to-drive/
│           └── index.ts          # Edge Function code
├── src/
│   └── components/
│       └── tickets/
│           ├── PhotoUpload.jsx   # Photo upload component
│           └── TicketForm.jsx    # Uses PhotoUpload
├── google-credentials/           # Gitignored
│   └── service-account.json     # Service account private key
└── GOOGLE-DRIVE-SETUP.md        # This file
```

## Updating the Function

If you need to modify the upload logic:

1. Edit `supabase/functions/upload-to-drive/index.ts`
2. Redeploy:
   ```bash
   supabase functions deploy upload-to-drive
   ```
3. Changes are live immediately

## Cost Considerations

- **Supabase Edge Functions:** Free tier includes 500,000 invocations/month
- **Google Drive Storage:** Free tier includes 15GB
- Each photo upload = 1 Edge Function invocation
- Estimated: ~10,000 tickets/month × 2 photos avg = 20,000 invocations (well within free tier)
