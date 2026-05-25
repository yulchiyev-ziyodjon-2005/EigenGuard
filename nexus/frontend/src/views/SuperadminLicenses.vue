<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { api } from '@/lib/api'
import type { License, Tenant } from '@/lib/types'

const licenses = ref<License[]>([])
const tenants = ref<Tenant[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showCreate = ref(false)
const filterTenantId = ref('')
const onlyActive = ref(false)
const renewId = ref<string | null>(null)
const revokeId = ref<string | null>(null)
const revokeReason = ref('')

const renewForm = reactive({ duration_days: 365, reset_from_now: false })
const createForm = reactive({
  tenant_id: '',
  duration_days: 365,
  max_devices: 10,
  max_users: 5,
  custom_ai: false,
  multi_site: false,
  alert_routing: true,
})

const activeLicenses = computed(() => licenses.value.filter((l) => l.is_valid && !l.is_revoked))
const revokedLicenses = computed(() => licenses.value.filter((l) => l.is_revoked))
const expiredLicenses = computed(() => licenses.value.filter((l) => l.is_expired && !l.is_revoked))
const expiringSoon = computed(() =>
  licenses.value.filter((license) => {
    const days = Math.ceil((new Date(license.expires_at).getTime() - Date.now()) / 86400000)
    return !license.is_revoked && days >= 0 && days <= 30
  }),
)

async function load() {
  loading.value = true
  error.value = null
  try {
    const params: Record<string, string | boolean> = {}
    if (filterTenantId.value) params.tenant_id = filterTenantId.value
    if (onlyActive.value) params.only_active = true
    const { data } = await api.get<License[]>('/api/v1/superadmin/licenses', { params })
    licenses.value = data
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Litsenziyalar yuklanmadi"
  } finally {
    loading.value = false
  }
}

async function loadTenants() {
  const { data } = await api.get<Tenant[]>('/api/v1/superadmin/tenants')
  tenants.value = data.filter((tenant) => tenant.deployment_mode !== 'superadmin')
}

async function createLicense() {
  if (!createForm.tenant_id) {
    error.value = 'Tenant tanlang'
    return
  }
  error.value = null
  try {
    await api.post('/api/v1/superadmin/licenses', {
      tenant_id: createForm.tenant_id,
      duration_days: createForm.duration_days,
      max_devices: createForm.max_devices,
      max_users: createForm.max_users,
      features: {
        custom_ai: createForm.custom_ai,
        multi_site: createForm.multi_site,
        alert_routing: createForm.alert_routing,
      },
    })
    Object.assign(createForm, {
      tenant_id: '',
      duration_days: 365,
      max_devices: 10,
      max_users: 5,
      custom_ai: false,
      multi_site: false,
      alert_routing: true,
    })
    showCreate.value = false
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Litsenziya yaratib bo'lmadi"
  }
}

async function renewLicense(id: string) {
  error.value = null
  try {
    await api.post(`/api/v1/superadmin/licenses/${id}/renew`, { ...renewForm })
    renewId.value = null
    renewForm.duration_days = 365
    renewForm.reset_from_now = false
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Renew bajarilmadi'
  }
}

async function revokeLicense(id: string) {
  if (!revokeReason.value.trim()) {
    error.value = 'Revoke sababi kiritilishi kerak'
    return
  }
  error.value = null
  try {
    await api.post(`/api/v1/superadmin/licenses/${id}/revoke`, {
      reason: revokeReason.value.trim(),
    })
    revokeId.value = null
    revokeReason.value = ''
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Revoke bajarilmadi'
  }
}

async function deleteLicense(license: License) {
  if (!confirm(`License ${license.key.slice(0, 8)}... butunlay o'chirilsin?`)) return
  error.value = null
  try {
    await api.delete(`/api/v1/superadmin/licenses/${license.id}`)
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "O'chirib bo'lmadi"
  }
}

function statusOf(license: License) {
  if (license.is_revoked) return { label: 'Revoked', cls: 'border-rose-400/30 bg-rose-500/15 text-rose-300' }
  if (license.is_expired) return { label: 'Expired', cls: 'border-amber-400/30 bg-amber-500/15 text-amber-300' }
  return { label: 'Active', cls: 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300' }
}

function daysLeft(iso: string) {
  const days = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000)
  if (days < 0) return `${Math.abs(days)} kun oldin tugagan`
  if (days === 0) return 'Bugun tugaydi'
  return `${days} kun qoldi`
}

function featureText(features: Record<string, unknown>) {
  return Object.entries(features)
    .filter(([, enabled]) => Boolean(enabled))
    .map(([name]) => name.replaceAll('_', ' '))
}

onMounted(async () => {
  try {
    await Promise.all([load(), loadTenants()])
  } catch {
    await load()
  }
})
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.26em] text-amber-300/90">
          Superadmin Billing Control
        </p>
        <h1 class="mt-2 text-3xl font-black tracking-wide text-slate-50">Litsenziyalar</h1>
        <p class="mt-1 text-sm text-slate-400">
          Tenant limitlari, feature flaglar va muddat nazorati.
        </p>
      </div>
      <button
        @click="showCreate = !showCreate"
        class="rounded border border-amber-300/50 bg-amber-300 px-4 py-2 text-sm font-black text-slate-950 hover:bg-amber-200"
      >
        {{ showCreate ? 'Formani yopish' : 'Yangi license' }}
      </button>
    </header>

    <div v-if="error" class="rounded border border-rose-500/40 bg-rose-500/10 px-4 py-3 text-sm text-rose-300">
      {{ error }}
    </div>

    <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Active</div>
        <div class="mt-3 text-3xl font-black text-emerald-300">{{ activeLicenses.length }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Expiring 30d</div>
        <div class="mt-3 text-3xl font-black text-amber-200">{{ expiringSoon.length }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Expired</div>
        <div class="mt-3 text-3xl font-black text-orange-300">{{ expiredLicenses.length }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Revoked</div>
        <div class="mt-3 text-3xl font-black text-rose-300">{{ revokedLicenses.length }}</div>
      </div>
    </section>

    <section v-if="showCreate" class="eg-panel p-5">
      <h2 class="text-lg font-black text-slate-50">Tenantga license berish</h2>
      <form @submit.prevent="createLicense" class="mt-5 grid gap-4 md:grid-cols-2">
        <div class="md:col-span-2">
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Tenant</label>
          <select v-model="createForm.tenant_id" required class="eg-input">
            <option value="">Tanlang</option>
            <option v-for="tenant in tenants" :key="tenant.id" :value="tenant.id">
              {{ tenant.subdomain }} - {{ tenant.name }}
            </option>
          </select>
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Muddat (kun)</label>
          <input v-model.number="createForm.duration_days" type="number" min="1" max="3650" required class="eg-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Max devices</label>
          <input v-model.number="createForm.max_devices" type="number" min="1" max="10000" required class="eg-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Max users</label>
          <input v-model.number="createForm.max_users" type="number" min="1" max="10000" required class="eg-input" />
        </div>
        <div class="rounded border border-slate-800 bg-slate-950/60 p-4">
          <div class="mb-3 text-xs font-bold uppercase tracking-wider text-slate-400">Features</div>
          <div class="grid gap-2 text-sm text-slate-300">
            <label class="flex items-center gap-2"><input v-model="createForm.custom_ai" type="checkbox" class="h-4 w-4 accent-amber-300" /> Custom AI</label>
            <label class="flex items-center gap-2"><input v-model="createForm.multi_site" type="checkbox" class="h-4 w-4 accent-amber-300" /> Multi-site</label>
            <label class="flex items-center gap-2"><input v-model="createForm.alert_routing" type="checkbox" class="h-4 w-4 accent-amber-300" /> Alert routing</label>
          </div>
        </div>
        <div class="md:col-span-2 flex justify-end gap-2">
          <button type="button" @click="showCreate = false" class="rounded border border-slate-700 px-4 py-2 text-sm text-slate-300 hover:bg-slate-800">
            Bekor
          </button>
          <button type="submit" class="rounded bg-amber-300 px-5 py-2 text-sm font-black text-slate-950 hover:bg-amber-200">
            License berish
          </button>
        </div>
      </form>
    </section>

    <section class="eg-panel p-4">
      <div class="grid gap-3 md:grid-cols-[1fr_auto_auto]">
        <select v-model="filterTenantId" @change="load" class="eg-input">
          <option value="">Barcha tenantlar</option>
          <option v-for="tenant in tenants" :key="tenant.id" :value="tenant.id">
            {{ tenant.subdomain }} - {{ tenant.name }}
          </option>
        </select>
        <label class="flex items-center gap-2 rounded border border-slate-800 bg-slate-950/60 px-4 py-2 text-sm text-slate-300">
          <input v-model="onlyActive" @change="load" type="checkbox" class="h-4 w-4 accent-amber-300" />
          Faqat aktiv
        </label>
        <button @click="load" class="rounded border border-slate-700 px-4 py-2 text-sm font-bold text-slate-300 hover:bg-slate-800">
          Yangilash
        </button>
      </div>
    </section>

    <section class="grid gap-4 xl:grid-cols-2">
      <article v-for="license in licenses" :key="license.id" class="eg-panel overflow-hidden">
        <div class="border-b border-slate-800 p-5">
          <div class="flex items-start justify-between gap-3">
            <div>
              <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="statusOf(license).cls">
                {{ statusOf(license).label }}
              </span>
              <h2 class="mt-3 text-lg font-black text-slate-50">{{ license.tenant_name || 'Unknown tenant' }}</h2>
              <p class="font-mono text-sm text-cyan-300">{{ license.tenant_subdomain || 'unknown' }}</p>
            </div>
            <div class="text-right text-xs text-slate-500">
              <div>{{ new Date(license.expires_at).toLocaleDateString('uz-UZ') }}</div>
              <div>{{ daysLeft(license.expires_at) }}</div>
            </div>
          </div>
          <div class="mt-4 font-mono text-xs text-slate-500">{{ license.key }}</div>
        </div>

        <div class="grid grid-cols-2 divide-x divide-slate-800 border-b border-slate-800">
          <div class="p-4">
            <div class="font-mono text-2xl font-black text-cyan-200">{{ license.max_devices }}</div>
            <div class="text-[10px] uppercase text-slate-500">Max devices</div>
          </div>
          <div class="p-4">
            <div class="font-mono text-2xl font-black text-amber-200">{{ license.max_users }}</div>
            <div class="text-[10px] uppercase text-slate-500">Max users</div>
          </div>
        </div>

        <div class="border-b border-slate-800 p-4">
          <div class="flex flex-wrap gap-2">
            <span
              v-for="feature in featureText(license.features)"
              :key="feature"
              class="rounded border border-slate-700 bg-slate-950/70 px-2 py-1 text-xs text-slate-300"
            >
              {{ feature }}
            </span>
            <span v-if="featureText(license.features).length === 0" class="text-xs text-slate-500">Feature yo'q</span>
          </div>
          <div v-if="license.revocation_reason" class="mt-3 rounded border border-rose-400/30 bg-rose-500/10 p-2 text-xs text-rose-300">
            {{ license.revocation_reason }}
          </div>
        </div>

        <div class="p-4">
          <div class="flex flex-wrap gap-2">
            <button
              v-if="!license.is_revoked"
              @click="renewId = renewId === license.id ? null : license.id"
              class="rounded border border-cyan-400/30 bg-cyan-500/10 px-3 py-2 text-xs font-bold text-cyan-200 hover:bg-cyan-500/20"
            >
              Renew
            </button>
            <button
              v-if="!license.is_revoked"
              @click="revokeId = revokeId === license.id ? null : license.id"
              class="rounded border border-amber-400/30 bg-amber-500/10 px-3 py-2 text-xs font-bold text-amber-200 hover:bg-amber-500/20"
            >
              Revoke
            </button>
            <button
              @click="deleteLicense(license)"
              class="rounded border border-rose-400/30 bg-rose-500/10 px-3 py-2 text-xs font-bold text-rose-200 hover:bg-rose-500/20"
            >
              Delete
            </button>
          </div>

          <form v-if="renewId === license.id" @submit.prevent="renewLicense(license.id)" class="mt-4 grid gap-3 rounded border border-slate-800 bg-slate-950/60 p-3 md:grid-cols-[140px_1fr_auto]">
            <input v-model.number="renewForm.duration_days" type="number" min="1" max="3650" class="eg-input" />
            <label class="flex items-center gap-2 text-sm text-slate-300">
              <input v-model="renewForm.reset_from_now" type="checkbox" class="h-4 w-4 accent-cyan-300" />
              Hozirdan boshlash
            </label>
            <button type="submit" class="rounded bg-cyan-300 px-4 py-2 text-sm font-black text-slate-950">Renew</button>
          </form>

          <form v-if="revokeId === license.id" @submit.prevent="revokeLicense(license.id)" class="mt-4 grid gap-3 rounded border border-slate-800 bg-slate-950/60 p-3 md:grid-cols-[1fr_auto]">
            <input v-model="revokeReason" required placeholder="Revoke sababi" class="eg-input" />
            <button type="submit" class="rounded bg-amber-300 px-4 py-2 text-sm font-black text-slate-950">Revoke</button>
          </form>
        </div>
      </article>

      <div v-if="!loading && licenses.length === 0" class="eg-panel p-12 text-center text-slate-500 xl:col-span-2">
        Litsenziyalar topilmadi.
      </div>
    </section>
  </div>
</template>
