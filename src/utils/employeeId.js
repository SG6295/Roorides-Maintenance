/**
 * A mechanic's page is addressed by their employee ID (MAIN-143): "NVS 1234" opens at
 * /mechanics/NVS-1234. Uniqueness and the lookup both use one key — lower case, spaces
 * and hyphens removed — mirrored by the generated users.employee_key column, so
 * "NVS 1234", "nvs-1234" and "NVS1234" are the same ID.
 */
export function employeeKey(employeeId) {
    return String(employeeId ?? '').toLowerCase().replace(/[\s-]/g, '')
}

export function mechanicPath(employeeId) {
    return `/mechanics/${encodeURIComponent(String(employeeId ?? '').trim().replace(/\s+/g, '-'))}`
}
