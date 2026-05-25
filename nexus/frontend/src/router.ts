import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/Login.vue'),
    meta: { public: true },
  },
  {
    path: '/superadmin/login',
    name: 'superadmin-login',
    component: () => import('@/views/SuperadminLogin.vue'),
    meta: { public: true, superadminLogin: true },
  },
  {
    path: '/',
    name: 'dashboard',
    component: () => import('@/views/Dashboard.vue'),
  },
  {
    path: '/users',
    name: 'users',
    component: () => import('@/views/UsersManage.vue'),
    meta: { requiresAdmin: true },
  },
  {
    path: '/commands',
    name: 'commands',
    component: () => import('@/views/Commands.vue'),
  },
  {
    path: '/camera-test',
    name: 'camera',
    component: () => import('@/views/CameraTest.vue'),
  },
  {
    path: '/superadmin/tenants',
    name: 'tenants',
    component: () => import('@/views/SuperadminTenants.vue'),
    meta: { requiresSuperadmin: true },
  },
  {
    path: '/superadmin/tenants/:id',
    name: 'tenant-detail',
    component: () => import('@/views/SuperadminTenantDetail.vue'),
    meta: { requiresSuperadmin: true },
  },
  {
    path: '/superadmin/licenses',
    name: 'licenses',
    component: () => import('@/views/SuperadminLicenses.vue'),
    meta: { requiresSuperadmin: true },
  },
  {
    path: '/superadmin/audit-logs',
    name: 'audit-logs',
    component: () => import('@/views/SuperadminAuditLog.vue'),
    meta: { requiresSuperadmin: true },
  },
  { path: '/:catchAll(.*)', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  const targetScope = to.path.startsWith('/superadmin') ? 'superadmin' : 'tenant'
  await auth.bootstrap(targetScope, auth.scope !== targetScope)

  if (to.meta.public) {
    if (to.name === 'login' && auth.user && !auth.user.is_superadmin) return { name: 'dashboard' }
    if (to.name === 'superadmin-login' && auth.user?.is_superadmin) return { name: 'tenants' }
    return true
  }

  if (!auth.user) {
    return to.meta.requiresSuperadmin ? { name: 'superadmin-login' } : { name: 'login' }
  }

  if (targetScope === 'superadmin' && !auth.user.is_superadmin) return { name: 'superadmin-login' }
  if (targetScope === 'tenant' && auth.user.is_superadmin) return { name: 'tenants' }
  if (to.meta.requiresAdmin && !auth.user.is_admin) return { name: 'dashboard' }
  if (to.meta.requiresSuperadmin && !auth.user.is_superadmin) return { name: 'login' }
  return true
})

export default router
