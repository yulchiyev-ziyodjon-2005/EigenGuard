<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()

const username = ref('')
const password = ref('')

async function submit() {
  try {
    await auth.login(username.value, password.value)
    router.push({ name: 'dashboard' })
  } catch {
    // error is stored in auth.error
  }
}
</script>

<template>
  <div class="eg-grid relative flex min-h-screen items-center justify-center overflow-hidden p-4">
    <div class="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan-300/70 to-transparent" />
    <div class="pointer-events-none absolute bottom-8 left-1/2 h-32 w-[min(720px,86vw)] -translate-x-1/2 rounded-full bg-cyan-400/10 blur-3xl" />

    <section class="grid w-full max-w-5xl overflow-hidden rounded-lg border border-slate-800 bg-slate-950/72 shadow-2xl shadow-slate-950/60 backdrop-blur-xl lg:grid-cols-[0.95fr_1.05fr]">
      <aside class="relative hidden overflow-hidden border-r border-slate-800 bg-slate-900/70 p-8 lg:block">
        <div class="eg-scan pointer-events-none absolute inset-0 opacity-50" />
        <div class="relative flex h-full flex-col justify-between">
          <div>
            <div class="mb-5 grid h-12 w-12 place-items-center rounded border border-cyan-300/40 bg-cyan-300/10 text-sm font-black text-cyan-200">
              EG
            </div>
            <p class="text-xs font-bold uppercase tracking-[0.26em] text-cyan-300/80">Tenant Workspace</p>
            <h1 class="mt-3 text-4xl font-black leading-tight text-white">
              Xodimlar va tenant adminlari uchun kirish
            </h1>
            <p class="mt-4 text-sm leading-6 text-slate-400">
              Login muvaffaqiyatli bo'lsa, tizim foydalanuvchining tenantini va rolini bazadan aniqlaydi hamda tegishli muhitni ochadi.
            </p>
          </div>
          <div class="grid gap-3 text-sm text-slate-300">
            <div class="rounded border border-slate-800 bg-slate-950/60 p-3">
              <div class="text-xs uppercase tracking-wider text-slate-500">Identifikatsiya</div>
              <div class="mt-1 font-mono text-cyan-200">username/email + password</div>
            </div>
            <div class="rounded border border-slate-800 bg-slate-950/60 p-3">
              <div class="text-xs uppercase tracking-wider text-slate-500">Sessiya</div>
              <div class="mt-1 font-mono text-cyan-200">tenant access_token</div>
            </div>
          </div>
        </div>
      </aside>

      <div class="relative p-7 sm:p-8">
      <div class="eg-scan pointer-events-none absolute inset-0 opacity-70" />
      <div class="relative">
        <div class="mb-7 text-center">
          <div class="mx-auto mb-4 grid h-14 w-14 place-items-center rounded-lg border border-cyan-300/40 bg-cyan-300/10 text-2xl font-black text-cyan-200">
            EG
          </div>
          <p class="text-xs font-bold uppercase tracking-[0.28em] text-cyan-300/80">
            Tenant Secure Login
          </p>
          <h1 class="mt-2 text-3xl font-black tracking-wide text-white">
            EigenGuard Nexus
          </h1>
          <p class="mt-2 text-sm text-slate-400">
            O'z tenantingiz muhitiga xavfsiz kirish
          </p>
        </div>

        <form @submit.prevent="submit" class="space-y-4">
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">
              Username yoki email
            </label>
            <input
              v-model="username"
              type="text"
              required
              autofocus
              autocomplete="username"
              placeholder="admin@demo.local"
              class="eg-input font-mono"
              @input="auth.clearError()"
            />
          </div>
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">
              Parol
            </label>
            <input
              v-model="password"
              type="password"
              required
              autocomplete="current-password"
              class="eg-input"
              @input="auth.clearError()"
            />
          </div>

          <div
            v-if="auth.error"
            class="rounded border border-rose-500/40 bg-rose-500/10 px-3 py-2 text-sm text-rose-300"
          >
            {{ auth.error }}
          </div>

          <button
            type="submit"
            :disabled="auth.loading"
            class="w-full rounded border border-cyan-300/40 bg-cyan-300 px-4 py-3 text-sm font-black uppercase tracking-wider text-slate-950 shadow-[0_0_30px_rgba(34,211,238,0.22)] transition hover:bg-cyan-200 disabled:border-slate-700 disabled:bg-slate-800 disabled:text-slate-500 disabled:shadow-none"
          >
            {{ auth.loading ? 'Tekshirilmoqda...' : 'Tenant muhitiga kirish' }}
          </button>
        </form>

        <div class="mt-6 border-t border-slate-800 pt-4 text-xs text-slate-500">
          <p class="mb-2 font-bold uppercase tracking-wider text-slate-400">Bu sahifa faqat tenant xodimlari uchun</p>
          <p>Superadmin akkauntlari bu formadan qabul qilinmaydi.</p>
          <router-link
            to="/superadmin/login"
            class="mt-4 inline-block font-bold text-amber-300 hover:text-amber-200"
          >
            Superadmin alohida kirish
          </router-link>
        </div>
      </div>
      </div>
    </section>
  </div>
</template>
