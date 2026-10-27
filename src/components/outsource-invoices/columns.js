/**
 * Every column the Outsource Invoices list can show (MAIN-98). `default` marks the
 * set everyone sees on load; the column manager changes it only until the page is
 * reloaded. Once finance settles the list, flip the flags here.
 *
 * How each column's cell is drawn lives in InvoiceCell.jsx, keyed by `key`.
 */
export const COLUMNS = [
    { key: 'job_card',           label: 'Job Card',           default: true },
    { key: 'vehicle',            label: 'Vehicle',            default: true },
    { key: 'supplier',           label: 'Supplier',           default: true },
    { key: 'invoice_no',         label: 'Invoice No',         default: true },
    { key: 'invoice_link',       label: 'Invoice Link',       default: true },
    { key: 'activity_date',      label: 'Activity Date',      default: true },
    { key: 'completed',          label: 'Completed',          default: false },
    { key: 'submitted',          label: 'Invoice Submitted',  default: false },
    { key: 'paid_by',            label: 'Paid By',            default: true },
    { key: 'invoice_value',      label: 'Invoice Value',      default: false, align: 'right' },
    { key: 'discount',           label: 'Discount',           default: false, align: 'right' },
    { key: 'approved',           label: 'Approved',           default: false, align: 'right' },
    { key: 'advance',            label: 'Advance',            default: false, align: 'right' },
    { key: 'payable',            label: 'Payable',            default: true,  align: 'right' },
    { key: 'paid',               label: 'Paid',               default: true,  align: 'right' },
    { key: 'tds',                label: 'TDS',                default: true,  align: 'right' },
    { key: 'round_off',          label: 'Round-off',          default: false, align: 'right' },
    { key: 'balance',            label: 'Balance',            default: false, align: 'right' },
    { key: 'maintenance_status', label: 'Maintenance Status', default: true },
    { key: 'finance_status',     label: 'Finance Status',     default: true },
    { key: 'finance_remark',     label: 'Finance Remark',     default: true },
    { key: 'last_paid_on',       label: 'Last Paid On',       default: true },
    { key: 'last_ledger',        label: 'Last Ledger',        default: false },
    { key: 'pay_by',             label: 'Pay By',             default: true },
]

export const DEFAULT_COLUMN_KEYS = COLUMNS.filter(c => c.default).map(c => c.key)
