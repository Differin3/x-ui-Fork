<template>
  <div class="nodes">
    <h2>Nodes</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>Status</th>
          <th>Address</th>
          <th>Version</th>
          <th>Groups</th>
          <th>Last Seen</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="node in nodes" :key="node.id">
          <td class="mono">{{ node.id }}</td>
          <td>{{ node.name }}</td>
          <td><span :class="['status', node.status]">{{ node.status }}</span></td>
          <td>
            <div>{{ node.hostname || '—' }}</div>
            <small v-if="node.ip_address">{{ node.ip_address }}</small>
          </td>
          <td>{{ node.xray_version || 'n/a' }}</td>
          <td>
            <span v-if="node.groups.length === 0">—</span>
            <ul v-else>
              <li v-for="group in node.groups" :key="group.id">{{ group.name }}</li>
            </ul>
          </td>
          <td>{{ formatDate(node.last_seen) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, handleApiError } from '../services/api';

interface NodeGroup {
  id: number | string;
  name: string;
}

interface NodeItem {
  id: string;
  name: string;
  status: string;
  ip_address: string | null;
  hostname: string | null;
  xray_version: string | null;
  groups: NodeGroup[];
  last_seen: string | null;
}

const nodes = ref<NodeItem[]>([]);

function formatDate(value: string | null): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
}

onMounted(async () => {
  try {
    const { data } = await api.get('/api/admin/nodes');
    const payload: NodeItem[] = data?.data ?? [];
    nodes.value = payload;
  } catch (error) {
    console.error('Failed to load nodes', error);
    // TODO: Show error notification to user
    const errorMsg = handleApiError(error);
    console.error('Error:', errorMsg);
  }
});
</script>

<style scoped>
.nodes {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

table {
  width: 100%;
  border-collapse: collapse;
  background: #fff;
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 2px 12px rgba(15, 23, 42, 0.08);
}

th,
td {
  padding: 0.75rem 1rem;
  text-align: left;
}

th {
  font-size: 0.85rem;
  color: #6b7280;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  background: #f9fafb;
}

tr + tr td {
  border-top: 1px solid #e5e7eb;
}

.mono {
  font-family: 'Fira Code', 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
  font-size: 0.85rem;
}

.status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.25rem 0.5rem;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.status.online {
  background: rgba(16, 185, 129, 0.15);
  color: #047857;
}

.status.degraded {
  background: rgba(245, 158, 11, 0.15);
  color: #b45309;
}

.status.offline {
  background: rgba(248, 113, 113, 0.15);
  color: #b91c1c;
}

ul {
  margin: 0;
  padding-left: 1rem;
}

small {
  color: #6b7280;
}
</style>
