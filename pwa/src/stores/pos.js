// src/stores/pos.js
import {defineStore} from 'pinia'

export const usePosStore = defineStore('pos', {
  state: () => ({
    qty: 0,
    price: 0,
    inputTarget: 'price',
    inputBuffer: '',
    pendingCategory: null,
    items: []
  }),
  getters: {
    total(state) {
      const current = (state.qty || 0) * (state.price || 0)
      const lines = state.items.reduce((s, it) => s + it.qty * it.price, 0)
      return current + lines
    }
  },
  actions: {
    setTarget(t) {
      this.inputTarget = t;
      this.inputBuffer = ''
    },
    pickCategory(cat) {
      this.pendingCategory = cat
    },
    inputDigit(d) {
      this.inputBuffer = (this.inputBuffer + d).replace(/^0+(?=\d)/, '')
      this._applyBuffer()
    },
    inputDot() {
      if (!this.inputBuffer.includes('.')) {
        this.inputBuffer = this.inputBuffer === '' ? '0.' : this.inputBuffer + '.'
        this._applyBuffer()
      }
    },
    backspace() {
      this.inputBuffer = this.inputBuffer.slice(0, -1);
      this._applyBuffer()
    },
    clearAll() {
      this.qty = 0;
      this.price = 0;
      this.inputBuffer = ''
    },
    _applyBuffer() {
      const n = Number(this.inputBuffer)
      if (this.inputTarget === 'qty') this.qty = isNaN(n) ? 0 : n
      else this.price = isNaN(n) ? 0 : n
    },
    commitLine() {
      const qty = Number(this.qty) || 0
      const price = Number(this.price) || 0
      if (qty <= 0 || price < 0) return
      this.items.push({id: Date.now(), name: this.pendingCategory?.label || 'Artikel', qty, price})
      this.qty = 0;
      this.price = 0;
      this.inputBuffer = '';
      this.pendingCategory = null
    },
    removeItem(id) {
      this.items = this.items.filter(i => i.id !== id)
    }
  }
})
