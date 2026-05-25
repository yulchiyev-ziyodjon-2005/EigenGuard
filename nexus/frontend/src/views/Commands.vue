<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { api } from '@/lib/api'
import type { Command, CommandType, Device } from '@/lib/types'

const devices = ref<Device[]>([])
const commands = ref<Command[]>([])
const error = ref<string | null>(null)
const loading = ref(true)

const COMMAND_TYPES: { value: CommandType; label: string; hint: string }[] = [
  { value: 'notify', label: 'Notify (bildirishnoma)', hint: 'payload: { message }' },
  { value: 'start_scan', label: 'Start scan', hint: '' },
  { value: 'stop_scan', label: 'Stop scan', hint: '' },
  { value: 'enable_demo_mode', label: 'Demo Mode ON', hint: '' },
  { value: 'disable_demo_mode', label: 'Demo Mode OFF', hint: '' },
  { value: 'set_material', label: 'Set material', hint: 'payload: { material_id }' },
  { value: 'take_snapshot', label: 'Take snapshot', hint: '' },
  { value: 'sync_now', label: 'Sync now', hint: '' },
  { value: 'custom', label: 'Custom', hint: 'erkin payload' },
]

const form = reactive({
  device_id: '',
  command_type: 'notify' as CommandType,
  payload_text: '{"message": "Test bildirishnoma"}',
  ttl_hours: 24,
})

const onlineDevices = computed(() => devices.value.filter((d) => d.is_active))

async function load() {
  loading.value = true
  error.value = null
  try {
    const [d, c] = await Promise.all([
      api.get<Device[]>('/api/v1/devices'),
      api.get<Command[]>('/api/v1/commands?limit=50'),
    ])
    devices.value = d.data
    commands.value = c.data
    if (!form.device_id && d.data.length) {
      form.device_id = d.data[0].id
    }
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Yuklab bo\'lmadi'
  } finally {
    loading.value = false
  }
}

async function sendCommand() {
  if (!form.device_id) {
    error.value = 'Qurilma tanlang'
    return
  }
  let payload: Record<string, unknown> | null = null
  if (form.payload_text.trim()) {
    try {
      payload = JSON.parse(form.payload_text)
    } catch {
      error.value = 'Payload JSON xato'
      return
    }
  }
  try {
    await api.post('/api/v1/commands', {
      device_id: form.device_id,
      command_type: form.command_type,
      payload,
      ttl_hours: form.ttl_hours,
    })
    await load()
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'Yuborib bo\'lmadi'
  }
}

function statusClass(s: string) {
  switch (s) {
    case 'pending':
      return 'bg-amber-500/20 text-amber-400'
    case 'delivered':
      return 'bg-cyan-500/20 text-cyan-400'
    case 'acknowledged':
      return 'bg-emerald-500/20 text-emerald-400'
    case 'failed':
      return 'bg-rose-500/20 text-rose-400'
    default:
      return 'bg-slate-700 text-slate-400'
  }
}

function fmtTime(s: string | null) {
  return s ? new Date(s).toLocaleString('uz-UZ') : '—'
}

function deviceLabel(id: string) {
  const d = devices.value.find((x) => x.id === id)
  return d ? d.device_name || d.device_identifier : id
}

function isOnline(id: string) {
  return devices.value.find((x) => x.id === id)?.is_online ?? false
}

onMounted(load)
</script>

<template>
  <div class="flex items-baseline justify-between mb-6 flex-wrap gap-2">
    <h1 class="text-2xl font-bold tracking-wider">COMMANDS</h1>
    <button @click="load" class="text-sm px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded">
      ↻ Yangilash
    </button>
  </div>

  <div
    v-if="error"
    class="mb-4 px-4 py-3 bg-rose-500/10 border border-rose-500/40 rounded text-rose-400"
  >
    {{ error }}
  </div>

  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <!-- Send command -->
    <div class="lg:col-span-1">
      <div class="bg-slate-900 border border-slate-800 rounded-xl p-6">
        <h2 class="text-sm uppercase tracking-wider text-slate-400 font-bold mb-4">
          Buyruq yuborish
        </h2>
        <form @submit.prevent="sendCommand" class="space-y-4">
          <div>
            <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
              Qurilma
            </label>
            <select
              v-model="form.device_id"
              required
              class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded text-sm"
            >
              <option value="" disabled>— tanlang —</option>
              <option v-for="d in onlineDevices" :key="d.id" :value="d.id">
                {{ d.device_name || d.device_identifier }}
                {{ d.is_online ? '● online' : '○ offline' }}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
              Buyruq turi
            </label>
            <select
              v-model="form.command_type"
              class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded text-sm"
            >
              <option v-for="c in COMMAND_TYPES" :key="c.value" :value="c.value">
                {{ c.label }}
              </option>
            </select>
            <p class="text-xs text-slate-500 mt-1">
              {{ COMMAND_TYPES.find((c) => c.value === form.command_type)?.hint }}
            </p>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
              Payload (JSON, ixt.)
            </label>
            <textarea
              v-model="form.payload_text"
              rows="4"
              class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded text-sm font-mono"
            ></textarea>
          </div>
          <div>
            <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
              TTL (soat)
            </label>
            <input
              v-model.number="form.ttl_hours"
              type="number"
              min="1"
              max="720"
              class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded text-sm"
            />
          </div>
          <button
            type="submit"
            class="w-full py-2.5 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold rounded"
          >
            ⇨ YUBORISH
          </button>
        </form>
      </div>
    </div>

    <!-- Commands history -->
    <div class="lg:col-span-2">
      <div class="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden">
        <div class="px-4 py-3 border-b border-slate-800">
          <h2 class="text-sm uppercase tracking-wider text-slate-400 font-bold">
            So'nggi buyruqlar
          </h2>
        </div>
        <table class="w-full text-sm" v-if="commands.length">
          <thead class="bg-slate-800/50 text-xs uppercase text-slate-400">
            <tr>
              <th class="px-3 py-2 text-left">Vaqt</th>
              <th class="px-3 py-2 text-left">Qurilma</th>
              <th class="px-3 py-2 text-left">Turi</th>
              <th class="px-3 py-2 text-center">Status</th>
              <th class="px-3 py-2 text-left">Yetkazildi</th>
              <th class="px-3 py-2 text-left">Ack</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="c in commands"
              :key="c.id"
              class="border-t border-slate-800 hover:bg-slate-800/30"
            >
              <td class="px-3 py-2 text-xs text-slate-400 font-mono">{{ fmtTime(c.created_at) }}</td>
              <td class="px-3 py-2 text-xs font-mono text-cyan-400">
                {{ deviceLabel(c.device_id) }}
                <span v-if="isOnline(c.device_id)" class="text-emerald-400">●</span>
              </td>
              <td class="px-3 py-2 text-xs font-mono">{{ c.command_type }}</td>
              <td class="px-3 py-2 text-center">
                <span class="px-2 py-0.5 rounded text-[10px] font-bold uppercase" :class="statusClass(c.status)">
                  {{ c.status }}
                </span>
              </td>
              <td class="px-3 py-2 text-xs text-slate-400">{{ fmtTime(c.delivered_at) }}</td>
              <td class="px-3 py-2 text-xs text-slate-400">{{ fmtTime(c.acknowledged_at) }}</td>
            </tr>
          </tbody>
        </table>
        <div v-else-if="!loading" class="px-4 py-12 text-center text-slate-500">
          Hozircha buyruqlar yo'q
        </div>
      </div>
    </div>
  </div>
</template>
