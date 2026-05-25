import axios, { type AxiosInstance } from 'axios'

const baseURL = (import.meta.env.VITE_API_BASE as string | undefined) || ''

export const api: AxiosInstance = axios.create({
  baseURL,
  withCredentials: true,
  timeout: 15000,
})

const TENANT_KEY = 'eigenguard.tenant_subdomain'

let tenantSubdomain: string | null = localStorage.getItem(TENANT_KEY)

export function setTenantHeader(subdomain: string | null) {
  tenantSubdomain = subdomain
  if (subdomain) {
    localStorage.setItem(TENANT_KEY, subdomain)
  } else {
    localStorage.removeItem(TENANT_KEY)
  }
}

export function getTenantHeader(): string | null {
  return tenantSubdomain
}

export function apiWebSocketUrl(path: string): string {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  const source = /^https?:\/\//.test(baseURL) ? baseURL : window.location.origin
  const url = new URL(normalizedPath, source)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  return url.toString()
}

api.interceptors.request.use((config) => {
  const requestUrl = String(config.url || '')
  const isSuperadminContext =
    window.location.pathname.startsWith('/superadmin') ||
    requestUrl.startsWith('/api/v1/superadmin') ||
    requestUrl.startsWith('/api/v1/auth/superadmin')
  if (isSuperadminContext) {
    config.headers.set('X-EigenGuard-Auth-Scope', 'superadmin')
  }
  if (tenantSubdomain) {
    config.headers.set('X-EigenGuard-Tenant', tenantSubdomain)
  }
  return config
})
