<template>
  <q-layout view="hHh lpR fFf">
    <q-header elevated>
      <q-toolbar>
        <q-icon name="img:/green.svg" class="q-mr-sm" size="36px" />
        <q-space />
        <q-btn
            style="color:#21645f"
            :icon="online ? 'wifi' : 'wifi_off'"
            :title="online ? 'Online' : 'Offline'"
            dense flat
        />
        <q-btn
            dense flat style="color:#21645f"
            icon="settings" title="Einstellungen"
            @click="showLogin = true"
        />
      </q-toolbar>
    </q-header>

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-dialog v-model="showLogin" persistent>
      <q-card style="min-width:380px;max-width:92vw">
        <q-card-section class="row items-center q-gutter-sm">
          <q-icon name="login" size="md" color="primary" />
          <div class="text-h6">Anmeldung</div>
        </q-card-section>

        <q-separator />

        <q-card-section class="q-gutter-md">
          <q-input v-model="licence" label="Licence" dense :disable="loading" />
          <q-input v-model="user" label="User" dense :disable="loading" />
          <q-input
              v-model="pass" label="Passwort" dense
              :type="showPass ? 'text' : 'password'"
              :disable="loading"
              @keyup.enter="doLogin"
          >
            <template #append>
              <q-icon
                  :name="showPass ? 'visibility_off' : 'visibility'"
                  class="cursor-pointer"
                  @click="showPass = !showPass"
              />
            </template>
          </q-input>

          <q-banner v-if="deviceId" dense class="bg-grey-2 text-grey-8">
            Eszköz ID: <b>{{ deviceId }}</b>
          </q-banner>
          <q-banner v-if="error" dense class="bg-red-2 text-negative">
            {{ error }}
          </q-banner>
        </q-card-section>

        <q-separator />

        <q-card-actions align="right">
          <q-btn flat label="Doch nicht" :disable="loading" v-close-popup />
          <q-btn color="primary" :loading="loading" label="Anmeldung" @click="doLogin">
            <template #loading>
              <q-spinner-hourglass class="on-left" /> Belépés…
            </template>
          </q-btn>
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-layout>
</template>

<script lang="ts" setup>
  import { onBeforeUnmount, onMounted, ref } from 'vue'
  import { useQuasar } from 'quasar'
  import { api, loginKasse, type LoginDto } from '@/services/api'

  const $q = useQuasar()

  const online = ref(navigator.onLine)
  function update () { online.value = navigator.onLine }
  onMounted(() => {
    window.addEventListener('online', update)
    window.addEventListener('offline', update)
  })
  onBeforeUnmount(() => {
    window.removeEventListener('online', update)
    window.removeEventListener('offline', update)
  })

  const showLogin = ref(false)
  const loading   = ref(false)
  const error     = ref<string | null>(null)
  const showPass  = ref(false)

  const licence = ref('')
  const user    = ref('')
  const pass    = ref('')

  const deviceId = ref<string>('')

  onMounted(async () => {
    try {
      const dev = await api.getDeviceId()
      deviceId.value = dev.deviceId
    } catch {  }
  })

  async function doLogin () {
    error.value = null
    loading.value = true
    try {
      const dto: LoginDto = { user: user.value, pass: pass.value, licence: licence.value }
      const { session } = await loginKasse(dto)
    //  $q.notify({ type: 'positive', message: "'you're in" })
      showLogin.value = false
    } catch (e:any) {
      error.value = e?.message ?? 'oh no'
    //  $q.notify({ type: 'negative', message: error.value })
    } finally {
      loading.value = false
    }
  }
</script>
