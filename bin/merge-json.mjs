// Prints BASE deep-merged with OVERLAY (when that file exists). Objects merge; other values replace.
// Each TOKEN=VALUE argument replaces TOKEN inside every string of the result.
// Usage: node merge-json.mjs BASE OVERLAY [TOKEN=VALUE...]
import { existsSync, readFileSync } from "node:fs";

const [base, overlay, ...replacements] = process.argv.slice(2);
if (!base || !overlay) throw new Error("usage: merge-json BASE OVERLAY [TOKEN=VALUE...]");
const substitutions = replacements.map((pair) => {
	const at = pair.indexOf("=");
	if (at < 1) throw new Error(`replacement must be TOKEN=VALUE: ${pair}`);
	return [pair.slice(0, at), pair.slice(at + 1)];
});
const substitute = (value) => {
	if (typeof value === "string") return substitutions.reduce((text, [token, replacement]) => text.split(token).join(replacement), value);
	if (Array.isArray(value)) return value.map(substitute);
	if (isObject(value)) return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, substitute(item)]));
	return value;
};

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const merge = (left, right) => {
	if (!isObject(left) || !isObject(right)) return right;
	const result = { ...left };
	for (const [key, value] of Object.entries(right)) result[key] = key in result ? merge(result[key], value) : value;
	return result;
};
const read = (path) => {
	const value = JSON.parse(readFileSync(path, "utf8"));
	if (!isObject(value)) throw new Error(`${path} must contain a JSON object`);
	return value;
};

const merged = existsSync(overlay) ? merge(read(base), read(overlay)) : read(base);
process.stdout.write(`${JSON.stringify(substitute(merged), null, 2)}\n`);
