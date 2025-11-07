<template>
  <header class="nav-bar">
    <div class="left">
      <slot name="title">Control Panel</slot>
    </div>
    <div class="right">
      <button class="ghost" @click="handleLogout">Logout</button>
      <div class="avatar">AD</div>
    </div>
  </header>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router';
import { api } from '../services/api';

const router = useRouter();

async function handleLogout() {
  try {
    await api.post('/api/logout');
    router.push('/login');
  } catch (error) {
    console.error('Logout error:', error);
    router.push('/login');
  }
}
</script>

<style scoped>
.nav-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.5rem 2rem;
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
}

.right {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.ghost {
  border: 1px solid #3b82f6;
  background: transparent;
  color: #1d4ed8;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  cursor: pointer;
}

.avatar {
  width: 36px;
  height: 36px;
  border-radius: 18px;
  background: #1f2937;
  color: #f9fafb;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
}
</style>

