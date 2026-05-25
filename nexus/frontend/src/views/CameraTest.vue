<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { api } from '@/lib/api'
import type { Device } from '@/lib/types'

// ── State ────────────────────────────────────────────────────────────
const videoEl = ref<HTMLVideoElement | null>(null)
const canvasEl = ref<HTMLCanvasElement | null>(null)
const running = ref(false)
const statusText = ref('Kameraga ruxsat kutilmoqda')
const errorText = ref<string | null>(null)

const motion = ref(0)
const risk = ref(0)
const fps = ref(0)
const riskLevel = ref('LOW')
const isAlert = ref(false)

// Auto-upload + notify
const autoUpload = ref(true)
const notifyOnCritical = ref(false)
const targetDeviceId = ref('')
const devices = ref<Device[]>([])
const logLines = ref<string[]>([])
const uploadCount = ref(0)
const commandCount = ref(0)

let stream: MediaStream | null = null
let rafId = 0
let lastFrameTime = 0
let prevImageData: Uint8ClampedArray | null = null
let frameCount = 0
let fpsLastTime = performance.now()
let lastUploadTime = 0
let lastNotifyTime = 0

// Rolling baseline for risk %
const motionWindow: number[] = []
const WIN = 60

function log(line: string) {
  const ts = new Date().toLocaleTimeString('uz-UZ')
  logLines.value.unshift(`[${ts}] ${line}`)
  if (logLines.value.length > 60) logLines.value.pop()
}

function classify(p: number): string {
  if (p >= 75) return 'CRITICAL'
  if (p >= 50) return 'HIGH'
  if (p >= 25) return 'MEDIUM'
  return 'LOW'
}

async function loadDevices() {
  try {
    const { data } = await api.get<Device[]>('/api/v1/devices')
    devices.value = data
    if (!targetDeviceId.value && data.length) {
      const online = data.find((d) => d.is_online) || data[0]
      targetDeviceId.value = online.id
    }
  } catch {
    // silent
  }
}

async function start() {
  errorText.value = null
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
      audio: false,
    })
    if (videoEl.value) {
      videoEl.value.srcObject = stream
      await videoEl.value.play()
    }
    running.value = true
    statusText.value = 'TAHLIL DAVOM ETMOQDA'
    log('Kamera ishga tushdi')
    loop()
  } catch (e: any) {
    errorText.value = e?.message || 'Kameraga ruxsat olib bo\'lmadi'
    statusText.value = 'XATO'
  }
}

function stop() {
  running.value = false
  if (rafId) cancelAnimationFrame(rafId)
  rafId = 0
  stream?.getTracks().forEach((t) => t.stop())
  stream = null
  if (videoEl.value) videoEl.value.srcObject = null
  prevImageData = null
  motionWindow.length = 0
  statusText.value = 'To\'xtatildi'
  log('Kamera to\'xtatildi')
}

// Browser-side frame-difference vibration detector
// (Mobile C++ Lucas-Kanade'ning soddalashtirilgan versiyasi)
function loop() {
  if (!running.value || !videoEl.value || !canvasEl.value) return
  const video = videoEl.value
  const canvas = canvasEl.value

  if (video.readyState < 2) {
    rafId = requestAnimationFrame(loop)
    return
  }

  const w = canvas.width = video.videoWidth || 320
  const h = canvas.height = video.videoHeight || 240
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return
  ctx.drawImage(video, 0, 0, w, h)
  const frame = ctx.getImageData(0, 0, w, h).data

  if (prevImageData && prevImageData.length === frame.length) {
    let diff = 0
    // Stride 4 — 16 px sample (perf)
    for (let i = 0; i < frame.length; i += 16) {
      diff += Math.abs(frame[i] - prevImageData[i])
    }
    const px = Math.floor(frame.length / 16)
    const normalizedMotion = diff / (px * 255)
    motion.value = normalizedMotion

    // Rolling baseline (median of last WIN frames)
    motionWindow.push(normalizedMotion)
    if (motionWindow.length > WIN) motionWindow.shift()
    const sorted = [...motionWindow].sort((a, b) => a - b)
    const baseline = sorted[Math.floor(sorted.length / 2)] || 0.001
    // Risk = how much current exceeds baseline (clipped 0..100)
    const ratio = (normalizedMotion - baseline) / Math.max(baseline, 0.005)
    const pct = Math.min(100, Math.max(0, ratio * 50))
    risk.value = pct
    riskLevel.value = classify(pct)
    isAlert.value = pct >= 75

    // FPS
    frameCount++
    const now = performance.now()
    if (now - fpsLastTime > 1000) {
      fps.value = Math.round((frameCount * 1000) / (now - fpsLastTime))
      frameCount = 0
      fpsLastTime = now
    }

    // Auto-upload (har 2 sek)
    if (autoUpload.value && now - lastUploadTime > 2000) {
      lastUploadTime = now
      uploadMeasurement(normalizedMotion, pct, riskLevel.value)
    }

    // Notify mobile on CRITICAL (har 5 sek bir marta)
    if (
      notifyOnCritical.value &&
      isAlert.value &&
      targetDeviceId.value &&
      now - lastNotifyTime > 5000
    ) {
      lastNotifyTime = now
      notifyMobile(pct)
    }
  }

  prevImageData = new Uint8ClampedArray(frame)
  lastFrameTime = performance.now()
  rafId = requestAnimationFrame(loop)
}

async function uploadMeasurement(motionVal: number, riskPct: number, level: string) {
  const browserDeviceId = `browser-${navigator.platform.replace(/\s+/g, '-').toLowerCase()}`
  try {
    await api.post('/api/v1/measurements', {
      device_id: browserDeviceId,
      source: 'mobile', // browser bu yerda "mobile" sifatida ko'rsatiladi
      timestamp: new Date().toISOString(),
      risk_percent: riskPct,
      frequency_hz: 0,
      amplitude_mm: motionVal * 10,
      risk_level: level,
      frame_count: 1,
      duration_seconds: 0,
      object_label: 'browser-cam',
      material_id: 'universal',
    })
    uploadCount.value++
  } catch (e: any) {
    log(`Upload xato: ${e?.response?.data?.detail || e?.message}`)
  }
}

async function notifyMobile(riskPct: number) {
  try {
    await api.post('/api/v1/commands', {
      device_id: targetDeviceId.value,
      command_type: 'notify',
      payload: {
        title: '⚠ EigenGuard CRITICAL',
        message: `Web camera CRITICAL alert: ${riskPct.toFixed(0)}% risk`,
        risk_percent: riskPct,
      },
      ttl_hours: 1,
    })
    commandCount.value++
    log(`Mobile'ga notify yuborildi (risk=${riskPct.toFixed(0)}%)`)
  } catch (e: any) {
    log(`Notify xato: ${e?.response?.data?.detail || e?.message}`)
  }
}

onMounted(loadDevices)
onBeforeUnmount(stop)
</script>

<template>
  <div class="flex items-baseline justify-between mb-6 flex-wrap gap-2">
    <h1 class="text-2xl font-bold tracking-wider">
      CAMERA TEST <span class="text-cyan-400">— Brauzer Vibratsiya Analizatori</span>
    </h1>
    <router-link to="/" class="text-sm text-slate-400 hover:text-cyan-400">← Dashboard</router-link>
  </div>

  <div
    v-if="errorText"
    class="mb-4 px-4 py-3 bg-rose-500/10 border border-rose-500/40 rounded text-rose-400"
  >
    {{ errorText }}
  </div>

  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <!-- Video + controls -->
    <div class="lg:col-span-2">
      <div class="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden">
        <div class="relative aspect-video bg-black">
          <video ref="videoEl" autoplay muted playsinline class="w-full h-full object-cover"></video>
          <canvas ref="canvasEl" class="hidden"></canvas>
          <div v-if="isAlert" class="absolute inset-0 border-4 border-rose-500 glow-danger pointer-events-none"></div>
          <div class="absolute top-3 right-3 px-3 py-1 rounded-full bg-slate-900/80 backdrop-blur text-xs font-bold uppercase tracking-wider">
            {{ statusText }}
          </div>
        </div>
        <div class="px-4 py-3 flex flex-wrap gap-3 border-t border-slate-800 items-center">
          <button
            v-if="!running"
            @click="start"
            class="flex-1 min-w-0 px-4 py-2 bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold rounded text-sm"
          >
            ▶ Boshlash
          </button>
          <button
            v-else
            @click="stop"
            class="flex-1 min-w-0 px-4 py-2 bg-rose-500 hover:bg-rose-400 text-white font-bold rounded text-sm"
          >
            ■ To'xtatish
          </button>
          <label class="flex items-center gap-2 px-3 py-2 bg-slate-800 rounded text-xs cursor-pointer">
            <input type="checkbox" v-model="autoUpload" class="accent-cyan-500" />
            Nexus'ga yuborish (har 2s)
          </label>
        </div>
      </div>

      <!-- Metrics -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4">
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-3">
          <div class="text-xs text-slate-500 uppercase">Motion</div>
          <div class="text-2xl font-mono mt-1 text-cyan-400">{{ motion.toFixed(3) }}</div>
        </div>
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-3">
          <div class="text-xs text-slate-500 uppercase">Risk %</div>
          <div
            class="text-2xl font-mono mt-1"
            :class="
              risk >= 75
                ? 'text-rose-400'
                : risk >= 50
                  ? 'text-orange-400'
                  : risk >= 25
                    ? 'text-amber-400'
                    : 'text-emerald-400'
            "
          >
            {{ risk.toFixed(0) }}
          </div>
        </div>
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-3">
          <div class="text-xs text-slate-500 uppercase">FPS</div>
          <div class="text-2xl font-mono mt-1 text-slate-300">{{ fps }}</div>
        </div>
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-3">
          <div class="text-xs text-slate-500 uppercase">Daraja</div>
          <div
            class="text-lg font-bold mt-1"
            :class="
              riskLevel === 'CRITICAL'
                ? 'text-rose-400'
                : riskLevel === 'HIGH'
                  ? 'text-orange-400'
                  : riskLevel === 'MEDIUM'
                    ? 'text-amber-400'
                    : 'text-emerald-400'
            "
          >
            {{ riskLevel }}
          </div>
        </div>
      </div>

      <!-- Mobile push panel -->
      <div class="mt-4 bg-slate-900 border border-slate-800 rounded-xl p-4">
        <h2 class="text-sm uppercase tracking-wider text-slate-400 font-bold mb-3">
          📤 Mobile'ga signal yuborish
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 items-end">
          <div class="sm:col-span-2">
            <label class="block text-xs uppercase tracking-wider text-slate-400 mb-1">
              Maqsad qurilma
            </label>
            <select
              v-model="targetDeviceId"
              class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded text-sm"
            >
              <option value="" disabled>— tanlang —</option>
              <option v-for="d in devices" :key="d.id" :value="d.id">
                {{ d.device_name || d.device_identifier }}
                {{ d.is_online ? '● online' : '○ offline' }}
              </option>
            </select>
          </div>
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" v-model="notifyOnCritical" class="accent-rose-500" />
            <span class="text-sm">CRITICAL'da avtomatik notify</span>
          </label>
        </div>
        <p class="text-xs text-slate-500 mt-2">
          ON bo'lsa, browser CRITICAL aniqlasa, tanlangan telefonga
          <span class="text-cyan-400 font-mono">notify</span> buyruq yuboriladi
          (har 5 soniyada bir marta). Mobile WebSocket ulanishi bo'lsa real-time, aks holda
          mobile keyingi sync'da oladi.
        </p>
      </div>
    </div>

    <!-- Log -->
    <div>
      <div class="bg-slate-900 border border-slate-800 rounded-xl p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-sm font-bold uppercase tracking-wider text-slate-400">Statistika</h2>
        </div>
        <div class="grid grid-cols-2 gap-3 text-xs">
          <div>
            <div class="text-slate-500 uppercase">Yuborilgan</div>
            <div class="text-xl font-mono text-emerald-400 mt-1">{{ uploadCount }}</div>
          </div>
          <div>
            <div class="text-slate-500 uppercase">Notify'lar</div>
            <div class="text-xl font-mono text-cyan-400 mt-1">{{ commandCount }}</div>
          </div>
        </div>
      </div>

      <div class="mt-4 bg-slate-900 border border-slate-800 rounded-xl p-4">
        <h2 class="text-sm font-bold uppercase tracking-wider text-slate-400 mb-3">Live Log</h2>
        <div class="text-xs font-mono space-y-1 h-80 overflow-y-auto text-slate-400">
          <div v-for="(line, i) in logLines" :key="i">{{ line }}</div>
          <div v-if="!logLines.length" class="text-slate-600">— bo'sh —</div>
        </div>
      </div>

      <div class="mt-4 bg-slate-900 border border-slate-800 rounded-xl p-4">
        <h2 class="text-sm font-bold uppercase tracking-wider text-slate-400 mb-2">Algoritm</h2>
        <p class="text-xs text-slate-400 leading-relaxed">
          <span class="text-cyan-400">Frame-difference</span>: har kadrning piksel intensivligi
          oldingi kadr bilan taqqoslanadi (sum of absolute differences, stride=16).
          <br /><br />
          <span class="text-cyan-400">Motion</span> qiymati 60-kadrlik rolling baseline'ga
          nisbatan o'lchanadi. Risk % = (current − baseline) / baseline × 50 (0..100).
          <br /><br />
          <span class="text-rose-400">CRITICAL ≥ 75%</span> — qizil border + (ixt.)
          mobile'ga avtomatik notify.
          <br /><br />
          <span class="text-slate-500">
            Bu sodda algoritm — production mobile app'da C++ Lucas-Kanade optical flow +
            Kalman filter ishlatadi (sezuvchanlik 10× yuqori).
          </span>
        </p>
      </div>
    </div>
  </div>
</template>
