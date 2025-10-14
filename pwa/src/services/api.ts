const BASE = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:5011').replace(/\/+$/, '');

async function request<T>(base: string, path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${base}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(init?.headers || {}) },
    ...init
  });

  const ct   = res.headers.get('content-type') || '';
  const text = await res.text();        
  const isJson = ct.includes('application/json');

  if (!res.ok) {
    let detail = text;
    if (isJson && text) {
      try {
        const j = JSON.parse(text);
        detail = j.detail || j.title || JSON.stringify(j);
      } catch {  }
    }
    const msg = `HTTP ${res.status} ${res.statusText}\n${detail || '(no body)'}`;
    throw new Error(msg);
  }

  if (!text || res.status === 204) {
    return undefined as unknown as T; 
  }

  if (isJson) {
    return JSON.parse(text) as T;
  }
  return text as unknown as T;
}



const get  = <T>(base: string, path: string) => request<T>(base, path)
const post = <T>(base: string, path: string, body?: any) =>
  request<T>(base, path, { method: 'POST', body: body ? JSON.stringify(body) : undefined })
const put  = <T>(base: string, path: string, body?: any) =>
  request<T>(base, path, { method: 'PUT',  body: body ? JSON.stringify(body) : undefined })

export type LoginDto = { user: string; pass: string; licence: string }

export const api = {
  ping:       () => get<{ ok: boolean; at: string }>(BASE, '/api/ping'),
  openDrawer: () => post<{ opened: boolean }>(BASE, '/api/drawer/open'),
  print: (p: { text: string; cut?: boolean; openDrawerAfter?: boolean }) =>
    post<{ printed: boolean }>(BASE, '/api/printer/print', p),
  getDeviceId: () => get<{ deviceId: string }>(BASE, '/api/device-id'),
  login:       (dto: LoginDto) => post<any>(BASE, '/api/login', dto),
  authStatus:  () => get<any>(BASE, '/api/auth/status'),
};

export async function loginKasse(dto: LoginDto) {
  const dev = await api.getDeviceId()
  const res = await api.login(dto)
  const sess = res?.sessData ?? res?.raw ?? res
  localStorage.setItem('gic.session', JSON.stringify(sess))
  return { deviceId: dev.deviceId, session: sess }
}

