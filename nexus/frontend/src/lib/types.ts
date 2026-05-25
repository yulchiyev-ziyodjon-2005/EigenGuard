export interface Me {
  id: string
  username: string
  email: string
  full_name: string | null
  role: string
  is_admin: boolean
  is_superadmin: boolean
  tenant_id: string
  tenant_subdomain: string
  tenant_name: string
  deployment_mode: string
}

export interface Tenant {
  id: string
  name: string
  subdomain: string
  deployment_mode: string
  is_active: boolean
  contact_email: string | null
  user_count: number
  measurement_count: number
  device_count?: number
  active_license_count?: number
  created_at: string
}

export interface UserBrief {
  id: string
  username: string
  email: string
  full_name: string | null
  role: string
  is_admin: boolean
  is_active: boolean
  created_at: string
  last_login_at: string | null
}

export interface DeviceBrief {
  id: string
  device_identifier: string
  platform: string
  device_name: string | null
  is_active: boolean
  last_seen_at: string
  created_at: string
}

export interface LicenseBrief {
  id: string
  key: string
  issued_at: string
  expires_at: string
  max_devices: number
  max_users: number
  is_revoked: boolean
  is_expired: boolean
  features: Record<string, unknown> | null
}

export interface MeasurementBrief {
  id: string
  timestamp: string
  risk_percent: number
  risk_level: string
  frequency_hz: number
  amplitude_mm: number
  source: string
  device_id: string | null
}

export interface TenantDetail {
  tenant: Tenant
  users: UserBrief[]
  devices: DeviceBrief[]
  licenses: LicenseBrief[]
  recent_measurements: MeasurementBrief[]
}

export interface License {
  id: string
  tenant_id: string
  tenant_subdomain: string | null
  tenant_name: string | null
  key: string
  issued_at: string
  expires_at: string
  max_devices: number
  max_users: number
  features: Record<string, unknown>
  last_validated_at: string | null
  is_revoked: boolean
  is_expired: boolean
  is_valid: boolean
  revocation_reason: string | null
}

export type AuditAction =
  | 'tenant_create'
  | 'tenant_update'
  | 'tenant_delete'
  | 'license_create'
  | 'license_update'
  | 'license_renew'
  | 'license_revoke'
  | 'license_delete'

export interface AuditLog {
  id: string
  actor_user_id: string | null
  actor_email: string
  target_tenant_id: string | null
  target_tenant_subdomain: string | null
  action: AuditAction
  entity_type: string
  entity_id: string | null
  payload: { before?: Record<string, unknown>; after?: Record<string, unknown> } | null
  ip_address: string | null
  user_agent: string | null
  created_at: string
}

export interface AuditLogPage {
  total: number
  items: AuditLog[]
}

export interface User {
  id: string
  username: string
  email: string
  full_name: string | null
  role: string
  is_admin: boolean
  is_active: boolean
  created_at: string
  last_login_at: string | null
}

export interface Device {
  id: string
  device_identifier: string
  platform: string
  device_name: string | null
  user_id: string | null
  is_active: boolean
  is_online: boolean
  measurement_count: number
  last_seen_at: string
  last_risk_percent: number | null
  last_risk_level: string | null
  last_source: string | null
  created_at: string
}

export interface Measurement {
  id: string
  local_id: number | null
  device_id: string | null
  source: 'mobile' | 'edge' | 'fused'
  timestamp: string
  risk_percent: number
  frequency_hz: number
  amplitude_mm: number
  risk_level: string
  fusion_confidence: number | null
  received_at: string
}

export interface PredictionAnalysis {
  device_id: string | null
  timestamp: string
  health_index: number
  anomaly_probability: number
  hours_to_critical: number | null
  risk_level: string
  verdict: string
  recommendations: string[]
  created_at: string
}

export interface DashboardWsMessage {
  kind: 'hello' | 'analysis' | 'pong'
  data?: PredictionAnalysis
  channel?: string
  tenant?: string
}

export type CommandType =
  | 'notify'
  | 'start_scan'
  | 'stop_scan'
  | 'enable_demo_mode'
  | 'disable_demo_mode'
  | 'set_material'
  | 'take_snapshot'
  | 'sync_now'
  | 'custom'

export type CommandStatus = 'pending' | 'delivered' | 'acknowledged' | 'failed' | 'expired'

export interface Command {
  id: string
  device_id: string
  command_type: CommandType
  payload: Record<string, unknown> | null
  status: CommandStatus
  error_message: string | null
  result_payload: Record<string, unknown> | null
  created_at: string
  delivered_at: string | null
  acknowledged_at: string | null
  expires_at: string
}
