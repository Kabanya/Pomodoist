import type { CalendarTokens } from "./actions.ts";
import { GraphError } from "../../pomodoist-outlook-calendar/graph_adapter.ts";
import { record } from "./security.ts";
export class CalendarTokenClient {
  constructor(
    readonly provider: "google" | "outlook",
    readonly clientId: string,
    readonly clientSecret: string,
    readonly redirectUri: string,
    readonly http: typeof fetch = fetch,
  ) {}
  private async token(
    parameters: Record<string, string>,
  ): Promise<Record<string, unknown>> {
    const response = await this.http(
      this.provider === "outlook"
        ? "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        : "https://oauth2.googleapis.com/token",
      {
        method: "POST",
        redirect: "error",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: this.clientId,
          client_secret: this.clientSecret,
          ...parameters,
        }),
      },
    );
    const value = await response.json();
    if (
      !response.ok || !record(value) || typeof value.access_token !== "string"
    ) {
      throw new GraphError(
        record(value) && value.error === "invalid_grant"
          ? 401
          : response.status >= 400
          ? response.status
          : 502,
      );
    }
    return value;
  }
  async exchange(code: string, verifier: string): Promise<CalendarTokens> {
    const token = await this.token({
      grant_type: "authorization_code",
      code,
      code_verifier: verifier,
      redirect_uri: this.redirectUri,
    });
    if (typeof token.refresh_token !== "string") {
      throw new Error("Offline calendar access was not granted.");
    }
    const profile = await this.http(
      this.provider === "outlook"
        ? "https://graph.microsoft.com/v1.0/me?$select=id,mail,userPrincipalName"
        : "https://openidconnect.googleapis.com/v1/userinfo",
      {
        redirect: "error",
        headers: { Authorization: `Bearer ${token.access_token}` },
      },
    );
    if (!profile.ok) throw new GraphError(profile.status);
    const identity = await profile.json();
    const id = this.provider === "outlook" ? identity.id : identity.sub;
    if (typeof id !== "string" || !id) {
      throw new Error("Calendar account identity is missing.");
    }
    return {
      accessToken: String(token.access_token),
      refreshToken: token.refresh_token,
      accountId: id,
      accountEmail: identity.mail ?? identity.email ??
        identity.userPrincipalName ?? null,
    };
  }
  async refresh(
    refreshToken: string,
  ): Promise<{ accessToken: string; refreshToken: string }> {
    const token = await this.token({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });
    return {
      accessToken: String(token.access_token),
      refreshToken: typeof token.refresh_token === "string"
        ? token.refresh_token
        : refreshToken,
    };
  }
}
