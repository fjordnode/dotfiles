import { readStoredCredential, type ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { sanitizeTerminalText } from "@narumitw/pi-tui-kit/terminal-text";
import {
	type AccountStore,
	defineOwnMap,
	getOwnCredential,
	type StoredOAuthCredential,
} from "./account-store.js";
import {
	type AccountProviderAdapter,
	type AccountProviderId,
	SUPPORTED_PROVIDER_IDS,
} from "./oauth.js";
import type { ProviderAccountSelections } from "./session-selection.js";
import { createUsageLoader, displayUsage, tokenIdentity, usageCredential, type Usage, type UsageCredential } from "./codex-usage.js";

const LOGIN_ACTION = "Login new account";
const REMOVE_ACTION = "Remove account";
const SWITCH_PROVIDER_ACTION = "Switch provider account";
const SWITCH_ANOTHER_PROVIDER_ACTION = "Switch another provider’s account";

type AccountMenuSession = {
	selections: ProviderAccountSelections;
	error?: string;
};

type AccountMenuOwner = {
	signal: AbortSignal;
	isCurrent(): boolean;
};

type AccountMenuHandlers = {
	login(
		adapter: AccountProviderAdapter,
		name: string,
		signal: AbortSignal,
		isCurrent: () => boolean,
	): Promise<void>;
	switch(
		adapter: AccountProviderAdapter,
		name: string,
		signal: AbortSignal,
		isCurrent: () => boolean,
	): Promise<void>;
	remove(
		adapter: AccountProviderAdapter,
		name: string,
		signal: AbortSignal,
		isCurrent: () => boolean,
	): Promise<void>;
};

type ProviderMenuState = {
	id: AccountProviderId;
	adapter: AccountProviderAdapter;
	active: string | undefined;
	selectionInvalid: boolean;
	accounts: Record<string, StoredOAuthCredential>;
	defaultIdentity?: string;
	usage?: Map<string, Usage>;
};

export async function showAccountsMenu(
	ctx: ExtensionCommandContext,
	store: AccountStore,
	adapters: Map<AccountProviderId, AccountProviderAdapter>,
	session: AccountMenuSession,
	handlers: AccountMenuHandlers,
	owner: AccountMenuOwner,
): Promise<void> {
	if (!ctx.hasUI) {
		ctx.ui.notify("/accounts requires interactive UI (TUI or RPC mode).", "error");
		return;
	}
	const { defineMenu, runMenu } = await import("@narumitw/pi-tui-kit");
	if (!owner.isCurrent()) return;
	let selectedProviderId: AccountProviderId | undefined;
	const loadUsage = createUsageLoader();
	type State = {
		states: Map<AccountProviderId, ProviderMenuState>;
		currentProviderId: AccountProviderId | undefined;
		hasAnyStoredAccount: boolean;
		selectionError?: string;
	};
	type Screen = "main" | "login-providers" | "switch-providers" | "switch-accounts" | "remove";
	type Action =
		| "login-route"
		| "login-provider"
		| "switch-current"
		| "switch-route"
		| "switch-provider"
		| "switch-account"
		| "remove-route"
		| "remove-account";
	const menu = defineMenu<State, Screen, Action, ExtensionCommandContext>({
		start: "main",
		screens: {
			main: ({ state }) => {
				const currentState = state.currentProviderId
					? state.states.get(state.currentProviderId)
					: undefined;
				return {
					kind: "actions",
					title: "Accounts",
					lines: formatAccountsMenuTitle(
						ctx,
						state.states,
						state.hasAnyStoredAccount,
						state.selectionError,
					)
						.split("\n")
						.slice(1),
					items: buildAccountMainItems(
						state.states,
						currentState,
						state.hasAnyStoredAccount,
						state.selectionError !== undefined,
					),
					hint: "close",
				};
			},
			"login-providers": ({ state }) => ({
				kind: "actions",
				title: "Select provider",
				items: sortedProviderStates(state.states).map((provider) => ({
					id: provider.id,
					label: provider.adapter.displayName,
					action: "login-provider",
				})),
				hint: "back",
			}),
			"switch-providers": ({ state }) => ({
				kind: "actions",
				title: "Select provider",
				items: providerStatesWithAccounts(
					state.states,
					state.currentProviderId,
					state.selectionError !== undefined,
				).map((provider) => ({
					id: provider.id,
					label: provider.adapter.displayName,
					action: "switch-provider",
				})),
				hint: "back",
			}),
			"switch-accounts": ({ state }) => {
				const provider = selectedProviderId ? state.states.get(selectedProviderId) : undefined;
				const options = provider
					? switchAccountOptions(
							provider.active,
							Object.keys(provider.accounts),
							provider.selectionInvalid,
						)
					: [];
				return {
					kind: "choice",
					title: provider ? `Switch ${provider.adapter.displayName} account` : "Switch account",
					lines: provider ? [
						`Active: ${activeAccountLabel(provider)}`,
						...(provider.id === "openai-codex" ? ["Remaining limits · highlight a row for reset times (local timezone)"] : []),
						// RPC select only transmits labels, not item descriptions/details.
						...(ctx.mode === "rpc" && provider.id === "openai-codex" ? options.flatMap(option => {
							const name = stripActiveMarker(option);
							const usage = displayUsage(provider.usage?.get(name));
							return [`${option}: ${usage.summary}`, ...usage.details.map(line => `  ${line}`)];
						}) : []),
					] : [],
					action: "switch-account",
					currentItemId: provider?.selectionInvalid ? undefined : accountItemId(provider?.active ?? "default"),
					items: options.map((option) => {
						const accountName = stripActiveMarker(option);
						return {
							id: accountItemId(accountName),
							label: `${option}${accountName === "default" && provider?.defaultIdentity ? ` → ${provider.defaultIdentity}` : ""}${option.startsWith("✓") ? " (active)" : ""}`,
							...(provider?.id === "openai-codex" ? usageMenuDetails(provider.usage?.get(accountName)) : {}),
							disabledReason: "Already selected in this session",
							disabled:
								!provider?.selectionInvalid && accountName === (provider?.active ?? "default"),
						};
					}),
					hint: "back",
				};
			},
			remove: ({ state }) => ({
				kind: "actions",
				title: "Remove account",
				items: removeAccountOptions(state.states, state.currentProviderId).map((option) => ({
					id: removeAccountItemId(option.adapter.id, option.accountName),
					label: option.label,
					action: "remove-account",
				})),
				hint: "back",
			}),
		},
		actions: {
			"login-route": async () => ({ kind: "to", screen: "login-providers" }),
			"login-provider": async ({ itemId, signal }) => {
				if (!isAccountProviderId(itemId)) return { kind: "rejected" };
				const adapter = requireAdapter(adapters, itemId);
				const name = await ctx.ui.input(`Name this ${adapter.displayName} account:`, "work", {
					signal,
				});
				if (name === undefined || !owner.isCurrent()) return { kind: "close" };
				await handlers.login(adapter, name, signal, owner.isCurrent);
				return { kind: "close" };
			},
			"switch-current": async ({ itemId }) => {
				if (!isAccountProviderId(itemId)) return { kind: "rejected" };
				selectedProviderId = itemId;
				return { kind: "to", screen: "switch-accounts" };
			},
			"switch-route": async () => ({ kind: "to", screen: "switch-providers" }),
			"switch-provider": async ({ itemId }) => {
				if (!isAccountProviderId(itemId)) return { kind: "rejected" };
				selectedProviderId = itemId;
				return { kind: "to", screen: "switch-accounts" };
			},
			"switch-account": async ({ itemId, signal }) => {
				const providerId = selectedProviderId;
				if (!providerId) return { kind: "rejected" };
				const latest = await store.readProviderAsync(providerId);
				if (!owner.isCurrent()) return { kind: "close" };
				const accountName = switchAccountOptions(
					session.selections[providerId] ?? undefined,
					Object.keys(latest.accounts),
					session.error !== undefined,
				)
					.map(stripActiveMarker)
					.find((name) => accountItemId(name) === itemId);
				if (!accountName) return { kind: "rejected" };
				await handlers.switch(
					requireAdapter(adapters, providerId),
					accountName,
					signal,
					owner.isCurrent,
				);
				return { kind: "close" };
			},
			"remove-route": async () => ({ kind: "to", screen: "remove" }),
			"remove-account": async ({ itemId, signal }) => {
				const states = await readProviderMenuStates(store, adapters, session);
				if (!owner.isCurrent()) return { kind: "close" };
				const option = removeAccountOptions(states, toProviderId(ctx.model?.provider)).find(
					(candidate) =>
						removeAccountItemId(candidate.adapter.id, candidate.accountName) === itemId,
				);
				if (!option) return { kind: "rejected" };
				const confirmed = await ctx.ui.confirm(
					"Remove account",
					`Remove ${option.adapter.displayName} account "${option.accountName}"?`,
				);
				if (!confirmed || !owner.isCurrent()) return { kind: "close" };
				await handlers.remove(option.adapter, option.accountName, signal, owner.isCurrent);
				return { kind: "close" };
			},
		},
	});
	await runMenu(ctx, menu, {
		getState: async () => {
			const states = await readProviderMenuStates(store, adapters, session);
			const codex = states.get("openai-codex");
			if (codex && (Object.keys(codex.accounts).length || ctx.model?.provider === "openai-codex")) {
				const credentials = new Map<string, UsageCredential>();
				for (const [name, credential] of Object.entries(codex.accounts)) {
					const parsed = usageCredential(credential);
					if (parsed) credentials.set(name, parsed);
				}
				if (!codex.selectionInvalid) {
					try {
						// Active default: use effective runtime auth. Inactive default: read Pi's
						// stored OAuth snapshot without refreshing it or changing the selection.
						const stored = codex.active ? readStoredCredential("openai-codex") : undefined;
						const resolved = !codex.active ? await ctx.modelRegistry.getProviderAuth("openai-codex") : undefined;
						const parsed = usageCredential(stored?.type === "oauth" ? stored : { access: resolved?.auth?.apiKey });
						if (parsed) {
							credentials.set("default", parsed);
							codex.defaultIdentity = defaultAccountIdentity(parsed, codex.accounts);
						}
					} catch { /* Keep default identity/limits explicitly unavailable. No raw auth errors. */ }
				}
				if (!owner.isCurrent() || owner.signal.aborted) throw new Error("Account menu closed");
				codex.usage = await loadUsage(credentials, owner.signal);
			}
			const missingSelection = [...states.values()].some((state) => state.selectionInvalid);
			return {
				states,
				currentProviderId: toProviderId(ctx.model?.provider),
				hasAnyStoredAccount: [...states.values()].some((state) => accountNames(state).length > 0),
				selectionError:
					session.error ??
					(missingSelection
						? "A selected account is no longer available. Choose an account or default to recover."
						: undefined),
			};
		},
		signal: owner.signal,
		isCurrent: owner.isCurrent,
	});
}

async function readProviderMenuStates(
	store: AccountStore,
	adapters: Map<AccountProviderId, AccountProviderAdapter>,
	session: AccountMenuSession,
): Promise<Map<AccountProviderId, ProviderMenuState>> {
	const data = await store.readAsync();
	const states = new Map<AccountProviderId, ProviderMenuState>();
	for (const id of adapters.keys()) {
		const state = data.providers[id] ?? { accounts: defineOwnMap({}) };
		const active = session.selections[id] ?? undefined;
		states.set(id, {
			id,
			adapter: requireAdapter(adapters, id),
			active,
			selectionInvalid:
				session.error !== undefined ||
				(active !== undefined && !getOwnCredential(state.accounts, active)),
			accounts: state.accounts,
		});
	}
	return states;
}

export function defaultAccountIdentity(credential: UsageCredential, accounts: Record<string, StoredOAuthCredential>): string {
	const matches = Object.entries(accounts).filter(([, account]) => account.accountId === credential.accountId).map(([name]) => name);
	const identity = tokenIdentity(credential.access);
	return sanitizeTerminalText(matches.length ? matches.join(", ") : identity?.email ?? `account …${credential.accountId.slice(-8)}`);
}

function activeAccountLabel(state: ProviderMenuState): string {
	if (state.selectionInvalid) return "recovery required";
	if (state.active) return sanitizeTerminalText(state.active);
	return state.id === "openai-codex" ? `default → ${state.defaultIdentity ?? "identity unavailable"}` : "default";
}

function usageMenuDetails(usage: Usage | undefined) {
	const display = displayUsage(usage);
	return { description: display.summary, details: display.details };
}

function formatAccountsMenuTitle(
	ctx: ExtensionCommandContext,
	states: Map<AccountProviderId, ProviderMenuState>,
	hasAnyStoredAccount: boolean,
	selectionError?: string,
): string {
	if (!hasAnyStoredAccount && !selectionError && !states.get("openai-codex")?.defaultIdentity) {
		return "Accounts\n\nNo saved accounts yet.\n\nWhat do you want to do?";
	}
	const activeLines = sortedProviderStates(states).flatMap((state) => {
		const lines = [`  ${state.adapter.displayName}: ${activeAccountLabel(state)}`];
		if (state.id === "openai-codex" && !state.selectionInvalid && state.usage) {
			const usage = displayUsage(state.usage.get(state.active ?? "default"));
			lines.push(`    ${usage.summary}`, ...usage.details.map(line => `    ${line}`));
		}
		return lines;
	});
	return [
		"Accounts",
		...(selectionError ? ["", `Selection error: ${sanitizeTerminalText(selectionError)}`] : []),
		"",
		"Current model:",
		`  ${formatCurrentModel(ctx)}`,
		"",
		"Active accounts:",
		...activeLines,
		"",
		"What do you want to do?",
	].join("\n");
}

function formatCurrentModel(ctx: ExtensionCommandContext): string {
	if (!ctx.model) return "(none)";
	const providerId = toProviderId(ctx.model.provider);
	const providerName = providerId ? providerDisplayName(providerId) : ctx.model.provider;
	return sanitizeTerminalText(`${providerName} / ${ctx.model.id}`);
}

function buildAccountMainItems(
	states: Map<AccountProviderId, ProviderMenuState>,
	currentState: ProviderMenuState | undefined,
	hasAnyStoredAccount: boolean,
	selectionInvalid = false,
): Array<{
	id: string;
	label: string;
	action: "login-route" | "switch-current" | "switch-route" | "remove-route";
}> {
	if (!hasAnyStoredAccount && !selectionInvalid) {
		return [{ id: "login", label: LOGIN_ACTION, action: "login-route" }];
	}
	const currentHasAccounts = currentState ? accountNames(currentState).length > 0 : false;
	if (currentState && (currentHasAccounts || currentState.selectionInvalid)) {
		return [
			{
				id: currentState.id,
				label: switchCurrentProviderAction(currentState.adapter),
				action: "switch-current",
			},
			{ id: "login", label: LOGIN_ACTION, action: "login-route" },
			...(hasAnyStoredAccount
				? [{ id: "remove", label: REMOVE_ACTION, action: "remove-route" as const }]
				: []),
			...(providerStatesWithAccounts(states, currentState.id, selectionInvalid).length > 0
				? [
						{
							id: "switch-other",
							label: SWITCH_ANOTHER_PROVIDER_ACTION,
							action: "switch-route" as const,
						},
					]
				: []),
		];
	}
	return [
		{ id: "login", label: LOGIN_ACTION, action: "login-route" },
		{
			id: "switch-provider",
			label: currentState ? SWITCH_ANOTHER_PROVIDER_ACTION : SWITCH_PROVIDER_ACTION,
			action: "switch-route",
		},
		...(hasAnyStoredAccount
			? [{ id: "remove", label: REMOVE_ACTION, action: "remove-route" as const }]
			: []),
	];
}

function accountItemId(accountName: string): string {
	return `account:${encodeURIComponent(accountName)}`;
}

function removeAccountItemId(providerId: AccountProviderId, accountName: string): string {
	return `${providerId}:${encodeURIComponent(accountName)}`;
}

function switchCurrentProviderAction(adapter: AccountProviderAdapter): string {
	return `Switch ${adapter.displayName} account`;
}

function sortedProviderStates(
	states: Map<AccountProviderId, ProviderMenuState>,
): ProviderMenuState[];
function sortedProviderStates(states: readonly ProviderMenuState[]): ProviderMenuState[];
function sortedProviderStates(
	states: Map<AccountProviderId, ProviderMenuState> | readonly ProviderMenuState[],
): ProviderMenuState[] {
	const values = Array.isArray(states) ? [...states] : [...states.values()];
	return values.sort((left, right) =>
		left.adapter.displayName.localeCompare(right.adapter.displayName),
	);
}

function providerStatesWithAccounts(
	states: Map<AccountProviderId, ProviderMenuState>,
	excludeProviderId?: AccountProviderId,
	includeEmpty = false,
): ProviderMenuState[] {
	return sortedProviderStates(states).filter(
		(state) => state.id !== excludeProviderId && (includeEmpty || accountNames(state).length > 0),
	);
}

function accountNames(state: ProviderMenuState): string[] {
	return Object.keys(state.accounts).sort();
}

function switchAccountOptions(
	activeName: string | undefined,
	names: string[],
	selectionInvalid = false,
): string[] {
	const active = activeName ?? "default";
	const sortedNames = [...names].sort();
	if (selectionInvalid) return [...sortedNames, "default"];
	const options = [formatSwitchAccountOption(active, true)];
	for (const name of sortedNames) {
		if (name !== active) options.push(formatSwitchAccountOption(name, false));
	}
	if (active !== "default") options.push(formatSwitchAccountOption("default", false));
	return options;
}

function formatSwitchAccountOption(name: string, active: boolean): string {
	return active ? `✓ ${name}` : name;
}

function stripActiveMarker(value: string): string {
	return value.replace(/^✓\s+/, "");
}

function removeAccountOptions(
	states: Map<AccountProviderId, ProviderMenuState>,
	currentProviderId?: AccountProviderId,
): Array<{ label: string; adapter: AccountProviderAdapter; accountName: string }> {
	const providerStates = providerStatesWithAccounts(states);
	if (currentProviderId) {
		const currentIndex = providerStates.findIndex((state) => state.id === currentProviderId);
		if (currentIndex > 0) {
			const [current] = providerStates.splice(currentIndex, 1);
			if (current) providerStates.unshift(current);
		}
	}
	return providerStates.flatMap((state) =>
		accountNames(state).map((accountName) => ({
			label: `${state.adapter.displayName} · ${accountName}`,
			adapter: state.adapter,
			accountName,
		})),
	);
}

function providerDisplayName(providerId: AccountProviderId): string {
	switch (providerId) {
		case "anthropic":
			return "Anthropic";
		case "github-copilot":
			return "GitHub Copilot";
		case "kimi-coding":
			return "Kimi For Coding";
		case "openai-codex":
			return "OpenAI Codex";
		case "openrouter":
			return "OpenRouter";
		case "radius":
			return "Radius";
		case "xai":
			return "xAI";
	}
}

function requireAdapter(
	adapters: Map<AccountProviderId, AccountProviderAdapter>,
	providerId: AccountProviderId,
): AccountProviderAdapter {
	const adapter = adapters.get(providerId);
	if (!adapter) throw new Error(`Unsupported account provider: ${providerId}`);
	return adapter;
}

function toProviderId(value: string | undefined): AccountProviderId | undefined {
	return value && isAccountProviderId(value) ? value : undefined;
}

function isAccountProviderId(value: string): value is AccountProviderId {
	return (SUPPORTED_PROVIDER_IDS as readonly string[]).includes(value);
}
