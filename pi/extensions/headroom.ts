import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

declare const process: { env: Record<string, string | undefined> };

interface HeadroomContext {
	model?: { baseUrl?: string };
	sessionManager: { getSessionId(): string };
	ui: { setStatus(key: string, value: string | undefined): void };
}

interface ProviderHeadersEvent {
	headers: Record<string, string | null>;
}

const OPENAI_CODEX_PATH = "/backend-api";
const OPENAI_PATH = "/v1";
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "::1", "localhost"]);

export function parseHeadroomBaseUrl(value: string | undefined): string | undefined {
	const raw = value?.trim();
	if (!raw) return undefined;

	const url = new URL(raw);
	if (url.protocol !== "http:") throw new Error("PI_HEADROOM_BASE_URL must use http");
	if (!LOOPBACK_HOSTS.has(url.hostname)) throw new Error("PI_HEADROOM_BASE_URL must use a loopback host");
	if (url.username || url.password) throw new Error("PI_HEADROOM_BASE_URL must not contain credentials");
	if (url.pathname !== "/" || url.search || url.hash) {
		throw new Error("PI_HEADROOM_BASE_URL must not contain a path, query, or fragment");
	}
	if (!url.port) throw new Error("PI_HEADROOM_BASE_URL must include an explicit port");

	return url.origin;
}

function requestUsesHeadroom(ctx: HeadroomContext, baseUrl: string): boolean {
	const modelBaseUrl = ctx.model?.baseUrl;
	return typeof modelBaseUrl === "string" && modelBaseUrl.startsWith(`${baseUrl}/`);
}

export default function headroomExtension(pi: ExtensionAPI): void {
	const baseUrl = parseHeadroomBaseUrl(process.env.PI_HEADROOM_BASE_URL);
	if (!baseUrl) return;

	pi.registerProvider("openai-codex", { baseUrl: `${baseUrl}${OPENAI_CODEX_PATH}` });
	pi.registerProvider("openai", { baseUrl: `${baseUrl}${OPENAI_PATH}` });
	pi.registerProvider("anthropic", { baseUrl });

	pi.on("before_provider_headers", (event: ProviderHeadersEvent, ctx: HeadroomContext) => {
		if (!requestUsesHeadroom(ctx, baseUrl)) return;

		const sessionId = ctx.sessionManager.getSessionId();
		if (!sessionId) throw new Error("Headroom requests require a Pi session id");
		event.headers["x-headroom-session-id"] = sessionId;
	});

	pi.on("session_start", (_event: unknown, ctx: HeadroomContext) => {
		ctx.ui.setStatus("headroom", `headroom ${baseUrl}`);
	});

	pi.on("session_shutdown", (_event: unknown, ctx: HeadroomContext) => {
		ctx.ui.setStatus("headroom", undefined);
	});
}
