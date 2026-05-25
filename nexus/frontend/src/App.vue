<script setup lang="ts">
import { useAuthStore } from '@/stores/auth'
import { useRoute } from 'vue-router'
import AppShell from '@/components/AppShell.vue'

const auth = useAuthStore()
const route = useRoute()
</script>

<template>
  <AppShell v-if="auth.user && route.name !== 'login' && route.name !== 'superadmin-login'">
    <router-view />
  </AppShell>
  <router-view v-else />
</template>
