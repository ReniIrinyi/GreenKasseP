export default [
  {
    path: '/',
    component: () => import('layouts/MainLayout.vue'),
    children: [
      {path: '', component: () => import('pages/SalePage.vue')},
      {path: 'customer', component: () => import('pages/CustomerDisplay.vue')}
    ]
  }
]
