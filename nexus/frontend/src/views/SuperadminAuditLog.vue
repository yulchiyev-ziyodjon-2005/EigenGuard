<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api } from '@/lib/api'
import type { AuditLog, AuditLogPage, Tenant } from '@/lib/types'

const items = ref<AuditLog[]>([])
const total = ref(0)
const loading = ref(true)
const error = ref<string | null>(null)
const actions = ref<string[]>([])
const tenants = ref<Tenant[]>([])
const filterAction = ref('')
const filterTenantId = ref('')
const filterActor = ref('')
const expandedId = ref<string | null>(null)
const limit = 25
const offset = ref(0)

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / limit)))
const page = computed(() => Math.floor(offset.value / limit) + 1)
const createCount = computed(() => items.value.filter((item) => item.action.includes('create')).length)
const updateCount = computed(() => items.value.filter((item) => item.action.includes('update') || item.action.includes('renew')).length)
const destructiveCount = computed(() =>
  items.value.filter((item) => item.action.includes('delete') || item.action.includes('revoke')).length,
)

async function load() {
  loading.value = true
  error.value = null
  try {
    const params: Record<string, string | number> = { limit, offset: offset.value }
    if (filterAction.value) params.action = filterAction.value
    if (filterTenantId.value) params.tenant_id = filterTenantId.value
    if (filterActor.value.trim()) params.actor_email = filterActor.value.trim()
    const { data } = await api.get<AuditLogPage>('/api/v1/superadmin/audit-logs', { params })
    items.value = data.items
    total.value = data.total
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Audit log yuklanmadi'
  } finally {
    loading.value = false
  }
}

async function loadMeta() {
  const [{ data: actionRows }, { data: tenantRows }] = await Promise.all([
    api.get<string[]>('/api/v1/superadmin/audit-logs/actions'),
    api.get<Tenant[]>('/api/v1/superadmin/tenants'),
  ])
  actions.value = actionRows
  tenants.value = tenantRows
}

function applyFilters() {
  offset.value = 0
  load()
}

function resetFilters() {
  filterAction.value = ''
  filterTenantId.value = ''
  filterActor.value = ''
  offset.value = 0
  load()
}

function prev() {
  if (offset.value === 0) return
  offset.value = Math.max(0, offset.value - limit)
  load()
}

function next() {
  if (offset.value + limit >= total.value) return
  offset.value += limit
  load()
}

function actionBadge(action: string) {
  if (action.includes('delete') || action.includes('revoke')) {
    return 'border-rose-400/30 bg-rose-500/15 text-rose-300'
  }
  if (action.includes('create')) {
    return 'border-emerald-400/30 bg-emerald-500/15 text-emerald-300'
  }
  if (action.includes('renew') || action.includes('license')) {
    return 'border-amber-400/30 bg-amber-500/15 text-amber-300'
  }
  return 'border-cyan-400/30 bg-cyan-500/15 text-cyan-300'
}

onMounted(async () => {
  try {
    await loadMeta()
  } catch {
    // Filters can still work with free-form values from the current result set.
  }
  await load()
})
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.26em] text-amber-300/90">
          Superadmin Security Trace
        </p>
        <h1 class="mt-2 text-3xl font-black tracking-wide text-slate-50">Audit log</h1>
        <p class="mt-1 text-sm text-slate-400">
          Tenant va license o'zgarishlari bo'yicha izchil nazorat jurnali.
        </p>
      </div>
      <div class="rounded border border-slate-800 bg-slate-900 px-4 py-2 font-mono text-sm text-slate-300">
        Total: {{ total }}
      </div>
    </header>

    <div v-if="error" class="rounded border border-rose-500/40 bg-rose-500/10 px-4 py-3 text-sm text-rose-300">
      {{ error }}
    </div>

    <section class="grid gap-3 md:grid-cols-4">
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">This page</div>
        <div class="mt-3 text-3xl font-black text-slate-50">{{ items.length }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Creates</div>
        <div class="mt-3 text-3xl font-black text-emerald-300">{{ createCount }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Updates</div>
        <div class="mt-3 text-3xl font-black text-amber-200">{{ updateCount }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Destructive</div>
        <div class="mt-3 text-3xl font-black text-rose-300">{{ destructiveCount }}</div>
      </div>
    </section>

    <section class="eg-panel p-4">
      <div class="grid gap-3 lg:grid-cols-[180px_180px_minmax(220px,1fr)_auto_auto]">
        <select v-model="filterAction" class="eg-input">
          <option value="">Barcha actionlar</option>
          <option v-for="action in actions" :key="action" :value="action">{{ action }}</option>
        </select>
        <select v-model="filterTenantId" class="eg-input">
          <option value="">Barcha tenantlar</option>
          <option v-for="tenant in tenants" :key="tenant.id" :value="tenant.id">
            {{ tenant.subdomain }}
          </option>
        </select>
        <input v-model="filterActor" placeholder="Actor email qidirish" class="eg-input" />
        <button @click="applyFilters" class="rounded bg-cyan-300 px-4 py-2 text-sm font-black text-slate-950 hover:bg-cyan-200">
          Filter
        </button>
        <button @click="resetFilters" class="rounded border border-slate-700 px-4 py-2 text-sm font-bold text-slate-300 hover:bg-slate-800">
          Reset
        </button>
      </div>
    </section>

    <section class="eg-panel overflow-hidden">
      <table v-if="items.length" class="w-full text-sm">
        <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
          <tr>
            <th class="px-4 py-3 text-left">Time</th>
            <th class="px-4 py-3 text-left">Actor</th>
            <th class="px-4 py-3 text-center">Action</th>
            <th class="px-4 py-3 text-left">Target</th>
            <th class="px-4 py-3 text-left">Entity</th>
            <th class="px-4 py-3 text-left">IP</th>
            <th class="px-4 py-3 text-right">Details</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="row in items" :key="row.id">
            <tr class="border-t border-slate-800 hover:bg-slate-800/30">
              <td class="px-4 py-3 font-mono text-xs text-slate-500">
                {{ new Date(row.created_at).toLocaleString('uz-UZ') }}
              </td>
              <td class="px-4 py-3 font-mono text-xs text-cyan-300">{{ row.actor_email }}</td>
              <td class="px-4 py-3 text-center">
                <span class="rounded border px-2 py-1 text-[11px] font-bold uppercase" :class="actionBadge(row.action)">
                  {{ row.action }}
                </span>
              </td>
              <td class="px-4 py-3 font-mono text-xs text-slate-300">{{ row.target_tenant_subdomain || 'system' }}</td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">
                {{ row.entity_type }}
                <span v-if="row.entity_id"> / {{ row.entity_id.slice(0, 8) }}</span>
              </td>
              <td class="px-4 py-3 font-mono text-xs text-slate-500">{{ row.ip_address || 'unknown' }}</td>
              <td class="px-4 py-3 text-right">
                <button
                  @click="expandedId = expandedId === row.id ? null : row.id"
                  class="rounded border border-slate-700 px-2 py-1 text-xs text-slate-300 hover:bg-slate-800"
                >
                  {{ expandedId === row.id ? 'Hide' : 'View' }}
                </button>
              </td>
            </tr>
            <tr v-if="expandedId === row.id" class="border-t border-slate-800 bg-slate-950/60">
              <td colspan="7" class="p-5">
                <div v-if="row.payload" class="grid gap-4 md:grid-cols-2">
                  <div>
                    <div class="mb-2 text-xs font-bold uppercase tracking-wider text-rose-300">Before</div>
                    <pre class="overflow-x-auto rounded border border-rose-400/20 bg-slate-950 p-3 text-xs text-slate-300">{{ JSON.stringify(row.payload.before ?? {}, null, 2) }}</pre>
                  </div>
                  <div>
                    <div class="mb-2 text-xs font-bold uppercase tracking-wider text-emerald-300">After</div>
                    <pre class="overflow-x-auto rounded border border-emerald-400/20 bg-slate-950 p-3 text-xs text-slate-300">{{ JSON.stringify(row.payload.after ?? {}, null, 2) }}</pre>
                  </div>
                </div>
                <div v-else class="text-sm text-slate-500">Payload mavjud emas.</div>
                <div v-if="row.user_agent" class="mt-4 break-all font-mono text-[11px] text-slate-500">
                  UA: {{ row.user_agent }}
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>

      <div v-else-if="!loading" class="p-12 text-center text-slate-500">
        Audit yozuvlari topilmadi.
      </div>

      <div v-if="items.length" class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-800 px-4 py-3">
        <div class="font-mono text-xs text-slate-500">Sahifa {{ page }} / {{ totalPages }}</div>
        <div class="flex gap-2">
          <button
            @click="prev"
            :disabled="offset === 0"
            class="rounded border border-slate-700 px-3 py-1.5 text-xs text-slate-300 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Oldingi
          </button>
          <button
            @click="next"
            :disabled="offset + limit >= total"
            class="rounded border border-slate-700 px-3 py-1.5 text-xs text-slate-300 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Keyingi
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
