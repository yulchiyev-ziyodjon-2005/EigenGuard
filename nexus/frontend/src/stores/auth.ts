import { defineStore } from 'pinia'
import { api, setTenantHeader } from '@/lib/api'
import type { Me } from '@/lib/types'

export type AuthScope = 'tenant' | 'superadmin'

interface AuthState {
  user: Me | null
  initialized: boolean
  scope: AuthScope | null
  loading: boolean
  error: string | null
}

export const useAuthStore = defineStore('auth', {
  state: (): AuthState => ({
    user: null,
    initialized: false,
    scope: null,
    loading: false,
    error: null,
  }),
  actions: {
    async bootstrap(scope: AuthScope = 'tenant', force = false) {
      if (this.initialized && this.scope === scope && !force) return
      try {
        const { data } = await api.get<Me>('/api/v1/auth/me', {
          headers: {
            'X-EigenGuard-Auth-Scope': scope,
          },
        })
        if (scope === 'superadmin' && !data.is_superadmin) throw new Error('Wrong auth scope')
        if (scope === 'tenant' && data.is_superadmin) throw new Error('Wrong auth scope')
        this.user = data
        setTenantHeader(data.tenant_subdomain)
      } catch {
        this.user = null
        setTenantHeader(null)
      } finally {
        this.initialized = true
        this.scope = scope
      }
    },
    async login(username: string, password: string) {
      this.loading = true
      this.error = null
      try {
        const { data } = await api.post<Me>('/api/v1/auth/login', {
          username: username.trim(),
          password,
        })
        this.user = data
        this.scope = 'tenant'
        setTenantHeader(data.tenant_subdomain)
      } catch (e: any) {
        this.error = e?.response?.data?.detail || 'Login xato'
        this.user = null
        throw e
      } finally {
        this.loading = false
      }
    },
    async superadminLogin(username: string, password: string) {
      this.loading = true
      this.error = null
      try {
        const { data } = await api.post<Me>('/api/v1/auth/superadmin/login', {
          username: username.trim(),
          password,
        })
        this.user = data
        this.scope = 'superadmin'
        setTenantHeader(data.tenant_subdomain)
      } catch (e: any) {
        this.error = e?.response?.data?.detail || 'Superadmin login xato'
        this.user = null
        throw e
      } finally {
        this.loading = false
      }
    },
    async logout() {
      try {
        await api.post('/api/v1/auth/logout')
      } catch {
        // ignore
      }
      this.user = null
      this.scope = null
      this.initialized = false
      setTenantHeader(null)
    },
    clearError() {
      this.error = null
    },
  },
})
