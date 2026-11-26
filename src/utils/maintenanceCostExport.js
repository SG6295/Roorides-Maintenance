import * as XLSX from 'xlsx'
import { companyLabel } from '../constants/vehicleCompanies'
import { categoryOf, hubOf, isCostLine } from './maintenanceCost'

const KIND_LABEL = { spare: 'Spare (in-house)', outsourced: 'Outsourced invoice', mvi: 'Multi-vehicle invoice line' }

/**
 * Maintenance cost as .xlsx (MAIN-164): one row per cost line, exactly the lines the page
 * added up, so the file cannot disagree with the screen.
 */
export function exportMaintenanceCost(lines, fileName) {
    const rows = lines.filter(isCostLine).map(l => ({
        'Date': l.cost_date || '',
        'Vehicle': l.vehicle_number || '',
        'Company': companyLabel(l.company),
        'Hub': hubOf(l),
        'Site': l.site || '',
        'Category': categoryOf(l),
        'Record': l.batch_number ? `MVI-${l.batch_number}` : l.job_card_number ? `JC-${l.job_card_number}` : '',
        'Line': KIND_LABEL[l.kind] || l.kind,
        'Part': l.part_name || '',
        'Quantity': l.kind === 'spare' ? l.quantity : '',
        'Unit': l.unit || '',
        'Amount (₹, incl. GST)': l.price_missing ? '' : Math.round(l.amount * 100) / 100,
        'Price missing': l.price_missing ? 'Yes' : '',
        'Split across issues': l.kind === 'outsourced' && l.split_count > 1 ? l.split_count : '',
        'Awaiting finance': l.awaiting_finance ? 'Yes' : '',
        'Odometer on job card (km)': l.job_card_odometer ?? '',
    }))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(rows), 'Cost lines')
    XLSX.writeFile(wb, fileName)
}
