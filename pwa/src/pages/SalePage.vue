<template>
  <q-page class="q-pa-md">
    <div style="    display: grid;  grid-template-columns: 1fr 1fr 1fr;grid-gap:36px;    align-items: center;
    justify-content: center;
    height: 100%;">
      <div>
        <div class="text-subtitle1 q-mb-sm">Bon</div>
        <q-list bordered separator>
          <q-item v-for="it in store.items" :key="it.id">
            <q-item-section>
              <q-item-label class="text-weight-medium">{{ it.name }}</q-item-label>
              <q-item-label caption>{{ it.qty }} × CHF {{ it.price.toFixed(2) }}</q-item-label>
            </q-item-section>
            <q-item-section class="text-weight-bold" side>
              CHF {{ (it.qty * it.price).toFixed(2) }}
            </q-item-section>
            <q-item-section side>
              <q-btn dense flat icon="delete" @click="store.removeItem(it.id)"/>
            </q-item-section>
          </q-item>
          <q-separator class="q-my-md"/>

          <q-item v-if="!store.items.length" clickable>
            <q-item-section class="text-grey-7">Noch keine Positionen…</q-item-section>
          </q-item>
        </q-list>
      </div>
      <div class="col-7">
        <q-card bordered class="q-pa-md" flat>
          <div class="row items-center q-mb-sm">
            <div class="text-subtitle1">WarenGruppen</div>
            <q-space/>
            <q-input v-model="search" class="w-200" dense outlined placeholder="Suche / PLU"/>
          </div>
          <CategoryGrid/>
        </q-card>
      </div>
      <div class="col-5">
        <PosSummary
          :price="store.price"
          :qty="store.qty"
          :total="store.total"
          class="q-mb-md"
          @update:qty="v => { store.qty = v; store.setTarget('qty') }"
          @update:price="v => { store.price = v; store.setTarget('price') }"
        />
        <div class="row q-col-gutter-md q-mb-md">
          <div class="col-6">
            <q-btn :color="store.inputTarget==='qty' ? 'teal' : 'grey-4'" class="w-100 q-py-md" label="Menge"
                   unelevated @click="store.setTarget('qty')"/>
          </div>
          <div class="col-6">
            <q-btn :color="store.inputTarget==='price' ? 'primary' : 'grey-4'" class="w-100 q-py-md" label="Preis"
                   unelevated @click="store.setTarget('price')"/>
          </div>
        </div>
        <Numpad
          @backspace="store.backspace"
          @digit="store.inputDigit"
          @dot="store.inputDot"
          @enter="store.commitLine"
        />
        <div class="row q-col-gutter-md q-mt-md">
          <div class="col-6">
            <q-btn class="full-width q-py-md" color="secondary" label="Bon E" @click="onBone()"/>
          </div>
          <div class="col-6">
            <q-btn class="full-width q-py-md" color="negative" label="ENTER" @click="store.commitLine"/>
          </div>
        </div>
      </div>
    </div>
    <!-- Bottom actions -->
    <q-separator class="q-my-md"/>
    <div class="row q-col-gutter-sm">
      <div class="col-12 col-md-auto">
        <q-btn icon="person" label="Kunde" outline/>
      </div>
      <div class="col-12 col-md-auto">
        <q-btn icon="delete_sweep" label="Löschen" outline @click="store.clearAll"/>
      </div>
      <q-space/>
    </div>
  </q-page>
</template>

<script lang="ts" setup>
import {ref} from 'vue'
import {usePosStore} from 'stores/pos'
import CategoryGrid from 'components/CategoryGrid.vue'
import Numpad from 'components/Numpad.vue'
import PosSummary from 'components/PosSummary.vue'
import {api} from 'src/services/api';
import {sendToCustomer} from 'src/services/customer'

const store = usePosStore()
const search = ref('')

async function onBone() {
  try {
    await api.ping();

    const last = store.items.length ? store.items[store.items.length - 1] : null;

    await api.print({ text: 'greenSys Kasse\nDanke!\n', cut: true, openDrawerAfter: true });
    await api.openDrawer();

    sendToCustomer({ total: store.total });
    if (last) {
      sendToCustomer({ lastItem: { name: last.name, qty: last.qty, price: last.price } });
    }
    sendToCustomer({ message: 'Danke!' });
  } catch (err) {
    console.error(err);
  }
}

</script>

<style scoped>
.w-100 {
  width: 100%;
}

.w-200 {
  width: 200px;
}

</style>
