import { LEDGER_COMPANIES, companyFromSlug } from './companyLedger'

/**
 * Which company's supplier and advance ledger a page shows (MAIN-162, epic MAIN-154).
 * It travels in the address as `?co=nvs-travels` / `?co=nvs-travel-solutions` — the
 * Company ledger's slugs — so a link opens the right tab. No `co`, or one that isn't a
 * company, is NVS Travels, so links from before the split still open.
 */
export const DEFAULT_LEDGER_COMPANY = 'nvs_travels'

export const ledgerCompanyFrom = searchParams =>
    companyFromSlug(searchParams?.get('co')) ?? DEFAULT_LEDGER_COMPANY

export const ledgerCompanySlug = company =>
    LEDGER_COMPANIES.find(c => c.value === company)?.slug
    ?? LEDGER_COMPANIES.find(c => c.value === DEFAULT_LEDGER_COMPANY).slug

/** "/supplier-ledger#advances" + Pvt Ltd → "/supplier-ledger?co=nvs-travel-solutions#advances". */
export function withLedgerCompany(path, company) {
    const [base, hash] = path.split('#')
    return `${base}?co=${ledgerCompanySlug(company)}${hash ? `#${hash}` : ''}`
}

export const supplierLedgerHome = company => withLedgerCompany('/supplier-ledger', company)

export const advanceStatementPath = (person, company) =>
    withLedgerCompany(`/supplier-ledger/advances/${encodeURIComponent(person)}`, company)

/** "NVS Travels'" / "NVS Travel Solutions Pvt Ltd's" — for "<company> accepted invoices". */
export const possessive = name => (name.endsWith('s') ? `${name}'` : `${name}'s`)
