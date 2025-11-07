import { createRouter, createWebHistory } from 'vue-router';
import { api } from '../services/api';

const routes = [
  {
    path: '/login',
    name: 'login',
    component: () => import('../pages/Login.vue'),
    meta: { requiresAuth: false }
  },
  {
    path: '/',
    component: () => import('../layouts/BaseLayout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        name: 'dashboard',
        component: () => import('../pages/Dashboard.vue')
      },
      {
        path: 'nodes',
        name: 'nodes',
        component: () => import('../pages/Nodes.vue')
      }
    ]
  }
];

const router = createRouter({
  history: createWebHistory(),
  routes
});

router.beforeEach(async (to, from, next) => {
  if (to.meta.requiresAuth) {
    try {
      const response = await api.get('/api/auth/check');
      if (response.data.authenticated) {
        next();
      } else {
        next('/login');
      }
    } catch {
      next('/login');
    }
  } else if (to.path === '/login') {
    // Если уже авторизован, перенаправляем на главную
    try {
      const response = await api.get('/api/auth/check');
      if (response.data.authenticated) {
        next('/');
      } else {
        next();
      }
    } catch {
      next();
    }
  } else {
    next();
  }
});

export default router;

