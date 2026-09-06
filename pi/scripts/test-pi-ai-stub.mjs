export async function complete(...args) {
	if (typeof globalThis.__piTestComplete !== "function") throw new Error("unexpected pi-ai complete call");
	return globalThis.__piTestComplete(...args);
}

export async function completeSimple(...args) {
	if (typeof globalThis.__piTestCompleteSimple === "function") return globalThis.__piTestCompleteSimple(...args);
	return complete(...args);
}

export const Type = { Object: () => ({}), Optional: value => value, String: () => ({}) };
