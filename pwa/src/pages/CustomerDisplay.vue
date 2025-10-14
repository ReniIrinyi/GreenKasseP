<template>
  <div class="cv-wrap">
    <q-icon name="img:/green.svg" class="q-mr-sm" size="28px"/>
    <div v-if="state.lastItem" class="last">
      {{ state.lastItem.qty }} × {{ state.lastItem.name }}
      — CHF {{ (state.lastItem.price).toFixed(2) }}
    </div>
    <div class="msg">{{ state.message ?? 'Willkommen!' }}</div>
  </div>
</template>

<script lang="ts" setup>
import {onBeforeUnmount, onMounted, reactive} from 'vue'

const state = reactive<{ total?: number, lastItem?: any, message?: string }>({})

let ch: BroadcastChannel
onMounted(() => {
  ch = new BroadcastChannel('greensys-customer')
  ch.onmessage = (ev) => Object.assign(state, ev.data || {})
})
onBeforeUnmount(() => ch?.close())
</script>

<style scoped>
.cv-wrap {
  height: 100vh;
  width: 100vw;
  display: grid;
  place-items: center;
  gap: 2rem;
  background: var(--secondary, #629080);
  color: #fff;
  text-align: center
}

.last {
  font-size: 1.2rem;
  opacity: .9
}

.msg {
  font-size: 1.4rem
}
</style>
