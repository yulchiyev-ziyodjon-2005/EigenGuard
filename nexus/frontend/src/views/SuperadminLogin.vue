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
    await auth.superadminLogin(username.value, password.value)
    router.push({ name: 'tenants' })
  } catch {
    // error is stored in auth.error
  }
}
</script>

<template>
  <div class="eg-grid relative flex min-h-screen items-center justify-center overflow-hidden p-4">
    <div class="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-amber-300/80 to-transparent" />
    <div class="pointer-events-none absolute bottom-8 left-1/2 h-36 w-[min(760px,88vw)] -translate-x-1/2 rounded-full bg-amber-300/10 blur-3xl" />

    <section class="eg-panel relative w-full max-w-md overflow-hidden border-amber-300/30 p-7 shadow-[0_0_34px_rgba(251,191,36,0.12)] sm:p-8">
      <div class="relative">
        <div class="mb-7 text-center">
          <div class="mx-auto mb-4 grid h-14 w-14 place-items-center rounded border border-amber-300/40 bg-amber-300/10 text-sm font-black text-amber-200">
            SA
          </div>
          <p class="text-xs font-bold uppercase tracking-[0.28em] text-amber-300/90">
            Superadmin Control Plane
          </p>
          <h1 class="mt-2 text-3xl font-black tracking-wide text-white">
            Nexus Superadmin
          </h1>
          <p class="mt-2 text-sm text-slate-400">
            Tenantlar, litsenziyalar va audit nazorati uchun alohida kirish.
          </p>
        </div>

        <form @submit.prevent="submit" class="space-y-4">
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">
              Superadmin username
            </label>
            <input
              v-model="username"
              required
              autofocus
              autocomplete="username"
              placeholder="admin@eigenguard.uz"
              class="eg-input font-mono focus:border-amber-300"
              @input="auth.clearError()"
            />
          </div>
          <div>
            <label class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400">
              Parol
            </label>
            <input
              v-model="password"
              required
              type="password"
              autocomplete="current-password"
              class="eg-input focus:border-amber-300"
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
            class="w-full rounded border border-amber-300/40 bg-amber-300 px-4 py-3 text-sm font-black uppercase tracking-wider text-slate-950 shadow-[0_0_30px_rgba(251,191,36,0.2)] transition hover:bg-amber-200 disabled:border-slate-700 disabled:bg-slate-800 disabled:text-slate-500 disabled:shadow-none"
          >
            {{ auth.loading ? 'Tekshirilmoqda...' : 'Superadmin kirish' }}
          </button>
        </form>

        <div class="mt-6 flex justify-center border-t border-slate-800 pt-4">
          <div class="text-center">
            <p class="text-xs text-slate-500">Bu portal tenant xodimlarini qabul qilmaydi.</p>
            <router-link to="/login" class="mt-3 inline-block text-xs font-bold text-cyan-300 hover:text-cyan-200">
              Tenant xodimlari login sahifasi
            </router-link>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
