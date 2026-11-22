// A dedicated worker keeps user-selected endpoints outside the document's CSP.
self.onmessage = async ({ data }) => {
  try {
    const url = new URL(data.url);
    const loopback = url.hostname === 'localhost' || url.hostname === '[::1]' ||
      /^127(?:\.\d{1,3}){3}$/.test(url.hostname);
    if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) ||
        url.username || url.password || url.search || url.hash ||
        !url.pathname.endsWith('/chat/completions')) {
      throw new Error('Invalid endpoint');
    }
    const headers = { 'Content-Type': 'application/json' };
    if (data.key) headers.Authorization = `Bearer ${data.key}`;
    const response = await fetch(url, {
      method: 'POST', headers, body: data.body,
      redirect: 'error', credentials: 'omit', mode: 'cors',
      referrerPolicy: 'no-referrer', cache: 'no-store',
    });
    self.postMessage({
      status: response.status,
      body: response.ok ? await response.text() : '',
    });
  } catch {
    self.postMessage({});
  }
};
