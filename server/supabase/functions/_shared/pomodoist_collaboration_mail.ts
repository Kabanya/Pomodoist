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
export class SmtpDeliveryError extends Error {
  constructor(readonly diagnostic: { stage: string; reason: string; expected?: number; actual?: number; enhanced?: string }) {
    super("Invitation SMTP delivery failed");
  }
}
export async function sendInvitationEmail(env: { get(name: string): string | undefined }, recipient: string, url: string, net = network) {
  const hostname = env.get("SMTP_HOST");
  const port = Number(env.get("SMTP_PORT") ?? "587");
  const sender = env.get("SMTP_ADMIN_EMAIL");
  const user = env.get("SMTP_USER");
  const password = env.get("SMTP_PASS");
  const address = /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/;
  if (!hostname || !sender || !address.test(sender) || !address.test(recipient) || !Number.isInteger(port) || port < 1 || port > 65535 || /[\r\n]/.test(url)) throw new SmtpDeliveryError({ stage: "configuration", reason: "invalid_configuration" });
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let socket: SmtpConnection | undefined;
  let buffer = "";
  let timedOut = false;
  let stage = "connect";
  const timer = setTimeout(() => { timedOut = true; socket?.close(); }, 15000);
  async function write(value: string) {
    const bytes = encoder.encode(value);
    let offset = 0;
    while (offset < bytes.length) { const written = await socket!.write(bytes.subarray(offset)); if (written <= 0) throw new SmtpDeliveryError({ stage, reason: "disconnected" }); offset += written; }
  }
  async function response(expected: number) {
    let total = 0;
    while (true) {
      while (!buffer.includes("\r\n")) {
        const bytes = new Uint8Array(4096);
        const read = await socket!.read(bytes);
        if (!read) throw new SmtpDeliveryError({ stage, reason: "disconnected" });
        total += read;
        if (total > 65536) throw new SmtpDeliveryError({ stage, reason: "response_too_large" });
        buffer += decoder.decode(bytes.subarray(0, read));
      }
      const end = buffer.indexOf("\r\n");
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 2);
      if (!/^\d{3}[ -]/.test(line)) throw new SmtpDeliveryError({ stage, reason: "invalid_response", expected });
      const actual = Number(line.slice(0, 3));
      if (actual !== expected) {
        // SMTP text may contain addresses, credentials or invitation links. Keep codes only.
        const enhanced = line.match(/^\d{3}[ -]([245]\.\d{1,3}\.\d{1,3})(?:\s|$)/)?.[1];
        throw new SmtpDeliveryError({ stage, reason: "rejected", expected, actual, ...(enhanced ? { enhanced } : {}) });
      }
      if (line[3] === " ") return;
    }
  }
  const command = async (value: string, expected: number) => { stage = value.split(" ", 1)[0]; await write(`${value}\r\n`); await response(expected); };
  try {
    socket = await net.connect(hostname, port, port === 465);
    if (timedOut) throw new Error("SMTP timed out");
    stage = "greeting";
    await response(220); await command("EHLO pomodoist", 250);
    if (port !== 465) {
      await command("STARTTLS", 220);
      stage = "tls";
      socket = await net.startTls(socket, hostname); buffer = "";
      await command("EHLO pomodoist", 250);
    }
    if (user || password) {
      if (!user || !password) throw new SmtpDeliveryError({ stage: "configuration", reason: "incomplete_credentials" });
      const encoded = btoa(String.fromCharCode(...encoder.encode(`\0${user}\0${password}`)));
      await command(`AUTH PLAIN ${encoded}`, 235);
    }
    await command(`MAIL FROM:<${sender}>`, 250); await command(`RCPT TO:<${recipient}>`, 250); await command("DATA", 354);
    const body = `You have been invited to a shared Pomodoist project.\r\n\r\nSign in and explicitly accept the invitation:\r\n${url}\r\n\r\nIf you did not expect this invitation, you can ignore this email.`;
    const message = `From: Pomodoist <${sender}>\r\nTo: <${recipient}>\r\nSubject: Pomodoist project invitation\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n${body}`;
    stage = "message";
    await write(`${message.replace(/(^|\r\n)\./g, "$1..")}\r\n.\r\n`); await response(250);
    // Once DATA is accepted, a disconnect during QUIT cannot unsend the letter.
    try { await command("QUIT", 221); } catch { /* Delivery already accepted. */ }
  } catch (error) {
    if (timedOut) throw new SmtpDeliveryError({ stage, reason: "timeout" });
    if (error instanceof SmtpDeliveryError) throw error;
    throw new SmtpDeliveryError({ stage, reason: "transport" });
  } finally { clearTimeout(timer); try { socket?.close(); } catch { /* Already closed on timeout. */ } }
}
