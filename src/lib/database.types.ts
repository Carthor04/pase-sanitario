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
    PostgrestVersion: "14.18"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      alerts: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by: string | null
          created_at: string
          escalated_at: string | null
          id: string
          level: number
          pass_id: string
          resolution: string | null
          resolved_at: string | null
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          created_at?: string
          escalated_at?: string | null
          id?: string
          level?: number
          pass_id: string
          resolution?: string | null
          resolved_at?: string | null
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by?: string | null
          created_at?: string
          escalated_at?: string | null
          id?: string
          level?: number
          pass_id?: string
          resolution?: string | null
          resolved_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "alerts_acknowledged_by_fkey"
            columns: ["acknowledged_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alerts_pass_id_fkey"
            columns: ["pass_id"]
            isOneToOne: false
            referencedRelation: "passes"
            referencedColumns: ["id"]
          },
        ]
      }
      destinations: {
        Row: {
          capacity: number | null
          id: string
          kind: string
          label: string
          per_group_limit: number | null
          queue_enabled: boolean
          sex: string | null
          uses_group_slot: boolean
        }
        Insert: {
          capacity?: number | null
          id: string
          kind: string
          label: string
          per_group_limit?: number | null
          queue_enabled?: boolean
          sex?: string | null
          uses_group_slot?: boolean
        }
        Update: {
          capacity?: number | null
          id?: string
          kind?: string
          label?: string
          per_group_limit?: number | null
          queue_enabled?: boolean
          sex?: string | null
          uses_group_slot?: boolean
        }
        Relationships: []
      }
      device_pairings: {
        Row: {
          claimed_at: string | null
          code: string
          created_at: string
          created_by: string
          device_id: string | null
          expires_at: string
          group_id: string
          id: string
          label: string | null
        }
        Insert: {
          claimed_at?: string | null
          code: string
          created_at?: string
          created_by: string
          device_id?: string | null
          expires_at: string
          group_id: string
          id?: string
          label?: string | null
        }
        Update: {
          claimed_at?: string | null
          code?: string
          created_at?: string
          created_by?: string
          device_id?: string | null
          expires_at?: string
          group_id?: string
          id?: string
          label?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "device_pairings_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "device_pairings_device_id_fkey"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "device_pairings_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "device_pairings_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "v_current_class"
            referencedColumns: ["group_id"]
          },
        ]
      }
      device_unlocks: {
        Row: {
          device_id: string
          expires_at: string
          id: string
          lock_reason: string | null
          locked_at: string | null
          staff_id: string
          unlocked_at: string
        }
        Insert: {
          device_id: string
          expires_at: string
          id?: string
          lock_reason?: string | null
          locked_at?: string | null
          staff_id: string
          unlocked_at?: string
        }
        Update: {
          device_id?: string
          expires_at?: string
          id?: string
          lock_reason?: string | null
          locked_at?: string | null
          staff_id?: string
          unlocked_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_unlocks_device_id_fkey"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "device_unlocks_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      devices: {
        Row: {
          auth_user_id: string | null
          created_at: string
          created_by: string | null
          group_id: string
          id: string
          label: string | null
          last_seen_at: string | null
          revoked_at: string | null
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string
          created_by?: string | null
          group_id: string
          id?: string
          label?: string | null
          last_seen_at?: string | null
          revoked_at?: string | null
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string
          created_by?: string | null
          group_id?: string
          id?: string
          label?: string | null
          last_seen_at?: string | null
          revoked_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "devices_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devices_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "devices_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "v_current_class"
            referencedColumns: ["group_id"]
          },
        ]
      }
      groups: {
        Row: {
          id: string
          name: string
          room: string | null
          sort: number | null
        }
        Insert: {
          id?: string
          name: string
          room?: string | null
          sort?: number | null
        }
        Update: {
          id?: string
          name?: string
          room?: string | null
          sort?: number | null
        }
        Relationships: []
      }
      notification_rules: {
        Row: {
          channel: string
          enabled: boolean
          role: string
        }
        Insert: {
          channel: string
          enabled?: boolean
          role: string
        }
        Update: {
          channel?: string
          enabled?: boolean
          role?: string
        }
        Relationships: []
      }
      notifications_outbox: {
        Row: {
          attempts: number
          body: string
          channel: string
          claimed_at: string | null
          created_at: string
          error: string | null
          id: number
          kind: string
          pass_id: string | null
          payload: Json
          recipient_staff_id: string | null
          sent_at: string | null
        }
        Insert: {
          attempts?: number
          body: string
          channel: string
          claimed_at?: string | null
          created_at?: string
          error?: string | null
          id?: number
          kind: string
          pass_id?: string | null
          payload?: Json
          recipient_staff_id?: string | null
          sent_at?: string | null
        }
        Update: {
          attempts?: number
          body?: string
          channel?: string
          claimed_at?: string | null
          created_at?: string
          error?: string | null
          id?: number
          kind?: string
          pass_id?: string | null
          payload?: Json
          recipient_staff_id?: string | null
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_outbox_pass_id_fkey"
            columns: ["pass_id"]
            isOneToOne: false
            referencedRelation: "passes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_outbox_recipient_staff_id_fkey"
            columns: ["recipient_staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      nurse_notes: {
        Row: {
          author_id: string
          body: string
          created_at: string
          id: number
          pass_id: string
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          id?: number
          pass_id: string
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          id?: number
          pass_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "nurse_notes_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nurse_notes_pass_id_fkey"
            columns: ["pass_id"]
            isOneToOne: false
            referencedRelation: "passes"
            referencedColumns: ["id"]
          },
        ]
      }
      pass_events: {
        Row: {
          actor_id: string | null
          at: string
          device_id: string | null
          id: number
          pass_id: string
          payload: Json
          type: string
        }
        Insert: {
          actor_id?: string | null
          at?: string
          device_id?: string | null
          id?: number
          pass_id: string
          payload?: Json
          type: string
        }
        Update: {
          actor_id?: string | null
          at?: string
          device_id?: string | null
          id?: number
          pass_id?: string
          payload?: Json
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "pass_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pass_events_device_id_fkey"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pass_events_pass_id_fkey"
            columns: ["pass_id"]
            isOneToOne: false
            referencedRelation: "passes"
            referencedColumns: ["id"]
          },
        ]
      }
      passes: {
        Row: {
          arrived_at: string | null
          called_at: string | null
          closed_by: string | null
          destination_id: string
          device_id: string | null
          ended_at: string | null
          group_id: string
          id: string
          opened_by: string | null
          period_subject: string | null
          queue_ts: string | null
          release_reason: string | null
          requested_at: string
          source: string
          started_at: string | null
          status: Database["public"]["Enums"]["pass_status"]
          student_id: string
        }
        Insert: {
          arrived_at?: string | null
          called_at?: string | null
          closed_by?: string | null
          destination_id: string
          device_id?: string | null
          ended_at?: string | null
          group_id: string
          id?: string
          opened_by?: string | null
          period_subject?: string | null
          queue_ts?: string | null
          release_reason?: string | null
          requested_at?: string
          source?: string
          started_at?: string | null
          status: Database["public"]["Enums"]["pass_status"]
          student_id: string
        }
        Update: {
          arrived_at?: string | null
          called_at?: string | null
          closed_by?: string | null
          destination_id?: string
          device_id?: string | null
          ended_at?: string | null
          group_id?: string
          id?: string
          opened_by?: string | null
          period_subject?: string | null
          queue_ts?: string | null
          release_reason?: string | null
          requested_at?: string
          source?: string
          started_at?: string | null
          status?: Database["public"]["Enums"]["pass_status"]
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "passes_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passes_destination_id_fkey"
            columns: ["destination_id"]
            isOneToOne: false
            referencedRelation: "destinations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passes_device_id_fkey"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passes_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passes_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "v_current_class"
            referencedColumns: ["group_id"]
          },
          {
            foreignKeyName: "passes_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passes_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      periods: {
        Row: {
          ends: string
          id: string
          starts: string
          weekday: number
        }
        Insert: {
          ends: string
          id?: string
          starts: string
          weekday: number
        }
        Update: {
          ends?: string
          id?: string
          starts?: string
          weekday?: number
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          last_error: string | null
          last_success_at: string | null
          p256dh: string
          staff_id: string
          user_agent: string | null
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          last_error?: string | null
          last_success_at?: string | null
          p256dh: string
          staff_id: string
          user_agent?: string | null
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          last_error?: string | null
          last_success_at?: string | null
          p256dh?: string
          staff_id?: string
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      schedule_entries: {
        Row: {
          group_id: string
          id: string
          period_id: string
          subject: string
          teacher_id: string | null
        }
        Insert: {
          group_id: string
          id?: string
          period_id: string
          subject: string
          teacher_id?: string | null
        }
        Update: {
          group_id?: string
          id?: string
          period_id?: string
          subject?: string
          teacher_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "schedule_entries_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedule_entries_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "v_current_class"
            referencedColumns: ["group_id"]
          },
          {
            foreignKeyName: "schedule_entries_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "schedule_entries_teacher_id_fkey"
            columns: ["teacher_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      security_attempts: {
        Row: {
          at: string
          auth_user_id: string | null
          device_id: string | null
          id: number
          kind: string
          ok: boolean
        }
        Insert: {
          at?: string
          auth_user_id?: string | null
          device_id?: string | null
          id?: number
          kind: string
          ok: boolean
        }
        Update: {
          at?: string
          auth_user_id?: string | null
          device_id?: string | null
          id?: number
          kind?: string
          ok?: boolean
        }
        Relationships: []
      }
      settings: {
        Row: {
          alert_minutes: number
          auto_lock_after_class_minutes: number
          confirm_turn_minutes: number
          escalate_minutes: number
          id: number
          pairing_code_minutes: number
          pin_lockout_seconds: number
          pin_max_attempts: number
          review_alerts_threshold: number
          review_exits_threshold: number
          sheets_daily_export_time: string
          sheets_spreadsheet_id: string | null
          undo_seconds: number
          unlock_without_class_minutes: number
          vapid_public_key: string | null
          whatsapp_enabled: boolean
        }
        Insert: {
          alert_minutes?: number
          auto_lock_after_class_minutes?: number
          confirm_turn_minutes?: number
          escalate_minutes?: number
          id?: number
          pairing_code_minutes?: number
          pin_lockout_seconds?: number
          pin_max_attempts?: number
          review_alerts_threshold?: number
          review_exits_threshold?: number
          sheets_daily_export_time?: string
          sheets_spreadsheet_id?: string | null
          undo_seconds?: number
          unlock_without_class_minutes?: number
          vapid_public_key?: string | null
          whatsapp_enabled?: boolean
        }
        Update: {
          alert_minutes?: number
          auto_lock_after_class_minutes?: number
          confirm_turn_minutes?: number
          escalate_minutes?: number
          id?: number
          pairing_code_minutes?: number
          pin_lockout_seconds?: number
          pin_max_attempts?: number
          review_alerts_threshold?: number
          review_exits_threshold?: number
          sheets_daily_export_time?: string
          sheets_spreadsheet_id?: string | null
          undo_seconds?: number
          unlock_without_class_minutes?: number
          vapid_public_key?: string | null
          whatsapp_enabled?: boolean
        }
        Relationships: []
      }
      staff: {
        Row: {
          active: boolean
          auth_user_id: string | null
          created_at: string
          email: string
          full_name: string
          id: string
          pin_set_at: string | null
          roles: string[]
          whatsapp: string | null
        }
        Insert: {
          active?: boolean
          auth_user_id?: string | null
          created_at?: string
          email: string
          full_name: string
          id?: string
          pin_set_at?: string | null
          roles: string[]
          whatsapp?: string | null
        }
        Update: {
          active?: boolean
          auth_user_id?: string | null
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          pin_set_at?: string | null
          roles?: string[]
          whatsapp?: string | null
        }
        Relationships: []
      }
      staff_pins: {
        Row: {
          pin_hash: string
          staff_id: string
          updated_at: string
        }
        Insert: {
          pin_hash: string
          staff_id: string
          updated_at?: string
        }
        Update: {
          pin_hash?: string
          staff_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_pins_staff_id_fkey"
            columns: ["staff_id"]
            isOneToOne: true
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
        ]
      }
      students: {
        Row: {
          active: boolean
          created_at: string
          full_name: string
          group_id: string
          id: string
          list_number: number
          rfid_tag: string | null
          sex: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          full_name: string
          group_id: string
          id?: string
          list_number: number
          rfid_tag?: string | null
          sex: string
        }
        Update: {
          active?: boolean
          created_at?: string
          full_name?: string
          group_id?: string
          id?: string
          list_number?: number
          rfid_tag?: string | null
          sex?: string
        }
        Relationships: [
          {
            foreignKeyName: "students_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "students_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "v_current_class"
            referencedColumns: ["group_id"]
          },
        ]
      }
    }
    Views: {
      v_current_class: {
        Row: {
          ends: string | null
          group_id: string | null
          group_name: string | null
          period_id: string | null
          starts: string | null
          subject: string | null
          teacher_id: string | null
          teacher_name: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      acknowledge_alert: { Args: { p_alert_id: string }; Returns: Json }
      add_nurse_note: {
        Args: { p_body: string; p_pass_id: string }
        Returns: undefined
      }
      cancel_pass: { Args: { p_pass_id: string }; Returns: Json }
      cede_turn: { Args: { p_pass_id: string }; Returns: Json }
      claim_device_pairing: { Args: { p_code: string }; Returns: Json }
      claim_push_batch: {
        Args: { p_limit?: number }
        Returns: {
          body: string
          id: number
          payload: Json
          recipient_staff_id: string
          subscriptions: Json
        }[]
      }
      classes_at: {
        Args: { p_at: string }
        Returns: {
          ends: string
          group_id: string
          period_id: string
          starts: string
          subject: string
          teacher_id: string
          teacher_name: string
        }[]
      }
      clear_staff_pin: { Args: { p_staff_id: string }; Returns: undefined }
      confirm_turn: { Args: { p_pass_id: string }; Returns: Json }
      create_device_pairing: {
        Args: { p_group_id: string; p_label?: string }
        Returns: Json
      }
      current_actor: { Args: never; Returns: Json }
      delete_push_subscription: {
        Args: { p_endpoint: string }
        Returns: undefined
      }
      device_session: { Args: never; Returns: Json }
      finish_push: {
        Args: {
          p_dead_endpoints: string[]
          p_error: string
          p_id: number
          p_ok_endpoints: string[]
        }
        Returns: undefined
      }
      group_board: { Args: { p_group_id: string }; Returns: Json }
      import_groups: { Args: { p_rows: Json }; Returns: Json }
      import_schedule: { Args: { p_rows: Json }; Returns: Json }
      import_staff: { Args: { p_rows: Json }; Returns: Json }
      import_students: { Args: { p_rows: Json }; Returns: Json }
      live_board: { Args: never; Returns: Json }
      lock_device: { Args: never; Returns: undefined }
      mark_arrived: { Args: { p_pass_id: string }; Returns: Json }
      mark_returned: { Args: { p_pass_id: string }; Returns: Json }
      me: { Args: never; Returns: Json }
      my_alerts: { Args: never; Returns: Json }
      my_groups: {
        Args: { p_at?: string }
        Returns: {
          ends: string
          group_id: string
          name: string
          rank: number
          room: string
          starts: string
          subject: string
          teacher_name: string
        }[]
      }
      nurse_today: { Args: never; Returns: Json }
      push_config: { Args: never; Returns: Json }
      release_pass: {
        Args: { p_pass_id: string; p_reason: string }
        Returns: Json
      }
      request_pass: {
        Args: { p_kind: string; p_student_id: string }
        Returns: Json
      }
      revoke_device: { Args: { p_device_id: string }; Returns: undefined }
      save_push_subscription: {
        Args: {
          p_auth: string
          p_endpoint: string
          p_p256dh: string
          p_user_agent: string
        }
        Returns: undefined
      }
      send_test_push: { Args: never; Returns: Json }
      set_my_pin: { Args: { p_pin: string }; Returns: Json }
      set_staff_pin: {
        Args: { p_pin: string; p_staff_id: string }
        Returns: Json
      }
      undo_last: { Args: { p_pass_id: string }; Returns: Json }
      unlock_device: { Args: { p_pin: string }; Returns: Json }
    }
    Enums: {
      pass_status:
        | "group_wait"
        | "queued"
        | "called"
        | "out"
        | "arrived"
        | "returned"
        | "released"
        | "cancelled"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      pass_status: [
        "group_wait",
        "queued",
        "called",
        "out",
        "arrived",
        "returned",
        "released",
        "cancelled",
      ],
    },
  },
} as const
