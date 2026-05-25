<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { api } from '@/lib/api'
import type { User } from '@/lib/types'

const users = ref<User[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showCreate = ref(false)
const resetUserId = ref<string | null>(null)
const resetPassword = ref('')

const form = reactive({
  username: '',
  email: '',
  password: '',
  full_name: '',
  role: 'engineer',
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const { data } = await api.get<User[]>('/api/v1/users')
    users.value = data
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Yuklab bo\'lmadi'
  } finally {
    loading.value = false
  }
}

async function createUser() {
  try {
    await api.post('/api/v1/users', {
      ...form,
      username: form.username.trim().toLowerCase(),
      email: form.email.trim().toLowerCase(),
      full_name: form.full_name.trim() || null,
    })
    Object.assign(form, { username: '', email: '', password: '', full_name: '', role: 'engineer' })
    showCreate.value = false
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Yaratib bo\'lmadi'
  }
}

async function toggleActive(u: User) {
  await api.patch(`/api/v1/users/${u.id}`, { is_active: !u.is_active })
  await load()
}

async function toggleAdmin(u: User) {
  await api.patch(`/api/v1/users/${u.id}`, {
    role: u.role === 'tenant_admin' ? 'engineer' : 'tenant_admin',
  })
  await load()
}

async function updateRole(u: User, role: string) {
  await api.patch(`/api/v1/users/${u.id}`, { role })
  await load()
}

async function doReset(id: string) {
  if (resetPassword.value.length < 8) {
    error.value = 'Parol kamida 8 ta belgi'
    return
  }
  await api.post(`/api/v1/users/${id}/reset-password`, { new_password: resetPassword.value })
  resetUserId.value = null
  resetPassword.value = ''
  await load()
}

async function removeUser(u: User) {
  if (!confirm(`User "${u.email}" o'chirilsin?`)) return
  try {
    await api.delete(`/api/v1/users/${u.id}`)
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'O\'chirib bo\'lmadi'
  }
}

function roleClass(role: string) {
  if (role === 'tenant_admin') return 'bg-amber-500/20 text-amber-300'
  if (role === 'engineer') return 'bg-cyan-500/20 text-cyan-300'
  if (role === 'operator') return 'bg-emerald-500/20 text-emerald-300'
  return 'bg-slate-700 text-slate-300'
}

onMounted(load)
</script>

<template>
  <div class="flex items-baseline justify-between mb-6 flex-wrap gap-2">
    <h1 class="text-2xl font-bold tracking-wider">XODIMLAR (mobile users)</h1>
    <button
      @click="showCreate = !showCreate"
      class="px-4 py-2 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold rounded text-sm"
    >
      {{ showCreate ? '× Yopish' : '+ Yangi xodim' }}
    </button>
  </div>

  <div
    v-if="error"
    class="mb-4 px-4 py-3 bg-rose-500/10 border border-rose-500/40 rounded text-rose-400"
  >
    {{ error }}
  </div>

  <div
    v-if="showCreate"
    class="mb-6 bg-slate-900 border border-cyan-500/40 rounded-xl p-6"
  >
    <h2 class="text-lg font-bold mb-4">Yangi xodim qo'shish (mobile login)</h2>
    <form @submit.prevent="createUser" class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">Username *</label>
        <input
          v-model="form.username"
          required
          minlength="3"
          pattern="^[a-zA-Z0-9_-]+$"
          placeholder="field-engineer-01"
          class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded font-mono"
        />
      </div>
      <div>
        <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">Email *</label>
        <input
          v-model="form.email"
          required
          type="email"
          placeholder="engineer@tenant.local"
          class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded"
        />
      </div>
      <div>
        <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
          Parol * (8+ belgi)
        </label>
        <input
          v-model="form.password"
          required
          type="password"
          minlength="8"
          class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded"
        />
      </div>
      <div>
        <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">FIO</label>
        <input
          v-model="form.full_name"
          placeholder="Bekzod Toshmatov"
          class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded"
        />
      </div>
      <div>
        <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">Role *</label>
        <select
          v-model="form.role"
          required
          class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded"
        >
          <option value="engineer">Engineer</option>
          <option value="operator">Operator</option>
          <option value="viewer">Viewer</option>
          <option value="tenant_admin">Tenant admin</option>
        </select>
      </div>
      <div class="md:col-span-2 flex justify-end gap-3">
        <button
          type="button"
          @click="showCreate = false"
          class="px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded text-sm"
        >
          Bekor
        </button>
        <button
          type="submit"
          class="px-6 py-2 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold rounded text-sm"
        >
          QO'SHISH
        </button>
      </div>
    </form>
  </div>

  <div class="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden">
    <table class="w-full text-sm" v-if="users.length">
      <thead class="bg-slate-800/50 text-xs uppercase text-slate-400">
        <tr>
          <th class="px-4 py-3 text-left">Login</th>
          <th class="px-4 py-3 text-left">FIO</th>
          <th class="px-4 py-3 text-center">Role</th>
          <th class="px-4 py-3 text-center">Active</th>
          <th class="px-4 py-3 text-left">Oxirgi kirish</th>
          <th class="px-4 py-3 text-right">Amallar</th>
        </tr>
      </thead>
      <tbody>
        <template v-for="u in users" :key="u.id">
          <tr class="border-t border-slate-800 hover:bg-slate-800/30">
            <td class="px-4 py-3">
              <div class="font-mono text-cyan-400 text-xs">{{ u.username }}</div>
              <div class="mt-1 font-mono text-slate-500 text-[11px]">{{ u.email }}</div>
            </td>
            <td class="px-4 py-3">{{ u.full_name || '—' }}</td>
            <td class="px-4 py-3 text-center">
              <select
                :value="u.role"
                class="rounded bg-slate-800 px-2 py-1 text-xs"
                :class="roleClass(u.role)"
                @change="updateRole(u, ($event.target as HTMLSelectElement).value)"
              >
                <option value="engineer">engineer</option>
                <option value="operator">operator</option>
                <option value="viewer">viewer</option>
                <option value="tenant_admin">tenant_admin</option>
              </select>
            </td>
            <td class="px-4 py-3 text-center">
              <button
                @click="toggleActive(u)"
                class="text-xs px-2 py-0.5 rounded"
                :class="
                  u.is_active
                    ? 'bg-emerald-500/20 text-emerald-400'
                    : 'bg-slate-700 text-slate-500'
                "
              >
                {{ u.is_active ? '● Active' : '○ Inactive' }}
              </button>
            </td>
            <td class="px-4 py-3 text-xs text-slate-400 font-mono">
              {{ u.last_login_at ? new Date(u.last_login_at).toLocaleString('uz-UZ') : '—' }}
            </td>
            <td class="px-4 py-3 text-right space-x-2">
              <button
                @click="toggleAdmin(u)"
                class="text-xs px-2 py-1 bg-amber-500/15 text-amber-300 hover:bg-amber-500/25 rounded"
              >
                Admin
              </button>
              <button
                @click="resetUserId = resetUserId === u.id ? null : u.id"
                class="text-xs px-2 py-1 bg-slate-800 hover:bg-slate-700 rounded"
              >
                🔑
              </button>
              <button
                @click="removeUser(u)"
                class="text-xs px-2 py-1 bg-rose-500/20 text-rose-400 hover:bg-rose-500/30 rounded"
              >
                O'chirish
              </button>
            </td>
          </tr>
          <tr v-if="resetUserId === u.id" class="border-t border-slate-800 bg-slate-800/20">
            <td colspan="6" class="px-4 py-3">
              <form @submit.prevent="doReset(u.id)" class="flex items-end gap-3">
                <div class="flex-1">
                  <label class="block text-xs text-slate-400 mb-1">Yangi parol</label>
                  <input
                    v-model="resetPassword"
                    type="password"
                    minlength="8"
                    required
                    class="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded text-sm"
                  />
                </div>
                <button
                  type="submit"
                  class="px-4 py-2 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold rounded text-sm"
                >
                  RESET
                </button>
              </form>
            </td>
          </tr>
        </template>
      </tbody>
    </table>
    <div v-else-if="!loading" class="px-4 py-12 text-center text-slate-500">
      Xodimlar yo'q
    </div>
  </div>
</template>
