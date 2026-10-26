
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "cash_shifts": {
                  Row: {
                    "cashier_id": string,"client_uuid": string,"close_client_uuid": string | null,"closed_at": string | null,"closing_cash_counted": number | null,"created_at": string,"created_by": string | null,"difference": number | null,"expected_cash": number | null,"id": string,"note": string | null,"opened_at": string,"opening_cash": number,"outlet_id": string,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cashier_id": string,"client_uuid": string,"close_client_uuid"?: string | null,"closed_at"?: string | null,"closing_cash_counted"?: number | null,"created_at"?: string,"created_by"?: string | null,"difference"?: number | null,"expected_cash"?: number | null,"id"?: string,"note"?: string | null,"opened_at"?: string,"opening_cash": number,"outlet_id": string,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "cashier_id"?: string,"client_uuid"?: string,"close_client_uuid"?: string | null,"closed_at"?: string | null,"closing_cash_counted"?: number | null,"created_at"?: string,"created_by"?: string | null,"difference"?: number | null,"expected_cash"?: number | null,"id"?: string,"note"?: string | null,"opened_at"?: string,"opening_cash"?: number,"outlet_id"?: string,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "cash_shifts_outlet_same_tenant"
      columns: ["tenant_id","outlet_id"]
isOneToOne: false
      referencedRelation: "outlets"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "cash_shifts_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"categories": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"name": string,"parent_id": string | null,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"parent_id"?: string | null,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"parent_id"?: string | null,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "categories_parent_same_tenant"
      columns: ["tenant_id","parent_id"]
isOneToOne: false
      referencedRelation: "categories"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "categories_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"customers": {
                  Row: {
                    "active": boolean,"address": string | null,"created_at": string,"created_by": string | null,"credit_limit": number,"id": string,"name": string,"notes": string | null,"phone": string | null,"tenant_id": string,"tier_id": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"address"?: string | null,"created_at"?: string,"created_by"?: string | null,"credit_limit"?: number,"id"?: string,"name": string,"notes"?: string | null,"phone"?: string | null,"tenant_id": string,"tier_id"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"address"?: string | null,"created_at"?: string,"created_by"?: string | null,"credit_limit"?: number,"id"?: string,"name"?: string,"notes"?: string | null,"phone"?: string | null,"tenant_id"?: string,"tier_id"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "customers_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "customers_tier_same_tenant"
      columns: ["tenant_id","tier_id"]
isOneToOne: false
      referencedRelation: "price_tiers"
      referencedColumns: ["tenant_id","id"]
    }
                  ]
                },"memberships": {
                  Row: {
                    "active": boolean,"created_at": string,"created_by": string | null,"id": string,"outlet_ids": (string)[],"role": string,"tenant_id": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string | null,"id"?: string,"outlet_ids"?: (string)[],"role"?: string,"tenant_id": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"created_by"?: string | null,"id"?: string,"outlet_ids"?: (string)[],"role"?: string,"tenant_id"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"outlets": {
                  Row: {
                    "address": string | null,"created_at": string,"created_by": string | null,"id": string,"name": string,"phone": string | null,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"phone"?: string | null,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"phone"?: string | null,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "outlets_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"price_breaks": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"min_qty": number,"price": number,"product_id": string,"tenant_id": string,"unit_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"min_qty": number,"price": number,"product_id": string,"tenant_id": string,"unit_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"min_qty"?: number,"price"?: number,"product_id"?: string,"tenant_id"?: string,"unit_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "price_breaks_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "price_breaks_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "price_breaks_unit_same_tenant"
      columns: ["tenant_id","unit_id"]
isOneToOne: false
      referencedRelation: "units"
      referencedColumns: ["tenant_id","id"]
    }
                  ]
                },"price_tiers": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"name": string,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "price_tiers_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"product_prices": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"price": number,"product_id": string,"tenant_id": string,"tier_id": string,"unit_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"price": number,"product_id": string,"tenant_id": string,"tier_id": string,"unit_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"price"?: number,"product_id"?: string,"tenant_id"?: string,"tier_id"?: string,"unit_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "product_prices_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "product_prices_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "product_prices_tier_same_tenant"
      columns: ["tenant_id","tier_id"]
isOneToOne: false
      referencedRelation: "price_tiers"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "product_prices_unit_same_tenant"
      columns: ["tenant_id","unit_id"]
isOneToOne: false
      referencedRelation: "units"
      referencedColumns: ["tenant_id","id"]
    }
                  ]
                },"product_units": {
                  Row: {
                    "barcode": string | null,"created_at": string,"created_by": string | null,"factor_to_base": number,"id": string,"product_id": string,"sell_price": number,"tenant_id": string,"unit_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "barcode"?: string | null,"created_at"?: string,"created_by"?: string | null,"factor_to_base": number,"id"?: string,"product_id": string,"sell_price"?: number,"tenant_id": string,"unit_id": string,"updated_at"?: string
                  }
                  Update: {
                    "barcode"?: string | null,"created_at"?: string,"created_by"?: string | null,"factor_to_base"?: number,"id"?: string,"product_id"?: string,"sell_price"?: number,"tenant_id"?: string,"unit_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "product_units_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "product_units_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "product_units_unit_same_tenant"
      columns: ["tenant_id","unit_id"]
isOneToOne: false
      referencedRelation: "units"
      referencedColumns: ["tenant_id","id"]
    }
                  ]
                },"products": {
                  Row: {
                    "active": boolean,"barcode": string | null,"base_unit_id": string | null,"category_id": string | null,"cost_price": number,"created_at": string,"created_by": string | null,"id": string,"image_url": string | null,"kind": string,"min_stock": number,"name": string,"sell_price": number,"sku": string | null,"tenant_id": string,"track_stock": boolean,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"barcode"?: string | null,"base_unit_id"?: string | null,"category_id"?: string | null,"cost_price"?: number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"image_url"?: string | null,"kind"?: string,"min_stock"?: number,"name": string,"sell_price"?: number,"sku"?: string | null,"tenant_id": string,"track_stock"?: boolean,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"barcode"?: string | null,"base_unit_id"?: string | null,"category_id"?: string | null,"cost_price"?: number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"image_url"?: string | null,"kind"?: string,"min_stock"?: number,"name"?: string,"sell_price"?: number,"sku"?: string | null,"tenant_id"?: string,"track_stock"?: boolean,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "products_category_same_tenant"
      columns: ["tenant_id","category_id"]
isOneToOne: false
      referencedRelation: "categories"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "products_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "products_unit_same_tenant"
      columns: ["tenant_id","base_unit_id"]
isOneToOne: false
      referencedRelation: "units"
      referencedColumns: ["tenant_id","id"]
    }
                  ]
                },"stock_levels": {
                  Row: {
                    "outlet_id": string,"product_id": string,"qty_base": number,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "outlet_id": string,"product_id": string,"qty_base"?: number,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "outlet_id"?: string,"product_id"?: string,"qty_base"?: number,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_levels_outlet_same_tenant"
      columns: ["tenant_id","outlet_id"]
isOneToOne: false
      referencedRelation: "outlets"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_levels_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_levels_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_movements": {
                  Row: {
                    "client_uuid": string | null,"created_at": string,"created_by": string | null,"id": string,"note": string | null,"outlet_id": string,"product_id": string,"qty_base": number,"ref_id": string | null,"ref_type": string | null,"tenant_id": string,"type": string,"unit_cost": number
                  }
                  ComputedFields: never
                  Insert: {
                    "client_uuid"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"note"?: string | null,"outlet_id": string,"product_id": string,"qty_base": number,"ref_id"?: string | null,"ref_type"?: string | null,"tenant_id": string,"type": string,"unit_cost"?: number
                  }
                  Update: {
                    "client_uuid"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"note"?: string | null,"outlet_id"?: string,"product_id"?: string,"qty_base"?: number,"ref_id"?: string | null,"ref_type"?: string | null,"tenant_id"?: string,"type"?: string,"unit_cost"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_movements_outlet_same_tenant"
      columns: ["tenant_id","outlet_id"]
isOneToOne: false
      referencedRelation: "outlets"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_movements_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_movements_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_opname_items": {
                  Row: {
                    "counted_qty": number | null,"created_at": string,"difference": number,"id": string,"opname_id": string,"product_id": string,"system_qty": number,"tenant_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "counted_qty"?: number | null,"created_at"?: string,"difference"?: number,"id"?: string,"opname_id": string,"product_id": string,"system_qty"?: number,"tenant_id": string
                  }
                  Update: {
                    "counted_qty"?: number | null,"created_at"?: string,"difference"?: number,"id"?: string,"opname_id"?: string,"product_id"?: string,"system_qty"?: number,"tenant_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_opname_items_opname_same_tenant"
      columns: ["tenant_id","opname_id"]
isOneToOne: false
      referencedRelation: "stock_opnames"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_opname_items_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_opname_items_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_opnames": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"note": string | null,"outlet_id": string,"posted_at": string | null,"posted_by": string | null,"status": string,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"note"?: string | null,"outlet_id": string,"posted_at"?: string | null,"posted_by"?: string | null,"status"?: string,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"note"?: string | null,"outlet_id"?: string,"posted_at"?: string | null,"posted_by"?: string | null,"status"?: string,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_opnames_outlet_same_tenant"
      columns: ["tenant_id","outlet_id"]
isOneToOne: false
      referencedRelation: "outlets"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_opnames_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"suppliers": {
                  Row: {
                    "active": boolean,"address": string | null,"created_at": string,"created_by": string | null,"id": string,"name": string,"payment_terms_days": number,"phone": string | null,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"address"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"payment_terms_days"?: number,"phone"?: string | null,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"address"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"payment_terms_days"?: number,"phone"?: string | null,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "suppliers_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                },"tenants": {
                  Row: {
                    "business_type": string,"client_uuid": string | null,"created_at": string,"created_by": string | null,"id": string,"name": string,"settings": NonNullable<Json>,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "business_type"?: string,"client_uuid"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"settings"?: NonNullable<Json>,"updated_at"?: string
                  }
                  Update: {
                    "business_type"?: string,"client_uuid"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"settings"?: NonNullable<Json>,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"units": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"name": string,"tenant_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name": string,"tenant_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"name"?: string,"tenant_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "units_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            "stock_by_outlet": {
                  Row: {
                    "is_low": boolean | null,"min_stock": number,"outlet_id": string,"outlet_name": string,"product_id": string,"product_name": string,"qty_base": number,"sku": string | null,"tenant_id": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "stock_levels_outlet_same_tenant"
      columns: ["tenant_id","outlet_id"]
isOneToOne: false
      referencedRelation: "outlets"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_levels_product_same_tenant"
      columns: ["tenant_id","product_id"]
isOneToOne: false
      referencedRelation: "products"
      referencedColumns: ["tenant_id","id"]
    },{
      foreignKeyName: "stock_levels_tenant_id_fkey"
      columns: ["tenant_id"]
isOneToOne: false
      referencedRelation: "tenants"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "adjust_stock":
{ Args: { "p_client_uuid": string,"p_outlet_id": string,"p_product_id": string,"p_qty_base": number,"p_reason": string,"p_tenant_id": string }; Returns: string
                           },
"close_cash_shift":
{ Args: { "p_client_uuid": string,"p_closing_cash_counted": number,"p_note": string,"p_shift_id": string }; Returns: Json
                           },
"create_stock_opname":
{ Args: { "p_note": string,"p_outlet_id": string,"p_tenant_id": string }; Returns: string
                           },
"create_tenant":
{ Args: { "p_business_type": string,"p_client_uuid": string,"p_name": string,"p_outlet_name": string }; Returns: {
              "outlet_id": string,"tenant_id": string
            }[]
                           },
"has_role":
{ Args: { "roles": (string)[],"t": string }; Returns: boolean
                           },
"is_dev":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"is_member":
{ Args: { "t": string }; Returns: boolean
                           },
"open_cash_shift":
{ Args: { "p_client_uuid": string,"p_opening_cash": number,"p_outlet_id": string,"p_tenant_id": string }; Returns: string
                           },
"post_stock_opname":
{ Args: { "p_opname_id": string }; Returns: number
                           },
"resolve_price":
{ Args: { "p_product_id": string,"p_qty": number,"p_tenant_id": string,"p_tier_id": string,"p_unit_id": string }; Returns: number
                           },
"save_stock_opname_counts":
{ Args: { "p_counts": Json,"p_opname_id": string }; Returns: number
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            
          }
        }
} as const
