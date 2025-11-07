<template>
  <div class="dashboard">
    <h2>Overview</h2>
    <div class="metrics">
      <div class="card">
        <h3>Online Nodes</h3>
        <p>{{ stats.activeNodes }}</p>
      </div>
      <div class="card">
        <h3>Online Users</h3>
        <p>{{ stats.onlineUsers }}</p>
      </div>
      <div class="card">
        <h3>Traffic (24h)</h3>
        <p>{{ stats.traffic24h.toFixed(2) }} GB</p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive } from 'vue';
import { api, handleApiError } from '../services/api';

interface DashboardStats {
  activeNodes: number;
  onlineUsers: number;
  traffic24h: number;
}

const stats = reactive<DashboardStats>({
  activeNodes: 0,
  onlineUsers: 0,
  traffic24h: 0
});

onMounted(async () => {
  try {
    const { data } = await api.get('/api/admin/dashboard');
    const payload = data?.data ?? {};
    stats.activeNodes = Number(payload?.online_nodes ?? 0);
    stats.onlineUsers = Number(payload?.online_users ?? 0);
    stats.traffic24h = Number(payload?.traffic_24h_gb ?? 0);
  } catch (error) {
    console.error('Failed to load dashboard data', error);
    // TODO: Show error notification to user
    const errorMsg = handleApiError(error);
    console.error('Error:', errorMsg);
  }
});
</script>

<style scoped>
.dashboard {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.metrics {
  display: grid;
  gap: 1.5rem;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
}

.card {
  background: #fff;
  padding: 1.5rem;
  border-radius: 12px;
  box-shadow: 0 2px 12px rgba(15, 23, 42, 0.08);
}

.card h3 {
  margin-top: 0;
  margin-bottom: 0.5rem;
  color: #4b5563;
  font-size: 0.95rem;
  font-weight: 600;
}

.card p {
  margin: 0;
  font-size: 1.75rem;
  font-weight: 700;
  color: #111827;
}
</style>

