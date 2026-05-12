import { useState } from 'react'
import { PlusIcon } from '@heroicons/react/24/outline'
import Navigation from '../components/shared/Navigation'
import ScrapInventoryTab from '../components/scrap/ScrapInventoryTab'
import SaleHistoryTab from '../components/scrap/SaleHistoryTab'
import WriteoffHistoryTab from '../components/scrap/WriteoffHistoryTab'
import RecordSaleModal from '../components/scrap/RecordSaleModal'
import RecordWriteoffModal from '../components/scrap/RecordWriteoffModal'
import { useAuth } from '../hooks/useAuth'

const TABS = [
    { key: 'inventory', label: 'Scrap Inventory' },
    { key: 'sales',     label: 'Sale History' },
    { key: 'writeoffs', label: 'Write-off History' },
]

export default function Scrap() {
    const { userProfile } = useAuth()
    const [tab, setTab] = useState('inventory')
    const [showSaleModal, setShowSaleModal] = useState(false)
    const [showWriteoffModal, setShowWriteoffModal] = useState(false)

    const isExec = userProfile?.role !== 'finance'

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Scrap' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                {/* Header row */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                    <h1 className="text-2xl font-bold text-gray-900">Scrap Inventory</h1>
                    {isExec && (
                        <div className="flex gap-3">
                            <button
                                onClick={() => setShowWriteoffModal(true)}
                                className="flex items-center gap-2 px-4 py-2 text-sm border rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-sm"
                            >
                                <PlusIcon className="w-4 h-4" />
                                Record Write-off
                            </button>
                            <button
                                onClick={() => setShowSaleModal(true)}
                                className="flex items-center gap-2 px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 shadow-sm"
                            >
                                <PlusIcon className="w-4 h-4" />
                                Record Sale
                            </button>
                        </div>
                    )}
                </div>

                {/* Tabs */}
                <div className="flex gap-1 bg-white border rounded-lg p-1 mb-6 w-fit shadow-sm">
                    {TABS.map(t => (
                        <button
                            key={t.key}
                            onClick={() => setTab(t.key)}
                            className={`px-4 py-1.5 text-sm rounded-md transition-colors ${
                                tab === t.key
                                    ? 'bg-blue-600 text-white font-medium'
                                    : 'text-gray-600 hover:text-gray-900'
                            }`}
                        >
                            {t.label}
                        </button>
                    ))}
                </div>

                {tab === 'inventory' && <ScrapInventoryTab />}
                {tab === 'sales'     && <SaleHistoryTab />}
                {tab === 'writeoffs' && <WriteoffHistoryTab />}
            </div>

            {showSaleModal && (
                <RecordSaleModal onClose={() => setShowSaleModal(false)} />
            )}
            {showWriteoffModal && (
                <RecordWriteoffModal onClose={() => setShowWriteoffModal(false)} />
            )}
        </div>
    )
}
