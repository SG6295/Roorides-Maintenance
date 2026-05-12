export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          changed_fields: string[] | null
          id: string
          new_data: Json | null
          old_data: Json | null
          performed_at: string | null
          performed_by: string | null
          record_id: string
          table_name: string
        }
        Insert: {
          action: string
          changed_fields?: string[] | null
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          performed_at?: string | null
          performed_by?: string | null
          record_id: string
          table_name: string
        }
        Update: {
          action?: string
          changed_fields?: string[] | null
          id?: string
          new_data?: Json | null
          old_data?: Json | null
          performed_at?: string | null
          performed_by?: string | null
          record_id?: string
          table_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_performed_by_fkey"
            columns: ["performed_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      finance_entries: {
        Row: {
          accounting_status: string | null
          activity_date: string
          advance_amount: number | null
          approval_screenshot: string | null
          approved_amount: number | null
          bill_attachment: string | null
          created_at: string | null
          created_by_user_id: string
          id: string
          invoice_number: string | null
          invoice_value: number | null
          job_card_upload: string | null
          job_sheet_id: string | null
          km_reading: number | null
          paid_amount: number | null
          payable_amount: number | null
          payment_date: string | null
          payment_status: string | null
          payment_via: string | null
          site: string | null
          ticket_id: string | null
          transaction_details: string | null
          vehicle_number: string | null
          vendor_contact: string | null
          vendor_name: string | null
          work_description: string
          work_inspected_by: string | null
          work_type: string
        }
        Insert: {
          accounting_status?: string | null
          activity_date: string
          advance_amount?: number | null
          approval_screenshot?: string | null
          approved_amount?: number | null
          bill_attachment?: string | null
          created_at?: string | null
          created_by_user_id: string
          id?: string
          invoice_number?: string | null
          invoice_value?: number | null
          job_card_upload?: string | null
          job_sheet_id?: string | null
          km_reading?: number | null
          paid_amount?: number | null
          payable_amount?: number | null
          payment_date?: string | null
          payment_status?: string | null
          payment_via?: string | null
          site?: string | null
          ticket_id?: string | null
          transaction_details?: string | null
          vehicle_number?: string | null
          vendor_contact?: string | null
          vendor_name?: string | null
          work_description: string
          work_inspected_by?: string | null
          work_type: string
        }
        Update: {
          accounting_status?: string | null
          activity_date?: string
          advance_amount?: number | null
          approval_screenshot?: string | null
          approved_amount?: number | null
          bill_attachment?: string | null
          created_at?: string | null
          created_by_user_id?: string
          id?: string
          invoice_number?: string | null
          invoice_value?: number | null
          job_card_upload?: string | null
          job_sheet_id?: string | null
          km_reading?: number | null
          paid_amount?: number | null
          payable_amount?: number | null
          payment_date?: string | null
          payment_status?: string | null
          payment_via?: string | null
          site?: string | null
          ticket_id?: string | null
          transaction_details?: string | null
          vehicle_number?: string | null
          vendor_contact?: string | null
          vendor_name?: string | null
          work_description?: string
          work_inspected_by?: string | null
          work_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "finance_entries_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_entries_site_fkey"
            columns: ["site"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "finance_entries_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      holidays: {
        Row: {
          created_at: string | null
          date: string
          description: string | null
          id: string
        }
        Insert: {
          created_at?: string | null
          date: string
          description?: string | null
          id?: string
        }
        Update: {
          created_at?: string | null
          date?: string
          description?: string | null
          id?: string
        }
        Relationships: []
      }
      issue_parts: {
        Row: {
          added_at: string | null
          added_by: string | null
          id: string
          issue_id: string
          outsource_part_disposition:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount: number | null
          part_id: string
          quantity_used: number
        }
        Insert: {
          added_at?: string | null
          added_by?: string | null
          id?: string
          issue_id: string
          outsource_part_disposition?:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount?: number | null
          part_id: string
          quantity_used: number
        }
        Update: {
          added_at?: string | null
          added_by?: string | null
          id?: string
          issue_id?: string
          outsource_part_disposition?:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount?: number | null
          part_id?: string
          quantity_used?: number
        }
        Relationships: [
          {
            foreignKeyName: "issue_parts_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "issue_parts_issue_id_fkey"
            columns: ["issue_id"]
            isOneToOne: false
            referencedRelation: "issues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "issue_parts_part_id_fkey"
            columns: ["part_id"]
            isOneToOne: false
            referencedRelation: "parts"
            referencedColumns: ["id"]
          },
        ]
      }
      issues: {
        Row: {
          category: Database["public"]["Enums"]["issue_category"]
          created_at: string | null
          description: string
          id: string
          issue_number: string | null
          job_card_id: string | null
          labour_hours: number | null
          rated_at: string | null
          rating: Database["public"]["Enums"]["rating_enum"] | null
          rating_remarks: string | null
          severity: Database["public"]["Enums"]["issue_severity"] | null
          sla_days: number | null
          sla_end_date: string | null
          sla_status: Database["public"]["Enums"]["sla_status_enum"] | null
          status: Database["public"]["Enums"]["issue_status"] | null
          ticket_id: string
          work_type: Database["public"]["Enums"]["work_type_enum"] | null
        }
        Insert: {
          category: Database["public"]["Enums"]["issue_category"]
          created_at?: string | null
          description: string
          id?: string
          issue_number?: string | null
          job_card_id?: string | null
          labour_hours?: number | null
          rated_at?: string | null
          rating?: Database["public"]["Enums"]["rating_enum"] | null
          rating_remarks?: string | null
          severity?: Database["public"]["Enums"]["issue_severity"] | null
          sla_days?: number | null
          sla_end_date?: string | null
          sla_status?: Database["public"]["Enums"]["sla_status_enum"] | null
          status?: Database["public"]["Enums"]["issue_status"] | null
          ticket_id: string
          work_type?: Database["public"]["Enums"]["work_type_enum"] | null
        }
        Update: {
          category?: Database["public"]["Enums"]["issue_category"]
          created_at?: string | null
          description?: string
          id?: string
          issue_number?: string | null
          job_card_id?: string | null
          labour_hours?: number | null
          rated_at?: string | null
          rating?: Database["public"]["Enums"]["rating_enum"] | null
          rating_remarks?: string | null
          severity?: Database["public"]["Enums"]["issue_severity"] | null
          sla_days?: number | null
          sla_end_date?: string | null
          sla_status?: Database["public"]["Enums"]["sla_status_enum"] | null
          status?: Database["public"]["Enums"]["issue_status"] | null
          ticket_id?: string
          work_type?: Database["public"]["Enums"]["work_type_enum"] | null
        }
        Relationships: [
          {
            foreignKeyName: "issues_job_card_id_fkey"
            columns: ["job_card_id"]
            isOneToOne: false
            referencedRelation: "job_cards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "issues_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      job_cards: {
        Row: {
          assigned_mechanic_id: string | null
          completed_at: string | null
          created_at: string | null
          id: string
          invoice_url: string | null
          job_card_number: number
          odometer: number | null
          remarks: string | null
          site: string
          status: Database["public"]["Enums"]["job_card_status"] | null
          supplier_id: string | null
          type: Database["public"]["Enums"]["work_type_enum"]
          vehicle_number: string
        }
        Insert: {
          assigned_mechanic_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          id?: string
          invoice_url?: string | null
          job_card_number?: never
          odometer?: number | null
          remarks?: string | null
          site: string
          status?: Database["public"]["Enums"]["job_card_status"] | null
          supplier_id?: string | null
          type: Database["public"]["Enums"]["work_type_enum"]
          vehicle_number: string
        }
        Update: {
          assigned_mechanic_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          id?: string
          invoice_url?: string | null
          job_card_number?: never
          odometer?: number | null
          remarks?: string | null
          site?: string
          status?: Database["public"]["Enums"]["job_card_status"] | null
          supplier_id?: string | null
          type?: Database["public"]["Enums"]["work_type_enum"]
          vehicle_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_cards_assigned_mechanic_id_fkey"
            columns: ["assigned_mechanic_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_cards_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      outsource_invoice_payments: {
        Row: {
          amount_paid: number
          attachment_urls: string[]
          created_at: string
          id: string
          notes: string | null
          outsource_invoice_id: string
          paid_on: string
          recorded_by: string | null
        }
        Insert: {
          amount_paid: number
          attachment_urls?: string[]
          created_at?: string
          id?: string
          notes?: string | null
          outsource_invoice_id: string
          paid_on: string
          recorded_by?: string | null
        }
        Update: {
          amount_paid?: number
          attachment_urls?: string[]
          created_at?: string
          id?: string
          notes?: string | null
          outsource_invoice_id?: string
          paid_on?: string
          recorded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "outsource_invoice_payments_outsource_invoice_id_fkey"
            columns: ["outsource_invoice_id"]
            isOneToOne: false
            referencedRelation: "outsource_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_invoice_payments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      outsource_invoices: {
        Row: {
          advance_amount: number | null
          approved_amount: number | null
          created_at: string
          created_by: string | null
          date_of_activity: string | null
          id: string
          invoice_no: string | null
          invoice_value: number | null
          job_card_id: string | null
          paid_by: string | null
          payby_date: string | null
          payment_status: string | null
          updated_at: string
        }
        Insert: {
          advance_amount?: number | null
          approved_amount?: number | null
          created_at?: string
          created_by?: string | null
          date_of_activity?: string | null
          id?: string
          invoice_no?: string | null
          invoice_value?: number | null
          job_card_id?: string | null
          paid_by?: string | null
          payby_date?: string | null
          payment_status?: string | null
          updated_at?: string
        }
        Update: {
          advance_amount?: number | null
          approved_amount?: number | null
          created_at?: string
          created_by?: string | null
          date_of_activity?: string | null
          id?: string
          invoice_no?: string | null
          invoice_value?: number | null
          job_card_id?: string | null
          paid_by?: string | null
          payby_date?: string | null
          payment_status?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "outsource_invoices_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_invoices_job_card_id_fkey"
            columns: ["job_card_id"]
            isOneToOne: true
            referencedRelation: "job_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      part_units: {
        Row: {
          created_at: string | null
          id: string
          name: string
          sort_order: number | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          name: string
          sort_order?: number | null
        }
        Update: {
          created_at?: string | null
          id?: string
          name?: string
          sort_order?: number | null
        }
        Relationships: []
      }
      parts: {
        Row: {
          created_at: string | null
          created_via: string
          id: string
          name: string
          part_number: string | null
          quantity_in_stock: number
          unit: string | null
        }
        Insert: {
          created_at?: string | null
          created_via?: string
          id?: string
          name: string
          part_number?: string | null
          quantity_in_stock?: number
          unit?: string | null
        }
        Update: {
          created_at?: string | null
          created_via?: string
          id?: string
          name?: string
          part_number?: string | null
          quantity_in_stock?: number
          unit?: string | null
        }
        Relationships: []
      }
      purchase_invoice_items: {
        Row: {
          gst_rate: number
          id: string
          invoice_id: string
          line_total: number | null
          part_id: string
          quantity: number
          unit_price: number
        }
        Insert: {
          gst_rate?: number
          id?: string
          invoice_id: string
          line_total?: number | null
          part_id: string
          quantity: number
          unit_price: number
        }
        Update: {
          gst_rate?: number
          id?: string
          invoice_id?: string
          line_total?: number | null
          part_id?: string
          quantity?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_invoice_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "purchase_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_invoice_items_part_id_fkey"
            columns: ["part_id"]
            isOneToOne: false
            referencedRelation: "parts"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_invoices: {
        Row: {
          created_at: string | null
          created_by: string | null
          id: string
          invoice_date: string
          invoice_file_url: string | null
          invoice_number: string
          notes: string | null
          supplier_name: string
          total_amount: number | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          id?: string
          invoice_date: string
          invoice_file_url?: string | null
          invoice_number: string
          notes?: string | null
          supplier_name: string
          total_amount?: number | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          id?: string
          invoice_date?: string
          invoice_file_url?: string | null
          invoice_number?: string
          notes?: string | null
          supplier_name?: string
          total_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_invoices_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_disposal: {
        Row: {
          buyer_contact: string | null
          buyer_name: string
          disposal_date: string
          id: string
          notes: string | null
          payment_mode: Database["public"]["Enums"]["scrap_payment_mode"]
          payment_reference: string | null
          receipt_photos: string[]
          recorded_at: string
          recorded_by: string
          total_value: number
        }
        Insert: {
          buyer_contact?: string | null
          buyer_name: string
          disposal_date: string
          id?: string
          notes?: string | null
          payment_mode: Database["public"]["Enums"]["scrap_payment_mode"]
          payment_reference?: string | null
          receipt_photos?: string[]
          recorded_at?: string
          recorded_by: string
          total_value: number
        }
        Update: {
          buyer_contact?: string | null
          buyer_name?: string
          disposal_date?: string
          id?: string
          notes?: string | null
          payment_mode?: Database["public"]["Enums"]["scrap_payment_mode"]
          payment_reference?: string | null
          receipt_photos?: string[]
          recorded_at?: string
          recorded_by?: string
          total_value?: number
        }
        Relationships: [
          {
            foreignKeyName: "scrap_disposal_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_disposal_items: {
        Row: {
          created_at: string
          disposal_id: string
          id: string
          part_name_snapshot: string
          quantity_snapshot: number
          scrap_inventory_id: string
          unit_snapshot: string
          value_allocated: number
        }
        Insert: {
          created_at?: string
          disposal_id: string
          id?: string
          part_name_snapshot: string
          quantity_snapshot: number
          scrap_inventory_id: string
          unit_snapshot: string
          value_allocated: number
        }
        Update: {
          created_at?: string
          disposal_id?: string
          id?: string
          part_name_snapshot?: string
          quantity_snapshot?: number
          scrap_inventory_id?: string
          unit_snapshot?: string
          value_allocated?: number
        }
        Relationships: [
          {
            foreignKeyName: "scrap_disposal_items_disposal_fkey"
            columns: ["disposal_id"]
            isOneToOne: false
            referencedRelation: "scrap_disposal"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_disposal_items_scrap_inventory_fkey"
            columns: ["scrap_inventory_id"]
            isOneToOne: false
            referencedRelation: "scrap_inventory"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_excluded_parts: {
        Row: {
          excluded_at: string
          excluded_by: string
          id: string
          notes: string | null
          part_id_snapshot: string | null
          part_name_snapshot: string
          quantity_snapshot: number
          reason: Database["public"]["Enums"]["scrap_exclusion_reason"]
          source_issue_id: string
          source_issue_part_id: string | null
          source_job_card_id: string
        }
        Insert: {
          excluded_at?: string
          excluded_by: string
          id?: string
          notes?: string | null
          part_id_snapshot?: string | null
          part_name_snapshot: string
          quantity_snapshot: number
          reason: Database["public"]["Enums"]["scrap_exclusion_reason"]
          source_issue_id: string
          source_issue_part_id?: string | null
          source_job_card_id: string
        }
        Update: {
          excluded_at?: string
          excluded_by?: string
          id?: string
          notes?: string | null
          part_id_snapshot?: string | null
          part_name_snapshot?: string
          quantity_snapshot?: number
          reason?: Database["public"]["Enums"]["scrap_exclusion_reason"]
          source_issue_id?: string
          source_issue_part_id?: string | null
          source_job_card_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scrap_excluded_parts_excluded_by_fkey"
            columns: ["excluded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_excluded_parts_source_issue_fkey"
            columns: ["source_issue_id"]
            isOneToOne: false
            referencedRelation: "issues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_excluded_parts_source_issue_part_fkey"
            columns: ["source_issue_part_id"]
            isOneToOne: false
            referencedRelation: "issue_parts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_excluded_parts_source_job_card_fkey"
            columns: ["source_job_card_id"]
            isOneToOne: false
            referencedRelation: "job_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_inventory: {
        Row: {
          created_at: string
          created_by: string
          current_location: string | null
          description: string | null
          estimated_value: number | null
          id: string
          notes: string | null
          outsource_part_disposition_snapshot:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount_snapshot: number | null
          part_id_snapshot: string | null
          part_name_snapshot: string
          part_number_snapshot: string | null
          photos: string[]
          quantity_snapshot: number
          received_at: string | null
          received_by: string | null
          source_issue_id: string
          source_issue_part_id: string | null
          source_job_card_id: string
          source_ticket_id: string
          source_vehicle_number: string
          status: Database["public"]["Enums"]["scrap_item_status"]
          unit_snapshot: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          current_location?: string | null
          description?: string | null
          estimated_value?: number | null
          id?: string
          notes?: string | null
          outsource_part_disposition_snapshot?:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount_snapshot?: number | null
          part_id_snapshot?: string | null
          part_name_snapshot: string
          part_number_snapshot?: string | null
          photos?: string[]
          quantity_snapshot: number
          received_at?: string | null
          received_by?: string | null
          source_issue_id: string
          source_issue_part_id?: string | null
          source_job_card_id: string
          source_ticket_id: string
          source_vehicle_number: string
          status?: Database["public"]["Enums"]["scrap_item_status"]
          unit_snapshot: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          current_location?: string | null
          description?: string | null
          estimated_value?: number | null
          id?: string
          notes?: string | null
          outsource_part_disposition_snapshot?:
            | Database["public"]["Enums"]["outsource_part_disposition"]
            | null
          outsource_vendor_credit_amount_snapshot?: number | null
          part_id_snapshot?: string | null
          part_name_snapshot?: string
          part_number_snapshot?: string | null
          photos?: string[]
          quantity_snapshot?: number
          received_at?: string | null
          received_by?: string | null
          source_issue_id?: string
          source_issue_part_id?: string | null
          source_job_card_id?: string
          source_ticket_id?: string
          source_vehicle_number?: string
          status?: Database["public"]["Enums"]["scrap_item_status"]
          unit_snapshot?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "scrap_inventory_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_received_by_fkey"
            columns: ["received_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_source_issue_fkey"
            columns: ["source_issue_id"]
            isOneToOne: false
            referencedRelation: "issues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_source_issue_part_fkey"
            columns: ["source_issue_part_id"]
            isOneToOne: false
            referencedRelation: "issue_parts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_source_job_card_fkey"
            columns: ["source_job_card_id"]
            isOneToOne: false
            referencedRelation: "job_cards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_source_ticket_fkey"
            columns: ["source_ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_inventory_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_writeoff: {
        Row: {
          description: string
          evidence_photos: string[]
          id: string
          notes: string | null
          reason: Database["public"]["Enums"]["scrap_writeoff_reason"]
          recorded_at: string
          recorded_by: string
          writeoff_date: string
        }
        Insert: {
          description: string
          evidence_photos?: string[]
          id?: string
          notes?: string | null
          reason: Database["public"]["Enums"]["scrap_writeoff_reason"]
          recorded_at?: string
          recorded_by: string
          writeoff_date: string
        }
        Update: {
          description?: string
          evidence_photos?: string[]
          id?: string
          notes?: string | null
          reason?: Database["public"]["Enums"]["scrap_writeoff_reason"]
          recorded_at?: string
          recorded_by?: string
          writeoff_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "scrap_writeoff_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      scrap_writeoff_items: {
        Row: {
          created_at: string
          id: string
          part_name_snapshot: string
          quantity_snapshot: number
          scrap_inventory_id: string
          unit_snapshot: string
          writeoff_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          part_name_snapshot: string
          quantity_snapshot: number
          scrap_inventory_id: string
          unit_snapshot: string
          writeoff_id: string
        }
        Update: {
          created_at?: string
          id?: string
          part_name_snapshot?: string
          quantity_snapshot?: number
          scrap_inventory_id?: string
          unit_snapshot?: string
          writeoff_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scrap_writeoff_items_scrap_inventory_fkey"
            columns: ["scrap_inventory_id"]
            isOneToOne: false
            referencedRelation: "scrap_inventory"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scrap_writeoff_items_writeoff_fkey"
            columns: ["writeoff_id"]
            isOneToOne: false
            referencedRelation: "scrap_writeoff"
            referencedColumns: ["id"]
          },
        ]
      }
      sites: {
        Row: {
          created_at: string | null
          id: string
          is_active: boolean | null
          name: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          name: string
        }
        Update: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          name?: string
        }
        Relationships: []
      }
      sla_events: {
        Row: {
          created_at: string | null
          created_by: string
          event_type: string
          id: string
          metadata: Json | null
          ticket_id: string | null
        }
        Insert: {
          created_at?: string | null
          created_by: string
          event_type: string
          id?: string
          metadata?: Json | null
          ticket_id?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string
          event_type?: string
          id?: string
          metadata?: Json | null
          ticket_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sla_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sla_events_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      sla_rules: {
        Row: {
          category: string
          created_at: string | null
          days: number
          id: string
          impact: string
          updated_at: string | null
        }
        Insert: {
          category: string
          created_at?: string | null
          days?: number
          id?: string
          impact: string
          updated_at?: string | null
        }
        Update: {
          category?: string
          created_at?: string | null
          days?: number
          id?: string
          impact?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      sla_rules_config: {
        Row: {
          category: Database["public"]["Enums"]["issue_category"]
          id: string
          severity: Database["public"]["Enums"]["issue_severity"]
          sla_days: number
        }
        Insert: {
          category: Database["public"]["Enums"]["issue_category"]
          id?: string
          severity: Database["public"]["Enums"]["issue_severity"]
          sla_days: number
        }
        Update: {
          category?: Database["public"]["Enums"]["issue_category"]
          id?: string
          severity?: Database["public"]["Enums"]["issue_severity"]
          sla_days?: number
        }
        Relationships: []
      }
      suppliers: {
        Row: {
          account_holder_name: string | null
          account_number: string | null
          account_type: string | null
          accounts_contact_name: string | null
          accounts_contact_number: string | null
          accounts_email: string | null
          bank_branch: string | null
          bank_name: string | null
          brand_spares_usage: string | null
          cancelled_cheque_url: string | null
          created_at: string | null
          created_by: string | null
          created_via: string
          email: string | null
          entity_name: string
          entity_type: string | null
          entity_type_other: string | null
          esi_certificate_url: string | null
          esi_registration_number: string | null
          gst_certificate_url: string | null
          gst_registration_type: string | null
          gstin: string | null
          id: string
          ifsc_code: string | null
          labour_license_number: string | null
          major_clients: string | null
          msme_udyam_number: string | null
          nature_of_work: string
          owner_contact: string
          owner_email: string | null
          owner_name: string
          pan_copy_url: string | null
          pan_number: string | null
          payment_terms_days: string | null
          pf_certificate_url: string | null
          pf_registration_number: string | null
          po_communication_emails: string | null
          registered_office_address: string
          sales_contact_name: string | null
          sales_contact_number: string | null
          sales_email: string | null
          skilled_manpower_available: boolean | null
          status: string | null
          submitted_by: string | null
          udyam_certificate_url: string | null
          workshop_address: string | null
          years_of_experience: string | null
        }
        Insert: {
          account_holder_name?: string | null
          account_number?: string | null
          account_type?: string | null
          accounts_contact_name?: string | null
          accounts_contact_number?: string | null
          accounts_email?: string | null
          bank_branch?: string | null
          bank_name?: string | null
          brand_spares_usage?: string | null
          cancelled_cheque_url?: string | null
          created_at?: string | null
          created_by?: string | null
          created_via?: string
          email?: string | null
          entity_name: string
          entity_type?: string | null
          entity_type_other?: string | null
          esi_certificate_url?: string | null
          esi_registration_number?: string | null
          gst_certificate_url?: string | null
          gst_registration_type?: string | null
          gstin?: string | null
          id?: string
          ifsc_code?: string | null
          labour_license_number?: string | null
          major_clients?: string | null
          msme_udyam_number?: string | null
          nature_of_work: string
          owner_contact: string
          owner_email?: string | null
          owner_name: string
          pan_copy_url?: string | null
          pan_number?: string | null
          payment_terms_days?: string | null
          pf_certificate_url?: string | null
          pf_registration_number?: string | null
          po_communication_emails?: string | null
          registered_office_address: string
          sales_contact_name?: string | null
          sales_contact_number?: string | null
          sales_email?: string | null
          skilled_manpower_available?: boolean | null
          status?: string | null
          submitted_by?: string | null
          udyam_certificate_url?: string | null
          workshop_address?: string | null
          years_of_experience?: string | null
        }
        Update: {
          account_holder_name?: string | null
          account_number?: string | null
          account_type?: string | null
          accounts_contact_name?: string | null
          accounts_contact_number?: string | null
          accounts_email?: string | null
          bank_branch?: string | null
          bank_name?: string | null
          brand_spares_usage?: string | null
          cancelled_cheque_url?: string | null
          created_at?: string | null
          created_by?: string | null
          created_via?: string
          email?: string | null
          entity_name?: string
          entity_type?: string | null
          entity_type_other?: string | null
          esi_certificate_url?: string | null
          esi_registration_number?: string | null
          gst_certificate_url?: string | null
          gst_registration_type?: string | null
          gstin?: string | null
          id?: string
          ifsc_code?: string | null
          labour_license_number?: string | null
          major_clients?: string | null
          msme_udyam_number?: string | null
          nature_of_work?: string
          owner_contact?: string
          owner_email?: string | null
          owner_name?: string
          pan_copy_url?: string | null
          pan_number?: string | null
          payment_terms_days?: string | null
          pf_certificate_url?: string | null
          pf_registration_number?: string | null
          po_communication_emails?: string | null
          registered_office_address?: string
          sales_contact_name?: string | null
          sales_contact_number?: string | null
          sales_email?: string | null
          skilled_manpower_available?: boolean | null
          status?: string | null
          submitted_by?: string | null
          udyam_certificate_url?: string | null
          workshop_address?: string | null
          years_of_experience?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      system_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string | null
          value: string
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string | null
          value: string
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string | null
          value?: string
        }
        Relationships: []
      }
      tickets: {
        Row: {
          acceptance_sla_status:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          closed_at: string | null
          created_at: string | null
          created_by_user_id: string
          final_sla_end_date: string | null
          id: string
          initial_remarks: string | null
          is_duplicate: boolean | null
          merged_into_ticket_id: string | null
          overall_sla_status:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          photos: string[] | null
          rated_at: string | null
          rating_comment: string | null
          rejected_at: string | null
          rejected_reason: string | null
          rejection_comment: string | null
          rejection_reason: string | null
          resolved_at: string | null
          site: string
          status: Database["public"]["Enums"]["ticket_status_new"] | null
          supervisor_contact: string | null
          supervisor_id: string
          supervisor_name: string
          tat_days: number | null
          ticket_number: number
          vehicle_number: string
        }
        Insert: {
          acceptance_sla_status?:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          closed_at?: string | null
          created_at?: string | null
          created_by_user_id: string
          final_sla_end_date?: string | null
          id?: string
          initial_remarks?: string | null
          is_duplicate?: boolean | null
          merged_into_ticket_id?: string | null
          overall_sla_status?:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          photos?: string[] | null
          rated_at?: string | null
          rating_comment?: string | null
          rejected_at?: string | null
          rejected_reason?: string | null
          rejection_comment?: string | null
          rejection_reason?: string | null
          resolved_at?: string | null
          site: string
          status?: Database["public"]["Enums"]["ticket_status_new"] | null
          supervisor_contact?: string | null
          supervisor_id: string
          supervisor_name: string
          tat_days?: number | null
          ticket_number?: never
          vehicle_number: string
        }
        Update: {
          acceptance_sla_status?:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          closed_at?: string | null
          created_at?: string | null
          created_by_user_id?: string
          final_sla_end_date?: string | null
          id?: string
          initial_remarks?: string | null
          is_duplicate?: boolean | null
          merged_into_ticket_id?: string | null
          overall_sla_status?:
            | Database["public"]["Enums"]["sla_status_enum"]
            | null
          photos?: string[] | null
          rated_at?: string | null
          rating_comment?: string | null
          rejected_at?: string | null
          rejected_reason?: string | null
          rejection_comment?: string | null
          rejection_reason?: string | null
          resolved_at?: string | null
          site?: string
          status?: Database["public"]["Enums"]["ticket_status_new"] | null
          supervisor_contact?: string | null
          supervisor_id?: string
          supervisor_name?: string
          tat_days?: number | null
          ticket_number?: never
          vehicle_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "tickets_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tickets_merged_into_ticket_id_fkey"
            columns: ["merged_into_ticket_id"]
            isOneToOne: false
            referencedRelation: "tickets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tickets_site_fkey"
            columns: ["site"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["name"]
          },
        ]
      }
      user_settings: {
        Row: {
          created_at: string
          digest_preferences: Json | null
          notify_daily_digest: boolean | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          digest_preferences?: Json | null
          notify_daily_digest?: boolean | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          digest_preferences?: Json | null
          notify_daily_digest?: boolean | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_sites: {
        Row: {
          created_at: string | null
          id: string
          site_id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          site_id: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          site_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_sites_site_id_fkey"
            columns: ["site_id"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_sites_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          contact: string | null
          created_at: string | null
          email: string
          employee_id: string | null
          id: string
          is_active: boolean | null
          name: string
          role: string
          site: string | null
        }
        Insert: {
          contact?: string | null
          created_at?: string | null
          email: string
          employee_id?: string | null
          id: string
          is_active?: boolean | null
          name: string
          role: string
          site?: string | null
        }
        Update: {
          contact?: string | null
          created_at?: string | null
          email?: string
          employee_id?: string | null
          id?: string
          is_active?: boolean | null
          name?: string
          role?: string
          site?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "users_site_fkey"
            columns: ["site"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["name"]
          },
        ]
      }
      vehicle_sites: {
        Row: {
          site_name: string
          vehicle_id: string
        }
        Insert: {
          site_name: string
          vehicle_id: string
        }
        Update: {
          site_name?: string
          vehicle_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vehicle_sites_site_name_fkey"
            columns: ["site_name"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "vehicle_sites_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      vehicles: {
        Row: {
          created_at: string | null
          id: string
          is_active: boolean | null
          make: string | null
          model: string | null
          notes: string | null
          raw_data: Json | null
          registration_number: string
          type: string | null
          year: number | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          make?: string | null
          model?: string | null
          notes?: string | null
          raw_data?: Json | null
          registration_number: string
          type?: string | null
          year?: number | null
        }
        Update: {
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          make?: string | null
          model?: string | null
          notes?: string | null
          raw_data?: Json | null
          registration_number?: string
          type?: string | null
          year?: number | null
        }
        Relationships: []
      }
    }
    Views: {
      maintenance_dashboard_stats: {
        Row: {
          avg_tat_days: number | null
          completion_sla_violated: number | null
          inhouse_count: number | null
          outsource_count: number | null
          pending_tickets: number | null
          total_tickets: number | null
        }
        Relationships: []
      }
      supervisor_dashboard_stats: {
        Row: {
          accepted_count: number | null
          avg_csat_score: number | null
          completed_count: number | null
          pending_count: number | null
          rejected_count: number | null
          site: string | null
          sla_violated_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tickets_site_fkey"
            columns: ["site"]
            isOneToOne: false
            referencedRelation: "sites"
            referencedColumns: ["name"]
          },
        ]
      }
    }
    Functions: {
      add_working_days: {
        Args: { n_days: number; start_date: string }
        Returns: string
      }
      calculate_sla_days: {
        Args: { p_category: string; p_impact: string }
        Returns: number
      }
      check_pan_exists: { Args: { p_pan: string }; Returns: boolean }
      close_job_card_with_scrap: {
        Args: {
          p_job_card_id: string
          p_remarks: string
          p_scrap_decisions: Json
        }
        Returns: Json
      }
      delete_issue_part_with_scrap_check: {
        Args: { p_issue_part_id: string }
        Returns: Json
      }
      evaluate_acceptance_sla: {
        Args: { p_first_issue_created: string; p_ticket_id: string }
        Returns: Database["public"]["Enums"]["sla_status_enum"]
      }
      get_blocking_scrap_for_issue_part: {
        Args: { p_issue_part_id: string }
        Returns: Json
      }
      get_maintenance_stats: {
        Args: {
          end_date_input?: string
          site_filter?: string
          start_date_input?: string
        }
        Returns: {
          accept_adhered: number
          accept_pending: number
          accept_violated: number
          comp_in_adhered: number
          comp_in_violated: number
          comp_in_wip_within: number
          comp_out_adhered: number
          comp_out_violated: number
          comp_out_wip_within: number
          csat_score_sum: number
          major_body: number
          major_electrical: number
          major_mechanical: number
          major_total: number
          major_tyre: number
          minor_body: number
          minor_electrical: number
          minor_mechanical: number
          minor_total: number
          minor_tyre: number
          rating_bad: number
          rating_collected: number
          rating_good: number
          rating_ok: number
          rating_pending: number
          status_accepted: number
          status_closed: number
          status_completed: number
          status_new: number
          status_pending: number
          status_rejected: number
          status_resolved: number
          status_wip: number
          total_completed_tickets: number
          total_tickets: number
          type_in_house: number
          type_outsource: number
        }[]
      }
      get_outsource_invoice_summary: {
        Args: {
          p_date_from?: string
          p_date_to?: string
          p_paid_by?: string[]
          p_payment_status?: string[]
        }
        Returns: {
          overdue_count: number
          pending_approval_count: number
          total_unpaid_payable: number
        }[]
      }
      is_maintenance_exec: { Args: never; Returns: boolean }
      is_super_admin: { Args: never; Returns: boolean }
      job_card_site_accessible_to_user: {
        Args: { p_job_card_id: string }
        Returns: boolean
      }
      record_scrap_disposal: {
        Args: { p_header: Json; p_items: Json }
        Returns: Json
      }
      record_scrap_writeoff: {
        Args: { p_header: Json; p_items: Json }
        Returns: Json
      }
    }
    Enums: {
      issue_category:
        | "Mechanical"
        | "Electrical"
        | "Body"
        | "Tyre"
        | "GPS"
        | "AdBlue"
        | "Other"
      issue_severity: "Minor" | "Major"
      issue_status: "Open" | "Done" | "Blocked"
      job_card_status: "Open" | "Completed"
      outsource_part_disposition:
        | "returned_to_nvs"
        | "retained_by_vendor"
        | "retained_by_vendor_with_credit"
      rating_enum: "Good" | "Ok" | "Bad"
      scrap_exclusion_reason:
        | "consumable"
        | "destroyed_on_removal"
        | "retained_by_vendor"
        | "other"
      scrap_item_status:
        | "in_storage"
        | "sent_for_refurbishment"
        | "refurbished"
        | "sold"
        | "written_off"
        | "reversed"
      scrap_payment_mode: "cash" | "upi" | "bank_transfer" | "cheque" | "other"
      scrap_writeoff_reason:
        | "lost"
        | "damaged_unsaleable"
        | "hazmat_disposal"
        | "stocktake_adjustment"
        | "donated"
        | "other"
      sla_status_enum: "Pending" | "Adhered" | "Violated"
      ticket_status_new:
        | "New"
        | "Accepted"
        | "Work In Progress"
        | "Resolved"
        | "Closed"
        | "Rejected"
      work_type_enum: "InHouse" | "Outsource"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      issue_category: [
        "Mechanical",
        "Electrical",
        "Body",
        "Tyre",
        "GPS",
        "AdBlue",
        "Other",
      ],
      issue_severity: ["Minor", "Major"],
      issue_status: ["Open", "Done", "Blocked"],
      job_card_status: ["Open", "Completed"],
      outsource_part_disposition: [
        "returned_to_nvs",
        "retained_by_vendor",
        "retained_by_vendor_with_credit",
      ],
      rating_enum: ["Good", "Ok", "Bad"],
      scrap_exclusion_reason: [
        "consumable",
        "destroyed_on_removal",
        "retained_by_vendor",
        "other",
      ],
      scrap_item_status: [
        "in_storage",
        "sent_for_refurbishment",
        "refurbished",
        "sold",
        "written_off",
        "reversed",
      ],
      scrap_payment_mode: ["cash", "upi", "bank_transfer", "cheque", "other"],
      scrap_writeoff_reason: [
        "lost",
        "damaged_unsaleable",
        "hazmat_disposal",
        "stocktake_adjustment",
        "donated",
        "other",
      ],
      sla_status_enum: ["Pending", "Adhered", "Violated"],
      ticket_status_new: [
        "New",
        "Accepted",
        "Work In Progress",
        "Resolved",
        "Closed",
        "Rejected",
      ],
      work_type_enum: ["InHouse", "Outsource"],
    },
  },
} as const
