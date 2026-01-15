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
