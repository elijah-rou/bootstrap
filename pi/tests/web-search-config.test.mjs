import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import test from "node:test";

const repositoryRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ssrfModule = process.env.PI_WEB_ACCESS_SSRF_MODULE;

test("repository web access config loads and keeps loopback fetches denied", { skip: !ssrfModule }, () => {
	assert.ok(existsSync(ssrfModule), `installed pi-web-access parser missing: ${ssrfModule}`);

	const script = `
		import { loadFetchContentDomainPolicy, loadSsrfConfig, validateRemoteUrl } from ${JSON.stringify(pathToFileURL(ssrfModule).href)};

		const policy = loadFetchContentDomainPolicy();
		const ssrf = loadSsrfConfig();
		const denials = {};
		for (const url of ["http://127.0.0.1", "http://[::1]"]) {
			try {
				await validateRemoteUrl(url, { ...ssrf, domainPolicy: policy });
				denials[url] = null;
			} catch (error) {
				denials[url] = error instanceof Error ? error.message : String(error);
			}
		}
		console.log(JSON.stringify({ policy, ssrf, denials }));
	`;
	const result = spawnSync("bun", ["-e", script], {
		cwd: repositoryRoot,
		encoding: "utf8",
		env: { ...process.env, PI_CODING_AGENT_DIR: join(repositoryRoot, "pi") },
	});

	assert.equal(result.status, 0, result.stderr || result.stdout);
	const loaded = JSON.parse(result.stdout);
	assert.deepEqual(loaded.policy, {
		allow: [],
		deny: ["localhost", "127.0.0.1"],
	});
	assert.deepEqual(loaded.ssrf, {
		allowRanges: ["127.0.0.1/32"],
		trustEnvProxy: false,
	});
	assert.match(loaded.denials["http://127.0.0.1"], /^Blocked hostname by fetch_content domain policy:/);
	assert.match(loaded.denials["http://[::1]"], /^Blocked internal address for ::1:/);
});

test("configured search routing prefers SearXNG, falls back on eligible failures, and preserves explicit selection and cancellation", { skip: !ssrfModule }, () => {
	const routingModule = join(dirname(ssrfModule), "gemini-search.ts");
	assert.ok(existsSync(routingModule), `installed pi-web-access routing missing: ${routingModule}`);
	const temporary = mkdtempSync(join(tmpdir(), "bootstrap-search-routing-"));
	try {
		const config = JSON.parse(readFileSync(join(repositoryRoot, "pi/web-search.json"), "utf8"));
		writeFileSync(join(temporary, "web-search.json"), JSON.stringify({
			...config,
			openaiApiKey: "fixture-not-a-secret",
			openaiSearchProviders: [],
		}), { mode: 0o600 });
		const script = `
			import assert from "node:assert/strict";
			const { search } = await import(${JSON.stringify(pathToFileURL(routingModule).href)});
			const cases = [
				{ name: "default", failure: "none", expected: "searxng", calls: ["searxng"] },
				{ name: "auto", failure: "none", provider: "auto", expected: "searxng", calls: ["searxng"] },
				{ name: "explicit OpenAI", failure: "none", provider: "openai", expected: "openai", calls: ["openai"] },
				{ name: "connection failure", failure: "network", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "service failure", failure: "transient", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "rate limit", failure: "quota", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "invalid JSON", failure: "invalid-response", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "HTTP timeout", failure: "http-timeout", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "Bun deadline", failure: "bun-timeout", expected: "openai", calls: ["searxng", "openai"] },
				{ name: "Node deadline", failure: "node-timeout", errorKind: "aborted", calls: ["searxng"] },
				{ name: "authentication failure", failure: "auth", errorKind: "auth", calls: ["searxng"] },
				{ name: "invalid request", failure: "invalid-request", errorKind: "invalid-request", calls: ["searxng"] },
				{ name: "user cancellation", failure: "aborted", errorKind: "aborted", calls: ["searxng"] },
				{ name: "explicit SearXNG failure", failure: "network", provider: "searxng", errorText: /fetch failed/, calls: ["searxng"] },
				{ name: "empty results", failure: "empty", expected: "searxng", calls: ["searxng"] },
				{ name: "route exhausted", failure: "exhausted", errorText: /Configured search routing exhausted/, calls: ["searxng", "openai"] },
			];
			const observations = [];
			for (const row of cases) {
				const calls = [];
				globalThis.fetch = async (input) => {
					const url = new URL(input);
					if (url.origin === "http://127.0.0.1:8888") {
						calls.push("searxng");
						switch (row.failure) {
							case "network": case "exhausted": throw new TypeError("fetch failed: ECONNREFUSED");
							case "transient": return new Response("Unavailable", { status: 503 });
							case "quota": return new Response("Too many requests", { status: 429 });
							case "invalid-response": return new Response("not JSON");
							case "http-timeout": return new Response("Timed out", { status: 408 });
							case "bun-timeout": throw new DOMException("The operation timed out.", "TimeoutError");
							case "node-timeout": throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
							case "auth": return new Response("Forbidden", { status: 403 });
							case "invalid-request": return new Response("Bad request", { status: 400 });
							case "aborted": throw new DOMException("The operation was aborted.", "AbortError");
							case "empty": return Response.json({ results: [] });
							case "none": return Response.json({ results: [{ title: "Fixture source", url: "https://example.com/source", content: "Source passage" }] });
							default: throw new Error("Unknown failure fixture");
						}
					}
					assert.equal(url.href, "https://api.openai.com/v1/responses", "unexpected outbound destination");
					calls.push("openai");
					if (row.failure === "exhausted") throw new TypeError("fetch failed: ECONNRESET");
					return Response.json({ output: [
						{ type: "web_search_call", action: { sources: [{ title: "Fixture source", url: "https://example.com/source" }] } },
						{ type: "message", content: [{ type: "output_text", text: "Fixture answer.", annotations: [] }] },
					] });
				};
				if (row.errorKind || row.errorText) {
					await assert.rejects(search("fixture query", { provider: row.provider }), (error) => {
						if (row.errorKind) assert.equal(error.kind, row.errorKind, row.name);
						if (row.errorText) assert.match(error.message, row.errorText, row.name);
						return true;
					});
				} else {
					const response = await search("fixture query", { provider: row.provider });
					assert.equal(response.provider, row.expected, row.name);
					assert.equal(response.results.length, row.failure === "empty" ? 0 : 1, row.name);
				}
				assert.deepEqual(calls, row.calls, row.name);
				observations.push({ name: row.name, calls });
			}
			console.log(JSON.stringify(observations));
		`;
		const result = spawnSync("bun", ["-e", script], {
			cwd: repositoryRoot,
			encoding: "utf8",
			timeout: 30_000,
			env: { ...process.env, PI_CODING_AGENT_DIR: temporary, OPENAI_API_KEY: "", SEARXNG_BASE_URL: "http://127.0.0.1:8888" },
		});
		assert.equal(result.status, 0, result.stderr || result.stdout);
		const observations = JSON.parse(result.stdout);
		assert.equal(observations.length, 16);
	} finally {
		rmSync(temporary, { recursive: true, force: true });
	}
});
