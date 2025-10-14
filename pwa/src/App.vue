<template>
  <router-view/>
</template>

<script lang="ts" setup>
import {onMounted} from 'vue'
import {openCustomerWindow} from 'src/services/openCustomer'


onMounted(() => setTimeout(openCustomerWindow, 400))
</script>
