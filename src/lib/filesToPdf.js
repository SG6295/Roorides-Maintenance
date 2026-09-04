/**
 * Combines several attached files into a single PDF, in the browser.
 *
 * A vendor bill spanning several photos used to be assembled on a free online
 * image-to-PDF site before being uploaded here, which sent commercial invoices —
 * and, on the public supplier form, other people's PAN cards and cancelled
 * cheques — through an unvetted third party. Doing it locally removes that.
 *
 * No React in this file, so the conversion can be reasoned about on its own.
 */

// The same list `upload-to-drive` accepts. Kept here so callers validate against
// one source rather than each repeating the array.
export const IMAGE_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp']
export const PDF_TYPE = 'application/pdf'
export const ACCEPTED_TYPES = [...IMAGE_TYPES, PDF_TYPE]

export const isImage = (file) => IMAGE_TYPES.includes(file.type)
export const isAccepted = (file) => ACCEPTED_TYPES.includes(file.type)

// Long edge to downscale photos to before embedding. A phone camera shot is
// 4000px+; at 1600 the text on an invoice stays legible while a five-page
// bundle lands in single-digit MB, well under the 50MB cap in upload-to-drive.
const MAX_EDGE = 1600
const JPEG_QUALITY = 0.7

/** Name for the assembled file: the first attachment's name, plus a suffix. */
export function combinedPdfName(files) {
    const first = files[0]?.name ?? 'invoice'
    const base = first.replace(/\.[^.]+$/, '')       // strip extension
        .replace(/[^\w\-. ]+/g, '')                  // Drive-safe characters only
        .trim()
        .slice(0, 60)
    return `${base || 'invoice'}-combined.pdf`
}

/**
 * Draws an image file onto a canvas at a bounded size and returns JPEG bytes.
 * Canvas is the only decoder available to us, so this doubles as the check that
 * the browser can actually read the file.
 */
async function imageToJpegBytes(file) {
    const bitmap = await createImageBitmap(file)
    const canvas = document.createElement('canvas')
    try {
        const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height))
        canvas.width = Math.max(1, Math.round(bitmap.width * scale))
        canvas.height = Math.max(1, Math.round(bitmap.height * scale))

        const ctx = canvas.getContext('2d')
        if (!ctx) throw new Error('Canvas 2D context unavailable')
        // JPEG has no alpha channel. Without this, a transparent PNG — a scan
        // saved with a transparent background, say — comes out black.
        ctx.fillStyle = '#ffffff'
        ctx.fillRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)

        const blob = await new Promise(resolve =>
            canvas.toBlob(resolve, 'image/jpeg', JPEG_QUALITY)
        )
        if (!blob) throw new Error('Canvas produced no image data')
        return await blob.arrayBuffer()
    } finally {
        // Release before the next file rather than at the end of the run —
        // several full-resolution bitmaps at once is what runs a mid-range
        // Android out of memory.
        bitmap.close?.()
        canvas.width = 0
        canvas.height = 0
    }
}

/**
 * Merges `files` (images and/or PDFs) into one PDF, page order matching array
 * order. Returns a File ready to hand to the upload endpoint.
 *
 * Throws an Error naming the offending file if any one of them cannot be read,
 * rather than emitting a blank page for it.
 */
export async function combineFilesToPdf(files, { name } = {}) {
    if (!files?.length) throw new Error('No files to combine.')

    // The only load site. Static-importing pdf-lib would put ~400kB into the
    // main bundle, which every visitor to the public supplier page would pay for.
    const { PDFDocument } = await import('pdf-lib')
    const doc = await PDFDocument.create()

    // Sequential on purpose — see the memory note in imageToJpegBytes.
    for (const file of files) {
        try {
            if (file.type === PDF_TYPE) {
                const src = await PDFDocument.load(await file.arrayBuffer(), { ignoreEncryption: true })
                const pages = await doc.copyPages(src, src.getPageIndices())
                pages.forEach(page => doc.addPage(page))
            } else {
                const jpegBytes = await imageToJpegBytes(file)
                const image = await doc.embedJpg(jpegBytes)
                const page = doc.addPage([image.width, image.height])
                page.drawImage(image, { x: 0, y: 0, width: image.width, height: image.height })
            }
        } catch (err) {
            console.error(`Failed to add "${file.name}" to the combined PDF:`, err)
            throw new Error(
                `Couldn't read "${file.name}" — it may be damaged or in a format this browser can't open. Remove it and try again.`
            )
        }
    }

    const bytes = await doc.save()
    return new File([bytes], name || combinedPdfName(files), { type: PDF_TYPE })
}
