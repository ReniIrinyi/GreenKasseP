<template>
  <q-card bordered flat>
    <q-card-section>
      <div class="row q-col-gutter-md">
        <div class="col-6">
          <q-input
            v-model="qtyProxy"
            dense
            inputmode="numeric"
            label="Menge"
            min="0"
            standout="bg-teal-2 text-dark"
            step="1"
            type="number"
          />
        </div>
        <div class="col-6">
          <q-input
            v-model="priceProxy"
            dense
            inputmode="decimal"
            label="Preis"
            min="0"
            prefix="CHF "
            standout="bg-blue-2 text-dark"
            step="0.05"
            type="number"
          />
        </div>
      </div>
    </q-card-section>

    <q-separator/>

    <q-card-section class="text-right text-h6">
      Total: <b>CHF {{ safeTotal.toFixed(2) }}</b>
    </q-card-section>
  </q-card>
</template>

<script lang="ts">
import {defineComponent} from 'vue'

export default defineComponent({
  name: 'PosSummary',
  props: {
    qty: {type: Number, default: 0},
    price: {type: Number, default: 0},
    total: {type: Number, default: 0}
  },
  emits: ['update:qty', 'update:price'],
  computed: {
    qtyProxy: {
      get(): number {
        return Number(this.qty) || 0
      },
      set(v: unknown) {
        this.$emit('update:qty', Number(v) || 0)
      }
    },
    priceProxy: {
      get(): number {
        return Number(this.price) || 0
      },
      set(v: unknown) {
        this.$emit('update:price', Number(v) || 0)
      }
    },
    safeTotal(): number {
      return Number(this.total) || 0
    }
  }
})
</script>
