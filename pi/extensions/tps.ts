import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type TpsContext = { ui?: { setStatus(key: string, value?: string): void; notify(message: string, level: "info"): void } };
type Usage = {
	input?: number;
	output?: number;
	total?: number;
	input_tokens?: number;
	output_tokens?: number;
	total_tokens?: number;
	inputTokens?: number;
	outputTokens?: number;
	totalTokens?: number;
};
type UsageEvent = {
	usage?: Usage;
	message?: { usage?: Usage };
	response?: { usage?: Usage };
	messages?: Array<{ role?: string; usage?: Usage }>;
};

let startedAt = 0;
let timer: ReturnType<typeof setInterval> | undefined;
let lastOutput = 0;

function latestAssistantUsage(messages: UsageEvent["messages"]): Usage | undefined {
	if (!Array.isArray(messages)) return undefined;
	for (let index = messages.length - 1; index >= 0; index -= 1) {
		const message = messages[index];
		if (message?.role === "assistant" && message.usage) return message.usage;
	}
	return undefined;
}

function usageOf(event: UsageEvent): Usage | undefined {
	return event.usage ?? event.message?.usage ?? event.response?.usage ?? latestAssistantUsage(event.messages);
}

function outputTokens(usage: Usage | undefined): number {
	if (!usage) return 0;
	const output = usage.output ?? usage.output_tokens ?? usage.outputTokens ?? 0;
	return typeof output === "number" && Number.isFinite(output) ? output : 0;
}

function label(output: number): string {
	if (startedAt === 0) return "out tok/s: idle";
	const seconds = Math.max(1, (Date.now() - startedAt) / 1000);
	const rate = output / seconds;
	return output > 0 ? `out tok/s ${rate.toFixed(1)} (${output})` : `out tok/s ${rate.toFixed(1)}`;
}

function update(ctx: TpsContext): void {
	ctx.ui?.setStatus("tps", label(lastOutput));
}

export default function tpsExtension(pi: ExtensionAPI) {
	pi.on("agent_start", async (_event: unknown, ctx: TpsContext) => {
		startedAt = Date.now();
		lastOutput = 0;
		update(ctx);
		if (timer) clearInterval(timer);
		timer = setInterval(() => update(ctx), 2_000);
	});

	pi.on("message_end", async (event: UsageEvent, ctx: TpsContext) => {
		lastOutput = Math.max(lastOutput, outputTokens(usageOf(event)));
		update(ctx);
	});

	pi.on("agent_end", async (event: UsageEvent, ctx: TpsContext) => {
		if (timer) clearInterval(timer);
		timer = undefined;
		lastOutput = Math.max(lastOutput, outputTokens(usageOf(event)), outputTokens(latestAssistantUsage(event.messages)));
		update(ctx);
		ctx.ui?.notify(label(lastOutput), "info");
	});

	pi.on("session_shutdown", async (_event: unknown, ctx: TpsContext) => {
		if (timer) clearInterval(timer);
		timer = undefined;
		ctx.ui?.setStatus("tps", undefined);
	});
}
