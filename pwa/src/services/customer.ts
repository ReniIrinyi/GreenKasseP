const ch = new BroadcastChannel('greensys-customer');

export function sendToCustomer(payload: {
  total?: number,
  lastItem?: { name: string; qty: number; price: number },
  message?: string
}) {
  ch.postMessage(payload);
}
