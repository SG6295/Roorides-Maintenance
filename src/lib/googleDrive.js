import { supabase } from './supabase';

/**
 * Uploads a single file to Google Drive via the upload-to-drive edge function
 * and returns its shareable link. Nothing is stored in Supabase Storage — the
 * database only ever holds the returned URL.
 *
 * The Authorization header is attached only when a session exists: the supplier
 * registration form is a public unauthenticated route, and the edge function
 * accepts anonymous uploads.
 */
export const uploadToDrive = async (file) => {
    const formData = new FormData();
    formData.append('file', file);

    const { data: { session } } = await supabase.auth.getSession();
    const headers = {};
    if (session?.access_token) {
        headers['Authorization'] = `Bearer ${session.access_token}`;
    }

    const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/upload-to-drive`,
        { method: 'POST', headers, body: formData }
    );

    if (!response.ok) {
        // Safe to surface: MAIN-62 stopped the function returning internal
        // error text, so what arrives here is either a deliberate validation
        // message or a generic one.
        const err = await response.json().catch(() => ({}));
        throw new Error(err.error || 'Upload failed. Please try again.');
    }

    const result = await response.json();
    return result.url;
};

export const getDriveFileId = (url) => {
    if (!url) return null;

    // Match /file/d/ID/view pattern
    const fileIdMatch = url.match(/\/file\/d\/([^/]+)/);
    if (fileIdMatch) return fileIdMatch[1];

    // Match id=ID parameter
    const idParamMatch = url.match(/[?&]id=([^&]+)/);
    if (idParamMatch) return idParamMatch[1];

    return null;
};

export const getDriveThumbnailUrl = (url) => {
    const fileId = getDriveFileId(url);
    if (!fileId) return null;

    // Use the export=view parameter which acts as a direct image link
    // This works better for <img src> tags than the view link
    return `https://drive.google.com/uc?export=view&id=${fileId}`;
};
