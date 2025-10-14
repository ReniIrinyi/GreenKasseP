export async function openCustomerWindow(): Promise<boolean> {
  const href = location.pathname.includes('#') ? '/#/customer' : '/customer'
  const url = location.origin + href

  const features =
    `popup=yes,resizable=yes,scrollbars=no,width=${screen.availWidth},height=${screen.availHeight}`
  const w = window.open(url, 'greensys-customer', features)
  if (!w) return false

  try {
    const left = window.screenX + window.outerWidth
    w.moveTo(left, window.screenY)
    w.resizeTo(screen.availWidth, screen.availHeight)
  } catch {
  }

  return true
}
