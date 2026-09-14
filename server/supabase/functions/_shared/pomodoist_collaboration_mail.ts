// SMTP uses the server's existing SMTP_* credentials. TLS is mandatory.
export type SmtpConnection = { read(buffer: Uint8Array): Promise<number | null>; write(buffer: Uint8Array): Promise<number>; close(): void };
export type SmtpNetwork = {
  connect(hostname: string, port: number, tls: boolean): Promise<SmtpConnection>;
  startTls(connection: SmtpConnection, hostname: string): Promise<SmtpConnection>;
};
const network: SmtpNetwork = {
  connect: (hostname, port, tls) => tls ? Deno.connectTls({ hostname, port }) : Deno.connect({ hostname, port }),
  startTls: (connection, hostname) => Deno.startTls(connection as Deno.TcpConn, { hostname }),
};
export async function sendInvitationEmail(env: { get(name: string): string | undefined }, recipient: string, url: string, net = network) {
  const hostname = env.get("SMTP_HOST");
  const port = Number(env.get("SMTP_PORT") ?? "587");
  const sender = env.get("SMTP_ADMIN_EMAIL");
  const user = env.get("SMTP_USER");
  const password = env.get("SMTP_PASS");
  const address = /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/;
  if (!hostname || !sender || !address.test(sender) || !address.test(recipient) || !Number.isInteger(port) || port < 1 || port > 65535 || /[\r\n]/.test(url)) throw new Error("Invalid SMTP configuration");
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let socket: SmtpConnection | undefined;
  let buffer = "";
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; socket?.close(); }, 15000);
  async function write(value: string) {
    const bytes = encoder.encode(value);
    let offset = 0;
    while (offset < bytes.length) { const written = await socket!.write(bytes.subarray(offset)); if (written <= 0) throw new Error("SMTP disconnected"); offset += written; }
  }
  async function response(expected: number) {
    let total = 0;
    while (true) {
      while (!buffer.includes("\r\n")) {
        const bytes = new Uint8Array(4096);
        const read = await socket!.read(bytes);
        if (!read) throw new Error("SMTP disconnected");
        total += read;
        if (total > 65536) throw new Error("SMTP response too large");
        buffer += decoder.decode(bytes.subarray(0, read));
      }
      const end = buffer.indexOf("\r\n");
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 2);
      if (!/^\d{3}[ -]/.test(line) || Number(line.slice(0, 3)) !== expected) throw new Error("SMTP rejected invitation");
      if (line[3] === " ") return;
    }
  }
  const command = async (value: string, expected: number) => { await write(`${value}\r\n`); await response(expected); };
  try {
    socket = await net.connect(hostname, port, port === 465);
    if (timedOut) throw new Error("SMTP timed out");
    await response(220); await command("EHLO pomodoist", 250);
    if (port !== 465) {
      await command("STARTTLS", 220);
      socket = await net.startTls(socket, hostname); buffer = "";
      await command("EHLO pomodoist", 250);
    }
    if (user || password) {
      if (!user || !password) throw new Error("Incomplete SMTP credentials");
      const encoded = btoa(String.fromCharCode(...encoder.encode(`\0${user}\0${password}`)));
      await command(`AUTH PLAIN ${encoded}`, 235);
    }
    await command(`MAIL FROM:<${sender}>`, 250); await command(`RCPT TO:<${recipient}>`, 250); await command("DATA", 354);
    const body = `You have been invited to a shared Pomodoist project.\r\n\r\nSign in and explicitly accept the invitation:\r\n${url}\r\n\r\nIf you did not expect this invitation, you can ignore this email.`;
    const message = `From: Pomodoist <${sender}>\r\nTo: <${recipient}>\r\nSubject: Pomodoist project invitation\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n${body}`;
    await write(`${message.replace(/(^|\r\n)\./g, "$1..")}\r\n.\r\n`); await response(250);
    // Once DATA is accepted, a disconnect during QUIT cannot unsend the letter.
    try { await command("QUIT", 221); } catch { /* Delivery already accepted. */ }
  } finally { clearTimeout(timer); try { socket?.close(); } catch { /* Already closed on timeout. */ } }
}
