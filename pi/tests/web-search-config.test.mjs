import assert from "node:assert/strict";
import { existsSync } from "node:fs";
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
