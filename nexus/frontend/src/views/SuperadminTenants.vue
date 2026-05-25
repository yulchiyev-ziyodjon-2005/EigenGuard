<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/lib/api'
import type { Tenant } from '@/lib/types'

const router = useRouter()

const tenants = ref<Tenant[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showCreate = ref(false)
const search = ref('')
const statusFilter = ref<'all' | 'active' | 'inactive' | 'needs_license'>('all')
const modeFilter = ref('')

const form = reactive({
  name: '',
  subdomain: '',
  deployment_mode: 'cloud',
  contact_email: '',
  admin_username: '',
  admin_email: '',
  admin_password: '',
  admin_full_name: '',
})

const tenantRows = computed(() =>
  tenants.value.filter((tenant) => tenant.deployment_mode !== 'superadmin'),
)
const activeCount = computed(() => tenantRows.value.filter((t) => t.is_active).length)
const inactiveCount = computed(() => tenantRows.value.filter((t) => !t.is_active).length)
const licensedCount = computed(
  () => tenantRows.value.filter((t) => (t.active_license_count ?? 0) > 0).length,
)
const totalUsers = computed(() =>
  tenantRows.value.reduce((sum, tenant) => sum + tenant.user_count, 0),
)
const totalDevices = computed(() =>
  tenantRows.value.reduce((sum, tenant) => sum + (tenant.device_count ?? 0), 0),
)

const filteredTenants = computed(() => {
  const q = search.value.trim().toLowerCase()
  return tenantRows.value.filter((tenant) => {
    const matchesSearch =
      !q ||
      tenant.name.toLowerCase().includes(q) ||
      tenant.subdomain.toLowerCase().includes(q) ||
      tenant.contact_email?.toLowerCase().includes(q)
    const matchesMode = !modeFilter.value || tenant.deployment_mode === modeFilter.value
    const matchesStatus =
      statusFilter.value === 'all' ||
      (statusFilter.value === 'active' && tenant.is_active) ||
      (statusFilter.value === 'inactive' && !tenant.is_active) ||
      (statusFilter.value === 'needs_license' && (tenant.active_license_count ?? 0) === 0)
    return matchesSearch && matchesMode && matchesStatus
  })
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const { data } = await api.get<Tenant[]>('/api/v1/superadmin/tenants')
    tenants.value = data
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Tenantlar yuklanmadi'
  } finally {
    loading.value = false
  }
}

async function createTenant() {
  error.value = null
  try {
    await api.post('/api/v1/superadmin/tenants', {
      ...form,
      subdomain: form.subdomain.trim().toLowerCase(),
      contact_email: form.contact_email.trim() || null,
      admin_full_name: form.admin_full_name.trim() || null,
      admin_username: form.admin_username.trim().toLowerCase(),
      admin_email: form.admin_email.trim().toLowerCase(),
    })
    Object.assign(form, {
      name: '',
      subdomain: '',
      deployment_mode: 'cloud',
      contact_email: '',
      admin_username: '',
      admin_email: '',
      admin_password: '',
      admin_full_name: '',
    })
    showCreate.value = false
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Tenant yaratib bo'lmadi"
  }
}

async function toggleActive(tenant: Tenant) {
  error.value = null
  try {
    await api.patch(`/api/v1/superadmin/tenants/${tenant.id}`, {
      is_active: !tenant.is_active,
    })
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Tenant holatini yangilab bo\'lmadi'
  }
}

async function removeTenant(tenant: Tenant) {
  const confirmed = confirm(
    `Tenant "${tenant.name}" o'chirilsin?\n\nBu tenantga tegishli user, qurilma, license va measurement ma'lumotlari ham o'chadi.`,
  )
  if (!confirmed) return
  error.value = null
  try {
    await api.delete(`/api/v1/superadmin/tenants/${tenant.id}`)
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Tenantni o'chirib bo'lmadi"
  }
}

function healthScore(tenant: Tenant) {
  let score = 100
  if (!tenant.is_active) score -= 45
  if ((tenant.active_license_count ?? 0) === 0) score -= 30
  if (tenant.user_count === 0) score -= 15
  if ((tenant.device_count ?? 0) === 0) score -= 10
  return Math.max(0, score)
}

function healthMeta(tenant: Tenant) {
  const score = healthScore(tenant)
  if (!tenant.is_active) {
    return {
      label: 'Suspended',
      cls: 'border-slate-600 bg-slate-700/40 text-slate-300',
      bar: 'bg-slate-500',
    }
  }
  if ((tenant.active_license_count ?? 0) === 0) {
    return {
      label: 'Needs license',
      cls: 'border-rose-400/40 bg-rose-500/15 text-rose-300',
      bar: 'bg-rose-400',
    }
  }
  if (score < 80) {
    return {
      label: 'Needs setup',
      cls: 'border-amber-400/40 bg-amber-500/15 text-amber-300',
      bar: 'bg-amber-300',
    }
  }
  return {
    label: 'Operational',
    cls: 'border-emerald-400/40 bg-emerald-500/15 text-emerald-300',
    bar: 'bg-emerald-300',
  }
}

function modeMeta(mode: string) {
  if (mode === 'air_gapped') return 'border-rose-400/30 bg-rose-500/15 text-rose-300'
  if (mode === 'on_premise') return 'border-amber-400/30 bg-amber-500/15 text-amber-300'
  return 'border-cyan-400/30 bg-cyan-500/15 text-cyan-300'
}

function percent(value: number, total: number) {
  if (!total) return '0%'
  return `${Math.round((value / total) * 100)}%`
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.26em] text-amber-300/90">
          Superadmin SaaS Control Plane
        </p>
        <h1 class="mt-2 text-3xl font-black tracking-wide text-slate-50">
          Tenantlar boshqaruvi
        </h1>
        <p class="mt-1 text-sm text-slate-400">
          Mijoz tenantlari, license coverage, deployment mode va operatsion holat nazorati.
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <button
          @click="load"
          class="rounded border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-bold text-slate-200 transition hover:border-amber-300/50 hover:text-amber-200"
        >
          Yangilash
        </button>
        <button
          @click="showCreate = !showCreate"
          class="rounded border border-amber-300/50 bg-amber-300 px-4 py-2 text-sm font-black text-slate-950 shadow-[0_0_22px_rgba(251,191,36,0.18)] transition hover:bg-amber-200"
        >
          {{ showCreate ? 'Formani yopish' : 'Yangi tenant' }}
        </button>
      </div>
    </header>

    <div
      v-if="error"
      class="rounded border border-rose-500/40 bg-rose-500/10 px-4 py-3 text-sm text-rose-300"
    >
      {{ error }}
    </div>

    <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Tenantlar</div>
        <div class="mt-3 text-3xl font-black text-slate-50">{{ tenantRows.length }}</div>
        <div class="mt-2 h-1.5 overflow-hidden rounded bg-slate-800">
          <div class="h-full bg-cyan-300" :style="{ width: '100%' }" />
        </div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Active</div>
        <div class="mt-3 text-3xl font-black text-emerald-300">{{ activeCount }}</div>
        <div class="mt-2 h-1.5 overflow-hidden rounded bg-slate-800">
          <div class="h-full bg-emerald-300" :style="{ width: percent(activeCount, tenantRows.length) }" />
        </div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Inactive</div>
        <div class="mt-3 text-3xl font-black text-slate-300">{{ inactiveCount }}</div>
        <div class="mt-2 h-1.5 overflow-hidden rounded bg-slate-800">
          <div class="h-full bg-slate-500" :style="{ width: percent(inactiveCount, tenantRows.length) }" />
        </div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Licensed</div>
        <div class="mt-3 text-3xl font-black text-amber-200">{{ licensedCount }}</div>
        <div class="mt-2 h-1.5 overflow-hidden rounded bg-slate-800">
          <div class="h-full bg-amber-300" :style="{ width: percent(licensedCount, tenantRows.length) }" />
        </div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Users / Devices</div>
        <div class="mt-3 text-3xl font-black text-cyan-200">{{ totalUsers }} / {{ totalDevices }}</div>
        <div class="mt-2 text-xs text-slate-500">Barcha tenantlar bo'yicha</div>
      </div>
    </section>

    <section v-if="showCreate" class="eg-panel p-5">
      <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-lg font-black text-slate-50">Yangi SaaS tenant yaratish</h2>
          <p class="mt-1 text-sm text-slate-500">
            Tenant bilan birga birinchi admin akkaunt yaratiladi.
          </p>
        </div>
        <button @click="showCreate = false" class="rounded border border-slate-700 px-3 py-1.5 text-sm text-slate-300 hover:bg-slate-800">
          Yopish
        </button>
      </div>

      <form @submit.prevent="createTenant" class="grid gap-4 md:grid-cols-2">
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Tenant nomi</label>
          <input v-model="form.name" required placeholder="Toshkent Issiqlik" class="eg-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Subdomain</label>
          <input
            v-model="form.subdomain"
            required
            pattern="^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"
            placeholder="tashkent-issiqlik"
            class="eg-input font-mono"
          />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Deployment</label>
          <select v-model="form.deployment_mode" class="eg-input">
            <option value="cloud">Cloud SaaS</option>
            <option value="on_premise">On-premise</option>
            <option value="air_gapped">Air-gapped</option>
          </select>
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Kontakt email</label>
          <input v-model="form.contact_email" type="email" placeholder="ops@example.uz" class="eg-input" />
        </div>
        <div class="md:col-span-2 border-t border-slate-800 pt-4">
          <p class="text-xs font-bold uppercase tracking-[0.2em] text-amber-300">
            Tenant admin akkaunti
          </p>
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Admin username</label>
          <input
            v-model="form.admin_username"
            required
            minlength="3"
            pattern="^[a-zA-Z0-9_-]+$"
            placeholder="tashkent-admin"
            class="eg-input font-mono"
          />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Admin email</label>
          <input v-model="form.admin_email" required type="email" placeholder="admin@example.uz" class="eg-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Admin parol</label>
          <input v-model="form.admin_password" required minlength="8" type="password" class="eg-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">Admin FIO</label>
          <input v-model="form.admin_full_name" placeholder="Bekzod Toshmatov" class="eg-input" />
        </div>
        <div class="flex items-end justify-end gap-2">
          <button type="button" @click="showCreate = false" class="rounded border border-slate-700 px-4 py-2 text-sm text-slate-300 hover:bg-slate-800">
            Bekor
          </button>
          <button type="submit" class="rounded bg-amber-300 px-5 py-2 text-sm font-black text-slate-950 hover:bg-amber-200">
            Tenant yaratish
          </button>
        </div>
      </form>
    </section>

    <section class="eg-panel p-4">
      <div class="grid gap-3 lg:grid-cols-[minmax(240px,1fr)_180px_180px_auto]">
        <input
          v-model="search"
          type="search"
          placeholder="Tenant nomi, subdomain yoki kontakt bo'yicha qidirish"
          class="eg-input"
        />
        <select v-model="statusFilter" class="eg-input">
          <option value="all">Barcha holatlar</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="needs_license">License kerak</option>
        </select>
        <select v-model="modeFilter" class="eg-input">
          <option value="">Barcha modelar</option>
          <option value="cloud">Cloud</option>
          <option value="on_premise">On-premise</option>
          <option value="air_gapped">Air-gapped</option>
        </select>
        <button
          @click="search = ''; statusFilter = 'all'; modeFilter = ''"
          class="rounded border border-slate-700 px-4 py-2 text-sm font-bold text-slate-300 hover:bg-slate-800"
        >
          Reset
        </button>
      </div>
    </section>

    <section class="grid gap-4 xl:grid-cols-2">
      <article
        v-for="tenant in filteredTenants"
        :key="tenant.id"
        class="eg-panel overflow-hidden transition hover:border-amber-300/30"
      >
        <div class="border-b border-slate-800 p-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mb-2 flex flex-wrap items-center gap-2">
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="modeMeta(tenant.deployment_mode)">
                  {{ tenant.deployment_mode }}
                </span>
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="healthMeta(tenant).cls">
                  {{ healthMeta(tenant).label }}
                </span>
              </div>
              <h2 class="truncate text-xl font-black text-slate-50">{{ tenant.name }}</h2>
              <p class="mt-1 font-mono text-sm text-cyan-300">{{ tenant.subdomain }}.eigenguard.uz</p>
              <p class="mt-1 text-xs text-slate-500">{{ tenant.contact_email || 'Kontakt email kiritilmagan' }}</p>
            </div>
            <div class="text-right">
              <div class="font-mono text-2xl font-black text-slate-50">{{ healthScore(tenant) }}</div>
              <div class="text-[10px] uppercase tracking-wider text-slate-500">Health</div>
            </div>
          </div>
          <div class="mt-4 h-2 overflow-hidden rounded bg-slate-800">
            <div
              class="h-full rounded"
              :class="healthMeta(tenant).bar"
              :style="{ width: `${healthScore(tenant)}%` }"
            />
          </div>
        </div>

        <div class="grid grid-cols-4 divide-x divide-slate-800 border-b border-slate-800">
          <div class="p-4">
            <div class="font-mono text-xl font-black text-cyan-200">{{ tenant.user_count }}</div>
            <div class="text-[10px] uppercase text-slate-500">Users</div>
          </div>
          <div class="p-4">
            <div class="font-mono text-xl font-black text-emerald-200">{{ tenant.device_count ?? 0 }}</div>
            <div class="text-[10px] uppercase text-slate-500">Devices</div>
          </div>
          <div class="p-4">
            <div class="font-mono text-xl font-black text-amber-200">{{ tenant.active_license_count ?? 0 }}</div>
            <div class="text-[10px] uppercase text-slate-500">Licenses</div>
          </div>
          <div class="p-4">
            <div class="font-mono text-xl font-black text-slate-200">{{ tenant.measurement_count }}</div>
            <div class="text-[10px] uppercase text-slate-500">Signals</div>
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-2 p-4">
          <div class="text-xs text-slate-500">
            Yaratilgan: {{ new Date(tenant.created_at).toLocaleDateString('uz-UZ') }}
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              @click="router.push({ name: 'tenant-detail', params: { id: tenant.id } })"
              class="rounded border border-cyan-400/30 bg-cyan-500/10 px-3 py-2 text-xs font-bold text-cyan-200 hover:bg-cyan-500/20"
            >
              Boshqarish
            </button>
            <button
              @click="toggleActive(tenant)"
              class="rounded border px-3 py-2 text-xs font-bold"
              :class="tenant.is_active
                ? 'border-slate-600 bg-slate-800 text-slate-300 hover:bg-slate-700'
                : 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200 hover:bg-emerald-500/20'"
            >
              {{ tenant.is_active ? 'Suspend' : 'Activate' }}
            </button>
            <button
              @click="removeTenant(tenant)"
              class="rounded border border-rose-400/30 bg-rose-500/10 px-3 py-2 text-xs font-bold text-rose-200 hover:bg-rose-500/20"
            >
              Delete
            </button>
          </div>
        </div>
      </article>

      <div v-if="!loading && filteredTenants.length === 0" class="eg-panel p-12 text-center text-slate-500 xl:col-span-2">
        Tanlangan filterlar bo'yicha tenant topilmadi.
      </div>
    </section>
  </div>
</template>
