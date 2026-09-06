import assert from "node:assert/strict";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type SelectedModel = NonNullable<ExtensionContext["model"]>;
type ModelIdentity = Pick<SelectedModel, "provider" | "api" | "id" | "baseUrl">;

// Explicit lists prevent new models, fine-tunes, and compatible gateways from inheriting paid options.
// OpenAI accepts priority as an alias for fast, including on newer models:
// https://developers.openai.com/api/docs/guides/priority-processing
// https://developers.openai.com/api/docs/pricing.md (Fast pricing data)
const OPENAI_MODELS = new Set([
  "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
  "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini",
  "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o", "gpt-4o-2024-05-13", "gpt-4o-mini", "o3", "o4-mini",
]);
// ChatGPT-backed Codex has different availability from the API, including model retirements.
// https://developers.openai.com/codex/speed/
// https://developers.openai.com/codex/models/
const CODEX_MODELS = new Set(["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]);

function supportsFast(model: ModelIdentity | undefined): boolean {
  if (!model) return false;
  switch (model.provider) {
    case "openai": {
      if (model.api !== "openai-responses" && model.api !== "openai-completions") return false;
      if (!OPENAI_MODELS.has(model.id)) return false;
      if (model.id === "gpt-6-astra") {
        const endpoint = URL.parse(model.baseUrl);
        if (!endpoint || endpoint.hostname === "eu.api.openai.com") return false;
      }
      return true;
    }
    case "openai-codex":
      return model.api === "openai-codex-responses" && CODEX_MODELS.has(model.id);
    default:
      return false;
  }
}

export default function (pi: ExtensionAPI): void {
  // No persistence: a reload, resume, fork, or model change must not silently restore premium billing.
  let selection: { model: ModelIdentity; enabled: boolean } | undefined;

  function matchesSelection(model: ModelIdentity | undefined): boolean {
    return selection !== undefined && model !== undefined
      && selection.model.provider === model.provider && selection.model.api === model.api
      && selection.model.id === model.id && selection.model.baseUrl === model.baseUrl;
  }

  function reset(ctx: ExtensionContext): void {
    selection = undefined;
    if (ctx.hasUI) ctx.ui.setStatus("fast", undefined);
    return;
  }

  pi.on("session_start", (_event, ctx) => { reset(ctx); return; });
  pi.on("session_shutdown", (_event, ctx) => { reset(ctx); return; });
  pi.on("model_select", (event, ctx) => {
    if (selection && !matchesSelection(event.model)) {
      reset(ctx);
      if (ctx.hasUI) ctx.ui.notify("Fast mode reset after model change; provider defaults apply.", "info");
    }
    return;
  });

  pi.registerCommand("fast", {
    description: "Toggle paid fast processing for the selected model: /fast [on|off|status]",
    getArgumentCompletions: (prefix) => {
      const items = ["on", "off", "status"].filter((value) => value.startsWith(prefix)).map((value) => ({ value, label: value }));
      return items.length > 0 ? items : null;
    },
    handler: async (args, ctx) => {
      if (!ctx.hasUI) return;
      const action = args.trim().toLowerCase();
      if (!["", "on", "off", "status"].includes(action)) {
        ctx.ui.notify("Usage: /fast [on|off|status]", "warning");
        return;
      }
      const model = ctx.model;
      if (!model || !supportsFast(model)) {
        // In Pi 0.84.4 the header hook precedes Anthropic's internal beta assembly.
        // Setting anthropic-beta there replaces, rather than extends, those headers.
        // Do not duplicate upstream auth/thinking headers to work around that boundary.
        const reason = model?.provider === "anthropic" ? " Pi's header hook cannot safely merge Anthropic's required fast-mode beta header." : "";
        ctx.ui.notify(model ? `Fast mode not supported for ${model.provider}/${model.id} on this API/endpoint.${reason}` : "Fast mode unavailable: no model selected.", "warning");
        return;
      }
      const current = matchesSelection(model) ? selection : undefined;
      if (action === "status") {
        const status = current ? (current.enabled ? "on (requested, not guaranteed)" : "off (standard requested)") : "off (provider defaults unchanged)";
        ctx.ui.notify(`Fast mode ${status}: ${model.provider}/${model.id}.`, "info");
        return;
      }
      // Change the next turn, never an in-flight request or its retries.
      if (!ctx.isIdle()) {
        ctx.ui.notify("Wait for Pi to finish or abort the current turn before changing fast mode.", "warning");
        return;
      }
      const enabled = action === "" ? !current?.enabled : action === "on";
      selection = { model: { provider: model.provider, api: model.api, id: model.id, baseUrl: model.baseUrl }, enabled };
      ctx.ui.setStatus("fast", enabled ? "fast: requested" : "fast: off");
      const notice = enabled
        ? `Fast mode requested for ${model.provider}/${model.id}. Higher cost or credit/quota usage; provider access and capacity apply.`
        : `Fast mode off for ${model.provider}/${model.id}; standard processing requested.`;
      ctx.ui.notify(notice, enabled ? "warning" : "info");
      return;
    },
  });

  pi.on("before_provider_request", (event, ctx) => {
    if (!selection || !matchesSelection(ctx.model)) return undefined;
    if (!supportsFast(ctx.model)) return undefined;
    const payload = event.payload;
    assert(typeof payload === "object" && payload !== null && !Array.isArray(payload), "Expected a provider payload object");
    // A fallback or another extension can select a different wire model. Never charge it implicitly.
    if (!("model" in payload) || payload.model !== selection.model.id) return undefined;
    return { ...payload, service_tier: selection.enabled ? "priority" : "default" };
  });
  return;
}
