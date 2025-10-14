<template>
  <div class="category-grid">
    <q-btn
      v-for="c in [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]"
      :key="c"
      :label="c"
      class="category-btn"
      unelevated
    />
  </div>
</template>

<script lang="ts">

export default {
  name: 'CategoryGrid',
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
