import type {
  ExtensionAPI,
  KeybindingsManager,
  Theme,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

type BashInput = { command?: unknown };
type ApprovalChoice = "once" | "session" | "deny";
type GuardMatch = { reason: string; sessionCommand: string };

const MAX_PREVIEW = 700;

const DOCKER_COMPOSE_ACTIONS = new Set([
  "build",
  "down",
  "kill",
  "pause",
  "restart",
  "rm",
  "stop",
  "unpause",
]);
const DOCKER_DIRECT_ACTIONS = new Set(["down", "kill", "pause", "restart", "rm", "stop", "unpause"]);
const DOCKER_RESOURCES = new Set(["container", "image", "network", "system", "volume"]);
const DOCKER_RESOURCE_ACTIONS = new Set(["prune", "rm"]);
const PROXMOX_GUEST_ACTIONS = new Set([
  "clone",
  "create",
  "destroy",
  "migrate",
  "move_disk",
  "reboot",
  "reset",
  "restore",
  "shutdown",
  "start",
  "stop",
]);
const SYSTEMCTL_ACTIONS = new Set([
  "daemon-reexec",
  "daemon-reload",
  "disable",
  "enable",
  "halt",
  "isolate",
  "mask",
  "poweroff",
  "preset",
  "reboot",
  "reenable",
  "reload",
  "restart",
  "revert",
  "start",
  "stop",
  "unmask",
]);
const SERVICE_ACTIONS = new Set(["force-reload", "reload", "restart", "start", "stop"]);
const PACKAGE_ACTIONS: Record<string, Set<string>> = {
  apt: new Set(["autoremove", "dist-upgrade", "full-upgrade", "install", "purge", "remove", "upgrade"]),
  "apt-get": new Set(["autoremove", "dist-upgrade", "install", "purge", "remove", "upgrade"]),
  dnf: new Set(["autoremove", "downgrade", "install", "remove", "swap", "update", "upgrade"]),
  yum: new Set(["autoremove", "downgrade", "install", "remove", "swap", "update", "upgrade"]),
  zypper: new Set(["dist-upgrade", "dup", "install", "patch", "remove", "update"]),
};
const ACCOUNT_COMMANDS = new Set([
  "groupadd",
  "groupdel",
  "groupmod",
  "chpasswd",
  "passwd",
  "useradd",
  "userdel",
  "usermod",
]);
const PARTED_MUTATIONS = new Set([
  "disk_set",
  "mklabel",
  "mkpart",
  "name",
  "rescue",
  "resizepart",
  "rm",
  "set",
  "toggle",
]);

function preview(command: string): string {
  const normalized = command.trim();
  return normalized.length > MAX_PREVIEW
    ? `${normalized.slice(0, MAX_PREVIEW - 1)}…`
    : normalized;
}

function safeForTerminal(text: string): string {
  return text.replace(/\x1b/g, "␛").replace(/\r/g, "");
}

function splitShellCommands(command: string): string[] {
  const commands: string[] = [];
  let current = "";
  let quote: "'" | '"' | "`" | undefined;
  let escaped = false;

  const push = () => {
    const segment = current.trim();
    if (segment) commands.push(segment);
    current = "";
  };

  for (let index = 0; index < command.length; index++) {
    const character = command[index]!;
    if (escaped) {
      current += character;
      escaped = false;
      continue;
    }
    if (character === "\\" && quote !== "'") {
      current += character;
      escaped = true;
      continue;
    }
    if (quote) {
      current += character;
      if (character === quote) quote = undefined;
      continue;
    }
    if (character === "'" || character === '"' || character === "`") {
      quote = character;
      current += character;
      continue;
    }
    if (character === ";" || character === "\n" || character === "|" || character === "&") {
      push();
      if ((character === "|" || character === "&") && command[index + 1] === character) index++;
      continue;
    }
    current += character;
  }

  push();
  return commands;
}

function shellWords(command: string): string[] {
  return (
    command.match(/(?:[^\s"'`]+|"(?:\\.|[^"])*"|'[^']*'|`[^`]*`)+/g)?.map((word) => {
      if (
        word.length >= 2 &&
        ((word.startsWith('"') && word.endsWith('"')) ||
          (word.startsWith("'") && word.endsWith("'")) ||
          (word.startsWith("`") && word.endsWith("`")))
      ) {
        return word.slice(1, -1);
      }
      return word;
    }) ?? []
  );
}

function executableName(token: string | undefined): string {
  return (token ?? "").split("/").at(-1)?.toLowerCase() ?? "";
}

function stripCommandPrefixes(inputWords: string[]): { words: string[]; privileged: boolean } {
  const words = [...inputWords];
  let privileged = false;

  while (words[0] && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0])) words.shift();
  if (executableName(words[0]) === "env") {
    words.shift();
    while (words[0]?.startsWith("-") || (words[0] && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0]))) words.shift();
  }
  if (executableName(words[0]) === "command" || executableName(words[0]) === "exec") words.shift();

  if (executableName(words[0]) === "sudo") {
    privileged = true;
    words.shift();
    const optionsWithValues = new Set([
      "--chroot",
      "--close-from",
      "--command-timeout",
      "--group",
      "--host",
      "--prompt",
      "--role",
      "--type",
      "--user",
      "-C",
      "-g",
      "-h",
      "-p",
      "-R",
      "-T",
      "-u",
    ]);
    while (words[0]?.startsWith("-")) {
      const option = words.shift()!;
      if (option === "--") break;
      if (!option.includes("=") && optionsWithValues.has(option)) words.shift();
    }
    while (words[0] && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0])) words.shift();
  }

  return { words, privileged };
}

function optionLetters(words: string[]): string {
  return words
    .filter((word) => /^-[^-]/.test(word))
    .map((word) => word.slice(1))
    .join("");
}

function hasLongOption(words: string[], ...options: string[]): boolean {
  return words.some((word) => options.includes(word.split("=")[0]!));
}

function rmScope(words: string[]): string {
  const letters = optionLetters(words.slice(1));
  const recursive = /[rR]/.test(letters) || hasLongOption(words, "--recursive");
  const force = /f/.test(letters) || hasLongOption(words, "--force");
  if (recursive && force) return "rm -rf";
  if (recursive) return "rm -r";
  if (force) return "rm -f";
  return "rm";
}

function recursiveForceScope(executable: string, words: string[]): string | undefined {
  const letters = optionLetters(words.slice(1));
  const recursive = /R/.test(letters) || hasLongOption(words, "--recursive");
  const force = /f/.test(letters) || hasLongOption(words, "--force", "--silent", "--quiet");
  if (!recursive && !force) return undefined;
  if (recursive && force) return `${executable} -Rf`;
  return `${executable} ${recursive ? "-R" : "-f"}`;
}

function firstAction(words: string[], actions: Set<string>): string | undefined {
  return words.map((word) => word.toLowerCase()).find((word) => actions.has(word));
}

function classifyDocker(words: string[]): GuardMatch | undefined {
  const args = words.slice(1).map((word) => word.toLowerCase());
  if (args[0] === "build") return { reason: "Docker image build", sessionCommand: "docker build" };
  if (args[0] === "buildx" && args[1] === "build") {
    return { reason: "Docker image build", sessionCommand: "docker buildx build" };
  }
  if (args[0] === "compose" && DOCKER_COMPOSE_ACTIONS.has(args[1] ?? "")) {
    const action = args[1]!;
    return {
      reason: action === "build" ? "Docker image build" : "Docker service or resource change",
      sessionCommand: `docker compose ${action}`,
    };
  }
  if (DOCKER_DIRECT_ACTIONS.has(args[0] ?? "")) {
    return {
      reason: "Docker service or resource change",
      sessionCommand: `docker ${args[0]}`,
    };
  }
  if (DOCKER_RESOURCES.has(args[0] ?? "") && DOCKER_RESOURCE_ACTIONS.has(args[1] ?? "")) {
    return {
      reason: "Docker service or resource change",
      sessionCommand: `docker ${args[0]} ${args[1]}`,
    };
  }
  return undefined;
}

function classifyGit(words: string[]): GuardMatch | undefined {
  const originalArgs = words.slice(1);
  const args = originalArgs.map((word) => word.toLowerCase());
  const action = args[0];
  if (
    action === "push" &&
    (args.some((arg) => arg === "--force" || arg === "--force-with-lease") || /f/.test(optionLetters(args)))
  ) {
    return { reason: "history-rewriting Git operation", sessionCommand: "git push --force" };
  }
  if (action === "push" && args.includes("--delete")) {
    return { reason: "remote Git ref deletion", sessionCommand: "git push --delete" };
  }
  if (action === "reset" && args.includes("--hard")) {
    return { reason: "history-rewriting Git operation", sessionCommand: "git reset --hard" };
  }
  if (action === "clean" && (/[f]/.test(optionLetters(args)) || args.includes("--force"))) {
    return { reason: "untracked file removal", sessionCommand: "git clean -f" };
  }
  if (action === "checkout" && args.includes("--")) {
    return { reason: "working-tree file replacement", sessionCommand: "git checkout --" };
  }
  if (action === "restore") {
    return { reason: "working-tree file replacement", sessionCommand: "git restore" };
  }
  if (action === "branch" && originalArgs.includes("-D")) {
    return { reason: "Git branch deletion", sessionCommand: "git branch -D" };
  }
  if (action === "stash" && (args[1] === "drop" || args[1] === "clear")) {
    return { reason: "Git stash deletion", sessionCommand: `git stash ${args[1]}` };
  }
  if (action === "worktree" && args[1] === "remove") {
    return { reason: "Git worktree removal", sessionCommand: "git worktree remove" };
  }
  return undefined;
}

function classifyFirewall(executable: string, words: string[]): GuardMatch | undefined {
  const args = words.slice(1).map((word) => word.toLowerCase());
  if (executable === "ip") {
    const area = args.find((arg) => ["addr", "address", "link", "route"].includes(arg));
    const action = args.find((arg) => ["add", "del", "delete", "replace", "set"].includes(arg));
    if (!area || !action) return undefined;
    return {
      reason: "firewall or network configuration change",
      sessionCommand: `ip ${area === "address" ? "addr" : area} ${action === "delete" ? "del" : action}`,
    };
  }
  if (executable === "networkctl") {
    const action = args.find((arg) => ["down", "reconfigure", "reload", "up"].includes(arg));
    return action
      ? { reason: "firewall or network configuration change", sessionCommand: `networkctl ${action}` }
      : undefined;
  }
  if (executable === "nmcli") {
    const action = args.find((arg) => ["connect", "delete", "disconnect", "down", "modify", "up"].includes(arg));
    return action
      ? { reason: "firewall or network configuration change", sessionCommand: `nmcli ${action}` }
      : undefined;
  }
  if (["iptables", "ip6tables"].includes(executable)) {
    const action = args.find((arg) => /^-(?:a|d|f|i|n|p|r|x|z)/i.test(arg)) ?? "change";
    return {
      reason: "firewall or network configuration change",
      sessionCommand: `${executable} ${action}`,
    };
  }
  if (executable === "nft") {
    const action = args.find((arg) => ["add", "delete", "flush", "insert", "replace", "reset"].includes(arg));
    return action
      ? { reason: "firewall or network configuration change", sessionCommand: `nft ${action}` }
      : undefined;
  }
  if (executable === "ufw") {
    const action = args.find((arg) => ["allow", "delete", "deny", "disable", "enable", "reject", "reload", "reset"].includes(arg));
    return action
      ? { reason: "firewall or network configuration change", sessionCommand: `ufw ${action}` }
      : undefined;
  }
  if (executable === "firewall-cmd") {
    const action = args.find((arg) => /^--(?:add|complete-reload|direct|permanent|reload|remove)/.test(arg));
    return action
      ? { reason: "firewall or network configuration change", sessionCommand: `firewall-cmd ${action.split("=")[0]}` }
      : undefined;
  }
  return undefined;
}

function classifyPackage(executable: string, words: string[]): GuardMatch | undefined {
  if (executable === "pacman") {
    const args = words.slice(1);
    const letters = optionLetters(args);
    let operation: string | undefined;
    if (letters.includes("R") || args.includes("--remove")) operation = "-R";
    else if (letters.includes("U") || args.includes("--upgrade")) operation = "-U";
    else if (letters.includes("S") || args.includes("--sync")) {
      const readOnlySync = /[silgp]/.test(letters) && !/[yucw]/.test(letters);
      if (!readOnlySync) operation = "-S";
    }
    return operation
      ? { reason: "system package change", sessionCommand: `pacman ${operation}` }
      : undefined;
  }
  const action = firstAction(words.slice(1), PACKAGE_ACTIONS[executable] ?? new Set<string>());
  return action
    ? { reason: "system package change", sessionCommand: `${executable} ${action}` }
    : undefined;
}

function classifyFind(words: string[]): GuardMatch | undefined {
  const lower = words.map((word) => word.toLowerCase());
  if (lower.includes("-delete")) {
    return { reason: "file removal", sessionCommand: "find -delete" };
  }
  const execIndex = lower.findIndex((word) => word === "-exec" || word === "-execdir");
  if (execIndex >= 0) {
    const nestedExecutable = executableName(words[execIndex + 1]);
    if (nestedExecutable === "rm") {
      return { reason: "file removal", sessionCommand: `find -exec ${rmScope(words.slice(execIndex + 1))}` };
    }
    if (nestedExecutable === "unlink" || nestedExecutable === "shred") {
      return { reason: "file removal", sessionCommand: `find -exec ${nestedExecutable}` };
    }
  }
  return undefined;
}

function classifySegment(segment: string): GuardMatch[] {
  const rawWords = shellWords(segment);
  const { words, privileged } = stripCommandPrefixes(rawWords);
  const executable = executableName(words[0]);
  if (!executable) return [];

  let match: GuardMatch | undefined;
  if (executable === "rm") match = { reason: "file removal", sessionCommand: rmScope(words) };
  else if (executable === "mv") match = { reason: "file move or rename", sessionCommand: "mv" };
  else if (["unlink", "shred", "truncate"].includes(executable)) {
    match = { reason: "file removal or destructive overwrite", sessionCommand: executable };
  } else if (["chmod", "chown", "chgrp"].includes(executable)) {
    const scope = recursiveForceScope(executable, words);
    if (scope) match = { reason: "recursive or forced permission change", sessionCommand: scope };
  } else if (executable === "setfacl") {
    const recursive = /R/.test(optionLetters(words.slice(1))) || hasLongOption(words, "--recursive");
    match = {
      reason: "access-control list change",
      sessionCommand: recursive ? "setfacl -R" : "setfacl",
    };
  } else if (executable === "find") match = classifyFind(words);
  else if (executable === "xargs") {
    const nestedIndex = words.findIndex((word, index) => index > 0 && ["rm", "shred", "unlink"].includes(executableName(word)));
    if (nestedIndex >= 0) {
      const nestedExecutable = executableName(words[nestedIndex]);
      match = {
        reason: "file removal",
        sessionCommand: nestedExecutable === "rm" ? `xargs ${rmScope(words.slice(nestedIndex))}` : `xargs ${nestedExecutable}`,
      };
    }
  } else if (executable === "docker") match = classifyDocker(words);
  else if (executable === "scp" || executable === "rsync") {
    match = { reason: "remote file transfer", sessionCommand: executable };
  } else if (executable === "qm" || executable === "pct") {
    const action = firstAction(words.slice(1), PROXMOX_GUEST_ACTIONS);
    if (action) match = { reason: "Proxmox guest change", sessionCommand: `${executable} ${action}` };
  } else if (executable === "pvesh") {
    const action = firstAction(words.slice(1), new Set(["create", "delete", "set"]));
    if (action) match = { reason: "Proxmox API change", sessionCommand: `pvesh ${action}` };
  } else if (["firewall-cmd", "ip", "ip6tables", "iptables", "networkctl", "nft", "nmcli", "ufw"].includes(executable)) {
    match = classifyFirewall(executable, words);
  } else if (executable.startsWith("mkfs")) {
    match = { reason: "filesystem creation", sessionCommand: executable };
  } else if (executable === "dd" && words.some((word) => word.startsWith("of="))) {
    match = { reason: "raw device or file overwrite", sessionCommand: "dd of=" };
  } else if (["poweroff", "reboot", "shutdown"].includes(executable)) {
    match = { reason: "system power operation", sessionCommand: executable };
  } else if (executable === "git") match = classifyGit(words);
  else if (executable === "systemctl") {
    const action = firstAction(words.slice(1), SYSTEMCTL_ACTIONS);
    if (action) match = { reason: "system service or power change", sessionCommand: `systemctl ${action}` };
  } else if (executable === "service") {
    const action = firstAction(words.slice(1), SERVICE_ACTIONS);
    if (action) match = { reason: "system service change", sessionCommand: `service ${action}` };
  } else if (["kill", "killall", "pkill"].includes(executable)) {
    const isProbe = executable === "kill" && words.slice(1).some((word) => word === "-0" || word === "-s0");
    if (!isProbe) match = { reason: "process termination", sessionCommand: executable };
  } else if ([...Object.keys(PACKAGE_ACTIONS), "pacman"].includes(executable)) {
    match = classifyPackage(executable, words);
  } else if (ACCOUNT_COMMANDS.has(executable)) {
    match = { reason: "user or group account change", sessionCommand: executable };
  } else if (executable === "mount") {
    if (words.length > 1 && !words.some((word) => word === "--help" || word === "-h")) {
      match = { reason: "filesystem mount change", sessionCommand: "mount" };
    }
  } else if (executable === "umount") {
    match = { reason: "filesystem mount change", sessionCommand: "umount" };
  } else if (executable === "fdisk") {
    if (!words.some((word) => word === "-l" || word === "--list")) {
      match = { reason: "disk partition change", sessionCommand: "fdisk" };
    }
  } else if (executable === "parted") {
    const lower = words.map((word) => word.toLowerCase());
    const action = lower.find((word) => PARTED_MUTATIONS.has(word));
    const printOnly = lower.includes("print") && !action;
    if (!printOnly) match = { reason: "disk partition change", sessionCommand: action ? `parted ${action}` : "parted" };
  } else if (executable === "wipefs") {
    if (!words.some((word) => word === "-n" || word === "--no-act")) {
      match = { reason: "filesystem signature removal", sessionCommand: "wipefs" };
    }
  }

  if (match) return [match];
  if (privileged) {
    const signature = words.slice(0, Math.min(words.length, 3)).join(" ");
    return [{ reason: "privileged command", sessionCommand: `sudo ${signature}` }];
  }
  return [];
}

function guardMatches(command: string): GuardMatch[] {
  const matches = splitShellCommands(command).flatMap(classifySegment);
  const seen = new Set<string>();
  return matches.filter((match) => {
    const key = `${match.reason}\0${match.sessionCommand}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

class ApprovalPrompt {
  private selected: 0 | 1 | 2 = 1;

  constructor(
    private readonly reason: string,
    private readonly sessionCommand: string,
    private readonly command: string,
    private readonly theme: Theme,
    private readonly keybindings: KeybindingsManager,
    private readonly done: (choice: ApprovalChoice) => void,
    private readonly requestRender: () => void,
  ) {}

  render(width: number): string[] {
    const innerWidth = Math.max(1, width - 4);
    const line = (text: string): string => truncateToWidth(text, width, "");
    const option = (index: 0 | 1 | 2, text: string): string => {
      const prefix = this.selected === index ? "  → " : "    ";
      const content = line(`${prefix}${text}`);
      const color = index === 0 ? "warning" : index === 1 ? "success" : "error";
      return this.theme.fg(color, this.selected === index ? this.theme.bold(content) : content);
    };

    const commandLines = wrapTextWithAnsi(safeForTerminal(this.command), innerWidth).map((commandLine) =>
      line(`  ${this.theme.fg("text", commandLine)}`),
    );

    return [
      this.theme.fg("warning", "━".repeat(Math.max(1, width))),
      "",
      line(
        `  ${this.theme.fg("warning", this.theme.bold("⚠  APPROVAL REQUIRED"))}${this.theme.fg("muted", `  ·  ${this.reason.toUpperCase()}`)}`,
      ),
      line("  The agent is paused until you approve or deny this guarded command."),
      "",
      line(`  ${this.theme.fg("muted", this.theme.bold("COMMAND"))}`),
      ...commandLines,
      "",
      option(0, "1.  ALLOW ONCE      Run this command"),
      option(1, "2.  DENY            Block this command"),
      option(2, `3.  ALLOW SESSION   Run; allow future “${this.sessionCommand}” commands this session`),
      "",
      line(this.theme.fg("dim", "  Press 1, 2, or 3  ·  ↑↓ move  ·  Enter select  ·  Esc deny")),
      this.theme.fg("warning", "━".repeat(Math.max(1, width))),
    ];
  }

  handleInput(data: string): void {
    if (data === "1") {
      this.done("once");
      return;
    }
    if (data === "2" || this.keybindings.matches(data, "tui.select.cancel")) {
      this.done("deny");
      return;
    }
    if (data === "3") {
      this.done("session");
      return;
    }
    if (this.keybindings.matches(data, "tui.select.up")) {
      this.selected = this.selected === 0 ? 2 : ((this.selected - 1) as 0 | 1);
      this.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.select.down")) {
      this.selected = this.selected === 2 ? 0 : ((this.selected + 1) as 1 | 2);
      this.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.select.confirm")) {
      this.done((["once", "deny", "session"] as const)[this.selected]);
    }
  }

  invalidate(): void {}
}

export default function (pi: ExtensionAPI) {
  const sessionAllowedCommands = new Set<string>();

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const command = (event.input as BashInput).command;
    if (typeof command !== "string") return;

    const guarded = guardMatches(command).filter(
      ({ sessionCommand }) => !sessionAllowedCommands.has(sessionCommand),
    );
    if (guarded.length === 0) return;

    if (!ctx.hasUI) {
      const operations = guarded.map(({ sessionCommand }) => sessionCommand).join(", ");
      return {
        block: true,
        reason: `Blocked guarded operation${guarded.length === 1 ? "" : "s"} (${operations}): this session has no UI for confirmation.`,
      };
    }

    const commandPreview = preview(command);
    for (const { reason, sessionCommand } of guarded) {
      const choice: ApprovalChoice =
        ctx.mode === "tui"
          ? await ctx.ui.custom<ApprovalChoice>((tui, theme, keybindings, done) =>
              new ApprovalPrompt(
                reason,
                sessionCommand,
                commandPreview,
                theme,
                keybindings,
                done,
                () => tui.requestRender(),
              ),
            )
          : (await ctx.ui.confirm(
                `Confirm ${reason}`,
                `The agent wants to run:\n\n${commandPreview}\n\nAllow it?`,
              ))
            ? "once"
            : "deny";
      if (choice === "session") sessionAllowedCommands.add(sessionCommand);
      if (choice === "deny") return { block: true, reason: `${reason} declined by user.` };
    }
  });
}
