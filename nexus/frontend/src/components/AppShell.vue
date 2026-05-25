<script setup lang="ts">
import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

const homeTarget = computed(() => (auth.user?.is_superadmin ? '/superadmin/tenants' : '/'))

async function logout() {
  const wasSuperadmin = auth.user?.is_superadmin
  await auth.logout()
  router.push({ name: wasSuperadmin ? 'superadmin-login' : 'login' })
}
</script>

<template>
  <div class="min-h-screen">
    <nav class="sticky top-0 z-50 border-b border-slate-800 bg-slate-950/88 backdrop-blur-xl">
      <div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 py-3">
        <div class="flex flex-wrap items-center gap-4">
          <router-link :to="homeTarget" class="mr-2 flex items-center gap-2 font-bold">
            <span class="grid h-8 w-8 place-items-center rounded border border-cyan-300/40 bg-cyan-300/10 text-xs font-black text-cyan-200">
              EG
            </span>
            <span>EigenGuard Nexus</span>
            <span
              class="rounded px-2 py-0.5 font-mono text-xs"
              :class="auth.user?.is_superadmin
                ? 'bg-amber-500/15 text-amber-300'
                : 'bg-slate-800 text-cyan-300'"
            >
              {{ auth.user?.is_superadmin ? 'superadmin' : auth.user?.tenant_subdomain }}
            </span>
          </router-link>

          <template v-if="auth.user?.is_superadmin">
            <router-link
              to="/superadmin/tenants"
              class="text-sm font-bold text-amber-300 hover:text-amber-200"
              active-class="text-white"
            >
              Tenants
            </router-link>
            <router-link
              to="/superadmin/licenses"
              class="text-sm font-bold text-amber-300 hover:text-amber-200"
              active-class="text-white"
            >
              Licenses
            </router-link>
            <router-link
              to="/superadmin/audit-logs"
              class="text-sm font-bold text-amber-300 hover:text-amber-200"
              active-class="text-white"
            >
              Audit
            </router-link>
          </template>

          <template v-else>
            <router-link to="/" class="text-sm text-slate-300 hover:text-cyan-300" active-class="text-cyan-300">
              Dashboard
            </router-link>
            <router-link to="/commands" class="text-sm text-slate-300 hover:text-cyan-300" active-class="text-cyan-300">
              Commands
            </router-link>
            <router-link to="/camera-test" class="text-sm text-slate-300 hover:text-cyan-300" active-class="text-cyan-300">
              Camera Test
            </router-link>
            <router-link
              v-if="auth.user?.is_admin"
              to="/users"
              class="text-sm text-slate-300 hover:text-cyan-300"
              active-class="text-cyan-300"
            >
              Users
            </router-link>
          </template>
        </div>

        <div class="flex items-center gap-3">
          <div class="hidden text-right sm:block">
            <div class="text-xs font-mono text-slate-300">
              {{ auth.user?.username }} / {{ auth.user?.email }}
            </div>
            <div class="text-[10px] uppercase tracking-wider">
              <span v-if="auth.user?.is_superadmin" class="text-amber-300">Superadmin control plane</span>
              <span v-else-if="auth.user?.is_admin" class="text-cyan-300">
                {{ auth.user?.tenant_subdomain }} / {{ auth.user?.role }}
              </span>
              <span v-else class="text-emerald-300">
                {{ auth.user?.tenant_subdomain }} / {{ auth.user?.role }}
              </span>
            </div>
          </div>
          <button
            @click="logout"
            class="rounded border border-slate-700 bg-slate-900 px-3 py-1.5 text-xs font-bold text-slate-300 transition hover:border-rose-400/50 hover:text-rose-200"
          >
            Chiqish
          </button>
        </div>
      </div>
    </nav>
    <main class="mx-auto max-w-7xl px-4 py-6 sm:py-8">
      <slot />
    </main>
  </div>
</template>
