<template>
  <div class="category-grid">
    <q-btn
      v-for="c in categories"
      :key="c.id"
      :label="c.label"
      :style="btnStyle(c)"
      class="category-btn"
      unelevated
      @click="printOnSecondDisplay('Picked: ' + c.label)"
    />
  </div>
</template>

<script lang="ts" setup>
import {api} from 'src/services/api'

type Cat = { id: string | number; label: string; bg?: string; color?: string }
const props = defineProps<{ categories: Cat[] }>()

const btnStyle = (c: Cat) => ({
  background: c.bg || '#e9eef3',
  color: c.color || '#1f2937',
  padding: '10px 6px',
  minHeight: '48px',
  fontWeight: '600',
  fontSize: '14px',
  textTransform: 'none'
})

const printOnSecondDisplay = async (msg: string) => {
  try {
    await api.display(msg)
  } catch (err) {
    console.error('Display error:', err)
  }
}
</script>

<style scoped>
.category-grid {
  display: grid;
  grid-template-columns:repeat(4, 1fr);
  gap: 8px;
}

.category-btn {
  justify-content: center;
}

@media (max-width: 1200px) {
  .category-grid {
    grid-template-columns:repeat(3, 1fr);
  }
}
</style>
