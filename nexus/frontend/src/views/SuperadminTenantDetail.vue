<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/lib/api'
import type { LicenseBrief, TenantDetail } from '@/lib/types'

type DetailTab = 'overview' | 'users' | 'devices' | 'licenses' | 'measurements' | 'settings'

const route = useRoute()
const router = useRouter()
const detail = ref<TenantDetail | null>(null)
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const activeTab = ref<DetailTab>('overview')

const editForm = reactive({
  name: '',
  deployment_mode: 'cloud',
  contact_email: '',
  is_active: true,
})

const tenantId = computed(() => String(route.params.id))
const activeLicenses = computed(() =>
  (detail.value?.licenses ?? []).filter((license) => !license.is_revoked && !license.is_expired),
)
const expiredLicenses = computed(() =>
  (detail.value?.licenses ?? []).filter((license) => license.is_revoked || license.is_expired),
)
const adminUsers = computed(() => (detail.value?.users ?? []).filter((user) => user.is_admin))
const activeUsers = computed(() => (detail.value?.users ?? []).filter((user) => user.is_active))
const activeDevices = computed(() => (detail.value?.devices ?? []).filter((device) => device.is_active))
const avgRisk = computed(() => {
  const rows = detail.value?.recent_measurements ?? []
  if (!rows.length) return 0
  return rows.reduce((sum, item) => sum + item.risk_percent, 0) / rows.length
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const { data } = await api.get<TenantDetail>(`/api/v1/superadmin/tenants/${tenantId.value}`)
    detail.value = data
    Object.assign(editForm, {
      name: data.tenant.name,
      deployment_mode: data.tenant.deployment_mode,
      contact_email: data.tenant.contact_email ?? '',
      is_active: data.tenant.is_active,
    })
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Tenant topilmadi'
  } finally {
    loading.value = false
  }
}

async function saveSettings() {
  error.value = null
  saving.value = true
  try {
    await api.patch(`/api/v1/superadmin/tenants/${tenantId.value}`, {
      name: editForm.name.trim(),
      deployment_mode: editForm.deployment_mode,
      contact_email: editForm.contact_email.trim() || null,
      is_active: editForm.is_active,
    })
    await load()
    activeTab.value = 'overview'
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Tenant sozlamalarini saqlab bo'lmadi"
  } finally {
    saving.value = false
  }
}

async function toggleActive() {
  if (!detail.value) return
  error.value = null
  try {
    await api.patch(`/api/v1/superadmin/tenants/${tenantId.value}`, {
      is_active: !detail.value.tenant.is_active,
    })
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Holatni yangilab bo\'lmadi'
  }
}

function healthScore() {
  const tenant = detail.value?.tenant
  if (!tenant) return 0
  let score = 100
  if (!tenant.is_active) score -= 45
  if (!activeLicenses.value.length) score -= 30
  if (!adminUsers.value.length) score -= 15
  if (!activeDevices.value.length) score -= 10
  return Math.max(0, score)
}

function healthMeta() {
  const tenant = detail.value?.tenant
  if (!tenant?.is_active) return { label: 'Suspended', cls: 'text-slate-300', bar: 'bg-slate-500' }
  if (!activeLicenses.value.length) return { label: 'License required', cls: 'text-rose-300', bar: 'bg-rose-400' }
  if (healthScore() < 80) return { label: 'Setup incomplete', cls: 'text-amber-300', bar: 'bg-amber-300' }
  return { label: 'Operational', cls: 'text-emerald-300', bar: 'bg-emerald-300' }
}

function modeClass(mode: string) {
  if (mode === 'air_gapped') return 'border-rose-400/30 bg-rose-500/15 text-rose-300'
  if (mode === 'on_premise') return 'border-amber-400/30 bg-amber-500/15 text-amber-300'
  if (mode === 'superadmin') return 'border-amber-300/40 bg-amber-300/15 text-amber-200'
  return 'border-cyan-400/30 bg-cyan-500/15 text-cyan-300'
}

function userRoleClass(role: string) {
  if (role === 'superadmin' || role === 'tenant_admin') {
    return 'border-amber-400/30 bg-amber-500/15 text-amber-300'
  }
  if (role === 'engineer') return 'border-cyan-400/30 bg-cyan-500/15 text-cyan-300'
  if (role === 'operator') return 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300'
  return 'border-slate-600 bg-slate-800 text-slate-300'
}

function licenseStatus(license: LicenseBrief) {
  if (license.is_revoked) return { label: 'Revoked', cls: 'border-rose-400/30 bg-rose-500/15 text-rose-300' }
  if (license.is_expired) return { label: 'Expired', cls: 'border-amber-400/30 bg-amber-500/15 text-amber-300' }
  return { label: 'Active', cls: 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300' }
}

function riskClass(level: string) {
  const normalized = level.toUpperCase()
  if (normalized === 'CRITICAL') return 'border-rose-400/30 bg-rose-500/15 text-rose-300'
  if (normalized === 'HIGH') return 'border-orange-400/30 bg-orange-500/15 text-orange-300'
  if (normalized === 'MEDIUM') return 'border-amber-400/30 bg-amber-500/15 text-amber-300'
  return 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300'
}

function daysLeft(iso: string) {
  const days = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000)
  if (days < 0) return `${Math.abs(days)} kun oldin tugagan`
  if (days === 0) return 'Bugun tugaydi'
  return `${days} kun qoldi`
}

watch(() => route.params.id, load)
onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <button
        @click="router.push({ name: 'tenants' })"
        class="rounded border border-slate-700 px-3 py-2 text-sm text-slate-300 hover:bg-slate-800"
      >
        Tenants ro'yxati
      </button>
      <div class="flex flex-wrap gap-2">
        <button
          @click="load"
          class="rounded border border-slate-700 px-3 py-2 text-sm font-bold text-slate-300 hover:bg-slate-800"
        >
          Yangilash
        </button>
        <button
          v-if="detail"
          @click="toggleActive"
          :disabled="detail.tenant.deployment_mode === 'superadmin'"
          class="rounded border px-3 py-2 text-sm font-bold disabled:cursor-not-allowed disabled:opacity-40"
          :class="detail.tenant.is_active
            ? 'border-slate-600 bg-slate-800 text-slate-300 hover:bg-slate-700'
            : 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200 hover:bg-emerald-500/20'"
        >
          {{ detail.tenant.is_active ? 'Suspend tenant' : 'Activate tenant' }}
        </button>
      </div>
    </div>

    <div
      v-if="error"
      class="rounded border border-rose-500/40 bg-rose-500/10 px-4 py-3 text-sm text-rose-300"
    >
      {{ error }}
    </div>

    <div v-if="loading" class="eg-panel p-12 text-center text-slate-500">Yuklanmoqda...</div>

    <template v-else-if="detail">
      <section class="eg-panel overflow-hidden">
        <div class="border-b border-slate-800 p-6">
          <div class="flex flex-wrap items-start justify-between gap-5">
            <div class="min-w-0">
              <div class="mb-3 flex flex-wrap items-center gap-2">
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="modeClass(detail.tenant.deployment_mode)">
                  {{ detail.tenant.deployment_mode }}
                </span>
                <span
                  class="rounded border px-2 py-1 text-[11px] font-bold uppercase"
                  :class="detail.tenant.is_active
                    ? 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300'
                    : 'border-slate-600 bg-slate-800 text-slate-300'"
                >
                  {{ detail.tenant.is_active ? 'Active' : 'Inactive' }}
                </span>
                <span class="rounded border border-slate-700 bg-slate-900 px-2 py-1 text-[11px] font-bold uppercase" :class="healthMeta().cls">
                  {{ healthMeta().label }}
                </span>
              </div>
              <h1 class="truncate text-3xl font-black text-slate-50">{{ detail.tenant.name }}</h1>
              <p class="mt-2 font-mono text-sm text-cyan-300">{{ detail.tenant.subdomain }}.eigenguard.uz</p>
              <p class="mt-1 text-sm text-slate-500">{{ detail.tenant.contact_email || 'Kontakt email kiritilmagan' }}</p>
            </div>
            <div class="w-full max-w-xs">
              <div class="flex items-end justify-between">
                <div>
                  <div class="font-mono text-4xl font-black text-slate-50">{{ healthScore() }}</div>
                  <div class="text-[10px] uppercase tracking-wider text-slate-500">Tenant health score</div>
                </div>
                <div class="text-right text-sm font-bold" :class="healthMeta().cls">{{ healthMeta().label }}</div>
              </div>
              <div class="mt-4 h-2 overflow-hidden rounded bg-slate-800">
                <div class="h-full rounded" :class="healthMeta().bar" :style="{ width: `${healthScore()}%` }" />
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-2 divide-x divide-y divide-slate-800 sm:grid-cols-4 sm:divide-y-0">
          <div class="p-5">
            <div class="font-mono text-2xl font-black text-cyan-200">{{ detail.tenant.user_count }}</div>
            <div class="text-[10px] uppercase text-slate-500">Users</div>
            <div class="mt-1 text-xs text-slate-500">{{ adminUsers.length }} admin</div>
          </div>
          <div class="p-5">
            <div class="font-mono text-2xl font-black text-emerald-200">{{ detail.tenant.device_count ?? 0 }}</div>
            <div class="text-[10px] uppercase text-slate-500">Devices</div>
            <div class="mt-1 text-xs text-slate-500">{{ activeDevices.length }} active</div>
          </div>
          <div class="p-5">
            <div class="font-mono text-2xl font-black text-amber-200">{{ activeLicenses.length }}</div>
            <div class="text-[10px] uppercase text-slate-500">Active licenses</div>
            <div class="mt-1 text-xs text-slate-500">{{ expiredLicenses.length }} expired/revoked</div>
          </div>
          <div class="p-5">
            <div class="font-mono text-2xl font-black text-rose-200">{{ avgRisk.toFixed(0) }}%</div>
            <div class="text-[10px] uppercase text-slate-500">Avg recent risk</div>
            <div class="mt-1 text-xs text-slate-500">{{ detail.recent_measurements.length }} recent signals</div>
          </div>
        </div>
      </section>

      <nav class="flex gap-2 overflow-x-auto">
        <button
          v-for="tab in ['overview', 'users', 'devices', 'licenses', 'measurements', 'settings'] as DetailTab[]"
          :key="tab"
          @click="activeTab = tab"
          class="rounded border px-4 py-2 text-sm font-bold capitalize"
          :class="activeTab === tab
            ? 'border-amber-300/50 bg-amber-300 text-slate-950'
            : 'border-slate-700 bg-slate-900 text-slate-300 hover:bg-slate-800'"
        >
          {{ tab }}
        </button>
      </nav>

      <section v-if="activeTab === 'overview'" class="grid gap-5 xl:grid-cols-[1fr_0.8fr]">
        <div class="eg-panel p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">Operational checklist</h2>
          <div class="mt-5 space-y-3">
            <div class="flex items-center justify-between rounded border border-slate-800 bg-slate-950/60 p-3">
              <span class="text-sm text-slate-300">Tenant active</span>
              <span :class="detail.tenant.is_active ? 'text-emerald-300' : 'text-rose-300'">
                {{ detail.tenant.is_active ? 'OK' : 'Blocked' }}
              </span>
            </div>
            <div class="flex items-center justify-between rounded border border-slate-800 bg-slate-950/60 p-3">
              <span class="text-sm text-slate-300">At least one admin</span>
              <span :class="adminUsers.length ? 'text-emerald-300' : 'text-rose-300'">
                {{ adminUsers.length ? `${adminUsers.length} admin` : 'Missing' }}
              </span>
            </div>
            <div class="flex items-center justify-between rounded border border-slate-800 bg-slate-950/60 p-3">
              <span class="text-sm text-slate-300">Active license</span>
              <span :class="activeLicenses.length ? 'text-emerald-300' : 'text-rose-300'">
                {{ activeLicenses.length ? `${activeLicenses.length} active` : 'Required' }}
              </span>
            </div>
            <div class="flex items-center justify-between rounded border border-slate-800 bg-slate-950/60 p-3">
              <span class="text-sm text-slate-300">Registered devices</span>
              <span :class="activeDevices.length ? 'text-emerald-300' : 'text-amber-300'">
                {{ activeDevices.length ? `${activeDevices.length} active` : 'No active device' }}
              </span>
            </div>
          </div>
        </div>

        <div class="eg-panel p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">Quick actions</h2>
          <div class="mt-5 grid gap-3">
            <router-link
              :to="{ name: 'licenses' }"
              class="rounded border border-amber-400/30 bg-amber-500/10 px-4 py-3 text-sm font-bold text-amber-200 hover:bg-amber-500/20"
            >
              License berish yoki yangilash
            </router-link>
            <button
              @click="activeTab = 'settings'"
              class="rounded border border-cyan-400/30 bg-cyan-500/10 px-4 py-3 text-left text-sm font-bold text-cyan-200 hover:bg-cyan-500/20"
            >
              Tenant sozlamalarini tahrirlash
            </button>
            <router-link
              :to="{ name: 'audit-logs' }"
              class="rounded border border-slate-700 bg-slate-900 px-4 py-3 text-sm font-bold text-slate-300 hover:bg-slate-800"
            >
              Audit loglarni ko'rish
            </router-link>
          </div>
        </div>
      </section>

      <section v-if="activeTab === 'users'" class="eg-panel overflow-hidden">
        <table class="w-full text-sm" v-if="detail.users.length">
          <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
            <tr>
              <th class="px-4 py-3 text-left">User</th>
              <th class="px-4 py-3 text-center">Role</th>
              <th class="px-4 py-3 text-center">Status</th>
              <th class="px-4 py-3 text-left">Created</th>
              <th class="px-4 py-3 text-left">Last login</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="user in detail.users" :key="user.id" class="border-t border-slate-800 hover:bg-slate-800/30">
              <td class="px-4 py-3">
                <div class="font-mono text-xs text-cyan-300">{{ user.username }}</div>
                <div class="mt-1 font-mono text-xs text-slate-400">{{ user.email }}</div>
                <div class="mt-1 text-xs text-slate-500">{{ user.full_name || 'FIO kiritilmagan' }}</div>
              </td>
              <td class="px-4 py-3 text-center">
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="userRoleClass(user.role)">
                  {{ user.role }}
                </span>
              </td>
              <td class="px-4 py-3 text-center">
                <span :class="user.is_active ? 'text-emerald-300' : 'text-slate-500'">
                  {{ user.is_active ? 'Active' : 'Inactive' }}
                </span>
              </td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">{{ new Date(user.created_at).toLocaleDateString('uz-UZ') }}</td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">
                {{ user.last_login_at ? new Date(user.last_login_at).toLocaleString('uz-UZ') : 'No login' }}
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="activeTab === 'devices'" class="eg-panel overflow-hidden">
        <table class="w-full text-sm" v-if="detail.devices.length">
          <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
            <tr>
              <th class="px-4 py-3 text-left">Device</th>
              <th class="px-4 py-3 text-center">Platform</th>
              <th class="px-4 py-3 text-center">Status</th>
              <th class="px-4 py-3 text-left">Last seen</th>
              <th class="px-4 py-3 text-left">Created</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="device in detail.devices" :key="device.id" class="border-t border-slate-800 hover:bg-slate-800/30">
              <td class="px-4 py-3">
                <div class="font-mono text-xs text-cyan-300">{{ device.device_identifier }}</div>
                <div class="mt-1 text-xs text-slate-500">{{ device.device_name || 'Nomsiz qurilma' }}</div>
              </td>
              <td class="px-4 py-3 text-center font-mono text-xs text-slate-400">{{ device.platform }}</td>
              <td class="px-4 py-3 text-center">
                <span :class="device.is_active ? 'text-emerald-300' : 'text-slate-500'">
                  {{ device.is_active ? 'Active' : 'Inactive' }}
                </span>
              </td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">{{ new Date(device.last_seen_at).toLocaleString('uz-UZ') }}</td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">{{ new Date(device.created_at).toLocaleDateString('uz-UZ') }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="p-10 text-center text-slate-500">Qurilmalar hali ulanmagan.</div>
      </section>

      <section v-if="activeTab === 'licenses'" class="grid gap-4 lg:grid-cols-2">
        <div v-for="license in detail.licenses" :key="license.id" class="eg-panel p-5">
          <div class="flex items-start justify-between gap-3">
            <div>
              <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="licenseStatus(license).cls">
                {{ licenseStatus(license).label }}
              </span>
              <div class="mt-4 font-mono text-sm text-slate-300">{{ license.key.slice(0, 24) }}...</div>
            </div>
            <div class="text-right text-xs text-slate-500">{{ daysLeft(license.expires_at) }}</div>
          </div>
          <div class="mt-5 grid grid-cols-2 gap-3">
            <div class="rounded border border-slate-800 bg-slate-950/60 p-3">
              <div class="font-mono text-xl font-black text-cyan-200">{{ license.max_devices }}</div>
              <div class="text-[10px] uppercase text-slate-500">Max devices</div>
            </div>
            <div class="rounded border border-slate-800 bg-slate-950/60 p-3">
              <div class="font-mono text-xl font-black text-amber-200">{{ license.max_users }}</div>
              <div class="text-[10px] uppercase text-slate-500">Max users</div>
            </div>
          </div>
        </div>
        <div v-if="!detail.licenses.length" class="eg-panel p-10 text-center text-slate-500 lg:col-span-2">
          License mavjud emas.
        </div>
      </section>

      <section v-if="activeTab === 'measurements'" class="eg-panel overflow-hidden">
        <table class="w-full text-sm" v-if="detail.recent_measurements.length">
          <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
            <tr>
              <th class="px-4 py-3 text-left">Time</th>
              <th class="px-4 py-3 text-right">Risk</th>
              <th class="px-4 py-3 text-center">Level</th>
              <th class="px-4 py-3 text-right">Frequency</th>
              <th class="px-4 py-3 text-right">Amplitude</th>
              <th class="px-4 py-3 text-left">Device</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in detail.recent_measurements" :key="item.id" class="border-t border-slate-800 hover:bg-slate-800/30">
              <td class="px-4 py-3 font-mono text-xs text-slate-500">{{ new Date(item.timestamp).toLocaleString('uz-UZ') }}</td>
              <td class="px-4 py-3 text-right font-mono">{{ item.risk_percent.toFixed(1) }}%</td>
              <td class="px-4 py-3 text-center">
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="riskClass(item.risk_level)">
                  {{ item.risk_level }}
                </span>
              </td>
              <td class="px-4 py-3 text-right font-mono">{{ item.frequency_hz.toFixed(1) }} Hz</td>
              <td class="px-4 py-3 text-right font-mono">{{ item.amplitude_mm.toFixed(2) }} mm</td>
              <td class="px-4 py-3 font-mono text-xs text-cyan-300">{{ item.device_id || 'unknown' }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else class="p-10 text-center text-slate-500">Measurement hali yo'q.</div>
      </section>

      <section v-if="activeTab === 'settings'" class="eg-panel p-5">
        <h2 class="text-lg font-black text-slate-50">Tenant sozlamalari</h2>
        <p class="mt-1 text-sm text-slate-500">Bu o'zgarishlar audit logga yoziladi.</p>

        <form @submit.prevent="saveSettings" class="mt-5 grid gap-4 md:grid-cols-2">
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Tenant nomi</label>
            <input v-model="editForm.name" required class="eg-input" />
          </div>
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Contact email</label>
            <input v-model="editForm.contact_email" type="email" class="eg-input" />
          </div>
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Deployment mode</label>
            <select v-model="editForm.deployment_mode" class="eg-input" :disabled="detail.tenant.deployment_mode === 'superadmin'">
              <option value="cloud">Cloud SaaS</option>
              <option value="on_premise">On-premise</option>
              <option value="air_gapped">Air-gapped</option>
            </select>
          </div>
          <label class="flex items-center gap-3 rounded border border-slate-800 bg-slate-950/60 px-4 py-3">
            <input v-model="editForm.is_active" type="checkbox" class="h-4 w-4 accent-amber-300" :disabled="detail.tenant.deployment_mode === 'superadmin'" />
            <span>
              <span class="block text-sm font-bold text-slate-200">Tenant active</span>
              <span class="block text-xs text-slate-500">Inactive tenant userlari tizimga kira olmaydi.</span>
            </span>
          </label>
          <div class="md:col-span-2 flex justify-end gap-2">
            <button type="button" @click="load" class="rounded border border-slate-700 px-4 py-2 text-sm text-slate-300 hover:bg-slate-800">
              Bekor
            </button>
            <button type="submit" :disabled="saving" class="rounded bg-amber-300 px-5 py-2 text-sm font-black text-slate-950 hover:bg-amber-200 disabled:bg-slate-700 disabled:text-slate-400">
              {{ saving ? 'Saqlanmoqda...' : 'Saqlash' }}
            </button>
          </div>
        </form>
      </section>
    </template>
  </div>
</template>
