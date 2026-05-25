<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { api, apiWebSocketUrl } from '@/lib/api'
import type { DashboardWsMessage, Device, Measurement, PredictionAnalysis } from '@/lib/types'

const devices = ref<Device[]>([])
const measurements = ref<Measurement[]>([])
const analyses = ref<PredictionAnalysis[]>([])
const loading = ref(true)
const testingAi = ref(false)
const error = ref<string | null>(null)
const socketStatus = ref<'connecting' | 'online' | 'offline'>('offline')

let socket: WebSocket | null = null
let reconnectTimer: number | null = null
let pingTimer: number | null = null
let closing = false

const onlineCount = computed(() => devices.value.filter((d) => d.is_online).length)
const criticalCount = computed(
  () => measurements.value.filter((m) => m.risk_level === 'CRITICAL').length,
)
const latestAnalysis = computed(() => analyses.value[0] ?? null)
const latestMeasurement = computed(() => measurements.value[0] ?? null)
const avgRisk = computed(() => {
  if (!measurements.value.length) return 0
  const total = measurements.value.reduce((sum, m) => sum + m.risk_percent, 0)
  return total / measurements.value.length
})
const signalTrend = computed(() => [...measurements.value].reverse().slice(-24))
const riskSeries = computed(() => signalTrend.value.map((m) => m.risk_percent))
const amplitudeSeries = computed(() => signalTrend.value.map((m) => m.amplitude_mm))
const aiRiskSeries = computed(() =>
  [...analyses.value]
    .reverse()
    .slice(-24)
    .map((a) => a.anomaly_probability * 100),
)

async function load() {
  loading.value = true
  error.value = null
  try {
    const [d, m] = await Promise.all([
      api.get<Device[]>('/api/v1/devices'),
      api.get<Measurement[]>('/api/v1/measurements?limit=50'),
    ])
    devices.value = d.data
    measurements.value = m.data
  } catch (e: any) {
    error.value = e?.response?.data?.detail || "Yuklab bo'lmadi"
  } finally {
    loading.value = false
  }
}

function addAnalysis(analysis: PredictionAnalysis) {
  if (analyses.value.some((item) => item.created_at === analysis.created_at)) return
  analyses.value = [analysis, ...analyses.value].slice(0, 50)
}

async function runAiTest() {
  testingAi.value = true
  error.value = null
  const source = latestMeasurement.value
  try {
    const { data } = await api.post<PredictionAnalysis>('/api/v1/measurements/analyze', {
      device_id: source?.device_id ?? 'dashboard-demo',
      timestamp: source?.timestamp ?? new Date().toISOString(),
      amplitude_mm: source?.amplitude_mm ?? 2.8,
      frequency_hz: source?.frequency_hz ?? 72,
      camera_risk: source?.risk_percent ?? 58,
    })
    addAnalysis(data)
  } catch (e: any) {
    error.value = e?.response?.data?.detail || 'AI tahlil bajarilmadi'
  } finally {
    testingAi.value = false
  }
}

function connectDashboardSocket() {
  if (socket && socket.readyState <= WebSocket.OPEN) return
  socketStatus.value = 'connecting'
  socket = new WebSocket(apiWebSocketUrl('/api/v1/ws/dashboard'))

  socket.onopen = () => {
    socketStatus.value = 'online'
    if (pingTimer) window.clearInterval(pingTimer)
    pingTimer = window.setInterval(() => {
      if (socket?.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ kind: 'ping' }))
      }
    }, 30000)
  }

  socket.onmessage = (event) => {
    try {
      const message = JSON.parse(event.data) as DashboardWsMessage
      if (message.kind === 'analysis' && message.data) {
        addAnalysis(message.data)
      }
    } catch {
      // Ignore malformed frames; backend controls this channel.
    }
  }

  socket.onclose = () => {
    socketStatus.value = 'offline'
    if (pingTimer) window.clearInterval(pingTimer)
    pingTimer = null
    socket = null
    if (!closing) {
      if (reconnectTimer) window.clearTimeout(reconnectTimer)
      reconnectTimer = window.setTimeout(connectDashboardSocket, 2500)
    }
  }

  socket.onerror = () => {
    socket?.close()
  }
}

function riskClass(level: string) {
  switch (level) {
    case 'CRITICAL':
      return 'bg-rose-500/20 text-rose-300 border-rose-400/30'
    case 'HIGH':
      return 'bg-orange-500/20 text-orange-300 border-orange-400/30'
    case 'MEDIUM':
      return 'bg-amber-500/20 text-amber-300 border-amber-400/30'
    default:
      return 'bg-emerald-500/20 text-emerald-300 border-emerald-400/30'
  }
}

function sourceBadge(s: string) {
  if (s === 'fused') return 'bg-emerald-500/20 text-emerald-300'
  if (s === 'edge') return 'bg-cyan-500/20 text-cyan-300'
  return 'bg-slate-700 text-slate-300'
}

function fmtTime(s: string) {
  return new Date(s).toLocaleString('uz-UZ')
}

function fmtPercent(value: number) {
  return `${value.toFixed(0)}%`
}

function barWidth(value: number) {
  return { width: `${Math.max(2, Math.min(100, value))}%` }
}

function sparklinePoints(values: number[], width = 360, height = 104) {
  if (!values.length) return ''
  const max = Math.max(...values, 1)
  const min = Math.min(...values, 0)
  const spread = Math.max(max - min, 1)
  return values
    .map((value, index) => {
      const x = values.length === 1 ? width : (index / (values.length - 1)) * width
      const y = height - ((value - min) / spread) * height
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })
    .join(' ')
}

onMounted(() => {
  load()
  connectDashboardSocket()
})

onBeforeUnmount(() => {
  closing = true
  if (reconnectTimer) window.clearTimeout(reconnectTimer)
  if (pingTimer) window.clearInterval(pingTimer)
  socket?.close()
})
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.24em] text-cyan-300/80">
          Live Command Center
        </p>
        <h1 class="mt-2 text-3xl font-black tracking-wide text-slate-50">
          EigenGuard Nexus
        </h1>
        <p class="mt-1 text-sm text-slate-400">
          Sensor, kamera va AI verdictlar yagona operatsion panelda.
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="rounded border px-3 py-2 text-xs font-bold uppercase"
          :class="socketStatus === 'online'
            ? 'border-emerald-400/40 bg-emerald-500/15 text-emerald-300'
            : socketStatus === 'connecting'
              ? 'border-amber-400/40 bg-amber-500/15 text-amber-300'
              : 'border-slate-600 bg-slate-800 text-slate-300'"
        >
          WS {{ socketStatus }}
        </span>
        <button
          @click="runAiTest"
          :disabled="testingAi"
          class="rounded border border-cyan-400/40 bg-cyan-400/15 px-4 py-2 text-sm font-bold text-cyan-100 shadow-[0_0_22px_rgba(34,211,238,0.16)] transition hover:bg-cyan-400/25 disabled:border-slate-700 disabled:bg-slate-800 disabled:text-slate-500"
        >
          {{ testingAi ? 'AI...' : 'AI test' }}
        </button>
        <button
          @click="load"
          class="rounded border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-bold text-slate-200 transition hover:border-cyan-400/50 hover:text-cyan-200"
        >
          Yangilash
        </button>
      </div>
    </header>

    <div
      v-if="error"
      class="rounded border border-rose-500/40 bg-rose-500/10 px-4 py-3 text-sm text-rose-300"
    >
      {{ error }}
    </div>

    <section class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Qurilmalar</div>
        <div class="mt-3 text-3xl font-black text-cyan-300">{{ devices.length }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Online</div>
        <div class="mt-3 text-3xl font-black text-emerald-300">{{ onlineCount }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">O'rtacha risk</div>
        <div class="mt-3 text-3xl font-black text-amber-200">{{ fmtPercent(avgRisk) }}</div>
      </div>
      <div class="eg-panel p-4">
        <div class="text-xs uppercase tracking-wider text-slate-500">Kritik</div>
        <div class="mt-3 text-3xl font-black text-rose-300">{{ criticalCount }}</div>
      </div>
    </section>

    <section class="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,0.65fr)]">
      <div class="eg-panel p-5">
        <div class="mb-5 flex items-center justify-between gap-3">
          <div>
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">
              Live Data Stream
            </h2>
            <p class="mt-1 text-xs text-slate-500">Risk, amplituda va AI ehtimollik trendi</p>
          </div>
          <span class="text-xs font-mono text-slate-500">{{ signalTrend.length }} points</span>
        </div>

        <div class="grid gap-4 lg:grid-cols-3">
          <div class="rounded border border-slate-800 bg-slate-950/60 p-4">
            <div class="mb-3 flex justify-between text-xs">
              <span class="font-bold uppercase text-slate-400">Risk</span>
              <span class="font-mono text-amber-200">{{ fmtPercent(latestMeasurement?.risk_percent ?? 0) }}</span>
            </div>
            <svg viewBox="0 0 360 104" class="h-28 w-full overflow-visible">
              <polyline
                :points="sparklinePoints(riskSeries)"
                fill="none"
                stroke="rgb(251 191 36)"
                stroke-width="4"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </div>
          <div class="rounded border border-slate-800 bg-slate-950/60 p-4">
            <div class="mb-3 flex justify-between text-xs">
              <span class="font-bold uppercase text-slate-400">Amplitude</span>
              <span class="font-mono text-cyan-200">
                {{ (latestMeasurement?.amplitude_mm ?? 0).toFixed(2) }} mm
              </span>
            </div>
            <svg viewBox="0 0 360 104" class="h-28 w-full overflow-visible">
              <polyline
                :points="sparklinePoints(amplitudeSeries)"
                fill="none"
                stroke="rgb(34 211 238)"
                stroke-width="4"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </div>
          <div class="rounded border border-slate-800 bg-slate-950/60 p-4">
            <div class="mb-3 flex justify-between text-xs">
              <span class="font-bold uppercase text-slate-400">AI Risk</span>
              <span class="font-mono text-rose-200">
                {{ fmtPercent((latestAnalysis?.anomaly_probability ?? 0) * 100) }}
              </span>
            </div>
            <svg viewBox="0 0 360 104" class="h-28 w-full overflow-visible">
              <polyline
                :points="sparklinePoints(aiRiskSeries)"
                fill="none"
                stroke="rgb(251 113 133)"
                stroke-width="4"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </div>
        </div>
      </div>

      <aside class="eg-panel p-5">
        <div class="mb-5 flex items-center justify-between">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">
            AI Analysis
          </h2>
          <span
            v-if="latestAnalysis"
            class="rounded border px-2 py-1 text-[11px] font-bold"
            :class="riskClass(latestAnalysis.risk_level)"
          >
            {{ latestAnalysis.risk_level }}
          </span>
        </div>

        <div v-if="latestAnalysis" class="space-y-5">
          <div>
            <div class="mb-2 flex justify-between text-xs text-slate-400">
              <span>Health Index</span>
              <span class="font-mono text-slate-100">{{ latestAnalysis.health_index.toFixed(1) }}</span>
            </div>
            <div class="h-3 overflow-hidden rounded bg-slate-800">
              <div
                class="h-full rounded bg-gradient-to-r from-rose-400 via-amber-300 to-emerald-300"
                :style="barWidth(latestAnalysis.health_index)"
              />
            </div>
          </div>

          <div>
            <div class="mb-2 flex justify-between text-xs text-slate-400">
              <span>Anomaliya ehtimoli</span>
              <span class="font-mono text-rose-200">
                {{ fmtPercent(latestAnalysis.anomaly_probability * 100) }}
              </span>
            </div>
            <div class="h-3 overflow-hidden rounded bg-slate-800">
              <div
                class="h-full rounded bg-rose-400"
                :style="barWidth(latestAnalysis.anomaly_probability * 100)"
              />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div class="rounded border border-slate-800 bg-slate-950/70 p-3">
              <div class="text-[11px] uppercase text-slate-500">Critical ETA</div>
              <div class="mt-2 font-mono text-xl text-slate-100">
                {{
                  latestAnalysis.hours_to_critical === null
                    ? 'N/A'
                    : `${latestAnalysis.hours_to_critical.toFixed(1)}h`
                }}
              </div>
            </div>
            <div class="rounded border border-slate-800 bg-slate-950/70 p-3">
              <div class="text-[11px] uppercase text-slate-500">Device</div>
              <div class="mt-2 truncate font-mono text-sm text-cyan-200">
                {{ latestAnalysis.device_id || 'unknown' }}
              </div>
            </div>
          </div>

          <p class="rounded border border-cyan-400/20 bg-cyan-400/10 p-3 text-sm text-cyan-50">
            {{ latestAnalysis.verdict }}
          </p>

          <ul class="space-y-2 text-sm text-slate-300">
            <li
              v-for="item in latestAnalysis.recommendations"
              :key="item"
              class="rounded border border-slate-800 bg-slate-950/60 px-3 py-2"
            >
              {{ item }}
            </li>
          </ul>
        </div>
        <div v-else class="rounded border border-slate-800 bg-slate-950/60 p-5 text-sm text-slate-500">
          Hali AI verdict kelmadi.
        </div>
      </aside>
    </section>

    <section class="grid gap-6 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
      <div class="eg-panel overflow-hidden">
        <div class="border-b border-slate-800 px-5 py-4">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">Qurilmalar</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm" v-if="devices.length">
            <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
              <tr>
                <th class="px-4 py-3 text-left">Identifier</th>
                <th class="px-4 py-3 text-center">Online</th>
                <th class="px-4 py-3 text-right">Risk</th>
                <th class="px-4 py-3 text-left">Last seen</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="d in devices" :key="d.id" class="border-t border-slate-800/80 hover:bg-slate-800/30">
                <td class="px-4 py-3">
                  <div class="font-mono text-xs text-cyan-300">{{ d.device_identifier }}</div>
                  <div class="mt-1 text-[11px] text-slate-500">{{ d.device_name || d.platform }}</div>
                </td>
                <td class="px-4 py-3 text-center">
                  <span
                    class="inline-block h-2.5 w-2.5 rounded-full"
                    :class="d.is_online ? 'bg-emerald-300 shadow-[0_0_18px_rgba(110,231,183,0.8)]' : 'bg-slate-600'"
                  />
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    v-if="d.last_risk_level"
                    class="rounded border px-2 py-1 text-xs font-bold"
                    :class="riskClass(d.last_risk_level)"
                  >
                    {{ d.last_risk_percent?.toFixed(0) }}%
                  </span>
                  <span v-else class="text-slate-600">N/A</span>
                </td>
                <td class="px-4 py-3 font-mono text-xs text-slate-400">{{ fmtTime(d.last_seen_at) }}</td>
              </tr>
            </tbody>
          </table>
          <div v-else-if="!loading" class="px-4 py-12 text-center text-slate-500">
            Hozircha qurilmalar yo'q
          </div>
        </div>
      </div>

      <div class="eg-panel overflow-hidden">
        <div class="border-b border-slate-800 px-5 py-4">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-slate-300">
            So'nggi o'lchovlar
          </h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm" v-if="measurements.length">
            <thead class="bg-slate-950/80 text-xs uppercase text-slate-500">
              <tr>
                <th class="px-4 py-3 text-left">Vaqt</th>
                <th class="px-4 py-3 text-left">Manba</th>
                <th class="px-4 py-3 text-right">Amp</th>
                <th class="px-4 py-3 text-right">Freq</th>
                <th class="px-4 py-3 text-center">Risk</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="m in measurements"
                :key="m.id"
                class="border-t border-slate-800/80 hover:bg-slate-800/30"
              >
                <td class="px-4 py-3 font-mono text-xs text-slate-400">{{ fmtTime(m.received_at) }}</td>
                <td class="px-4 py-3">
                  <span class="rounded px-2 py-1 text-[10px] font-bold uppercase" :class="sourceBadge(m.source)">
                    {{ m.source }}
                  </span>
                </td>
                <td class="px-4 py-3 text-right font-mono">{{ m.amplitude_mm.toFixed(2) }}</td>
                <td class="px-4 py-3 text-right font-mono">{{ m.frequency_hz.toFixed(0) }}</td>
                <td class="px-4 py-3 text-center">
                  <span class="rounded border px-2 py-1 text-xs font-bold" :class="riskClass(m.risk_level)">
                    {{ m.risk_percent.toFixed(0) }}%
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <div v-else-if="!loading" class="px-4 py-12 text-center text-slate-500">
            Hozircha o'lchovlar yo'q
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
