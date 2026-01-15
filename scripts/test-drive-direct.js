
import { promises as fs } from 'fs';
import path from 'path';

// Hardcoded Folder ID provided by user
const FOLDER_ID = '0ACqst8kJVkKPUk9PVA';
const CREDENTIALS_PATH = 'google-credentials/service-account.json';

async function testDirectUpload() {
    try {
        console.log('Reading local credentials...');
        const content = await fs.readFile(CREDENTIALS_PATH, 'utf-8');
        const credentials = JSON.parse(content);

        console.log('Using Service Account Email:', credentials.client_email);
        console.log('Target Folder ID:', FOLDER_ID);

        // Get Access Token
        const token = await getAccessToken(credentials.client_email, credentials.private_key);
        console.log('Got Access Token.');

        // Upload File
        const boundary = '-------314159265358979323846';
        const metadata = {
            name: 'direct-test-' + Date.now() + '.txt',
            parents: [FOLDER_ID],
            mimeType: 'text/plain'
        };

        const fileContent = 'Direct upload test content';

        const multipartBody =
            `--${boundary}\r\n` +
            `Content-Type: application/json; charset=UTF-8\r\n\r\n` +
            `${JSON.stringify(metadata)}\r\n` +
            `--${boundary}\r\n` +
            `Content-Type: text/plain\r\n\r\n` +
            `${fileContent}\r\n` +
            `--${boundary}--`;

        console.log('Attempting upload with supportsAllDrives=true...');
        const response = await fetch(
            'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',
            {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': `multipart/related; boundary=${boundary}`,
                },
                body: multipartBody
            }
        );

        if (!response.ok) {
            const errorText = await response.text();
            console.error('Upload Failed!');
            console.error('Status:', response.status);
            console.error('Body:', errorText);
        } else {
            const data = await response.json();
            console.log('Upload Success!');
            console.log('File ID:', data.id);
            console.log('Name:', data.name);
        }

    } catch (err) {
        if (err.code === 'ENOENT') {
            console.error('Could not find credentials file at:', CREDENTIALS_PATH);
        } else {
            console.error('Error:', err);
        }
    }
}

// Minimal JWT/Token Logic (same as Edge Function)
async function getAccessToken(email, privateKey) {
    const header = { alg: 'RS256', typ: 'JWT' };
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        iss: email,
        scope: 'https://www.googleapis.com/auth/drive.file',
        aud: 'https://oauth2.googleapis.com/token',
        exp: now + 3600,
        iat: now,
    };

    const encodedHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');

    const crypto = await import('crypto');
    const signer = crypto.createSign('RSA-SHA256');
    signer.update(`${encodedHeader}.${encodedPayload}`);
    const signature = signer.sign(privateKey, 'base64url');

    const jwt = `${encodedHeader}.${encodedPayload}.${signature}`;

    const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: jwt,
        }),
    });

    const data = await response.json();
    if (!data.access_token) throw new Error('Failed to get access token: ' + JSON.stringify(data));
    return data.access_token;
}

testDirectUpload();
