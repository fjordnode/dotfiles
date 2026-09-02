import type {
  ExtensionAPI,
  KeybindingsManager,
  Theme,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

type PromptChoice = "compact" | "defer" | "disable";
type PendingCompaction = {
  sessionId: string;
  phase: "waitingForSettle" | "compacting";
  usagePercent: number;
};

const INITIAL_THRESHOLD_PERCENT = 90;
const DEFER_STEP_PERCENT = 10;
const CONTINUATION_PROMPT = "Compaction completed. Continue.";

function isCodexModel(model: unknown): model is { provider: string; api: string } {
  return (
    typeof model === "object" &&
    model !== null &&
    "provider" in model &&
    "api" in model &&
    model.provider === "openai-codex" &&
    model.api === "openai-codex-responses"
  );
}

function nextThreshold(currentThreshold: number, usagePercent: number): number {
  const nextStepBoundary = (Math.floor(usagePercent / DEFER_STEP_PERCENT) + 1) * DEFER_STEP_PERCENT;
  return Math.max(currentThreshold + DEFER_STEP_PERCENT, nextStepBoundary);
}

class CompactionPrompt {
  private selected: 0 | 1 | 2 = 1;

  constructor(
    private readonly usagePercent: number,
    private readonly tokens: number,
    private readonly contextWindow: number,
    private readonly deferUntilPercent: number,
    private readonly theme: Theme,
    private readonly keybindings: KeybindingsManager,
    private readonly done: (choice: PromptChoice) => void,
    private readonly requestRender: () => void,
  ) {}

  render(width: number): string[] {
    const line = (text: string): string => truncateToWidth(text, width, "");
    const option = (index: 0 | 1 | 2, text: string): string => {
      const prefix = this.selected === index ? "  → " : "    ";
      const content = line(`${prefix}${text}`);
      const color = index === 0 ? "accent" : index === 1 ? "success" : "warning";
      return this.theme.fg(color, this.selected === index ? this.theme.bold(content) : content);
    };
    const tokenSummary = `${Math.round(this.tokens / 1000)}k / ${Math.round(this.contextWindow / 1000)}k tokens`;
    const description = wrapTextWithAnsi(
      "The agent is paused at a turn boundary. Choose whether to compact before it continues.",
      Math.max(1, width - 2),
    ).map((text) => line(`  ${text}`));

    return [
      this.theme.fg("warning", "━".repeat(Math.max(1, width))),
      "",
      line(
        `  ${this.theme.fg("warning", this.theme.bold("CONTEXT CHECKPOINT"))}${this.theme.fg("muted", `  ·  ${this.usagePercent.toFixed(1)}%  ·  ${tokenSummary}`)}`,
      ),
      ...description,
      "",
      option(0, "1.  COMPACT NOW     Stop, compact, then continue the task"),
      option(1, `2.  KEEP GOING      Continue; ask again at ${this.deferUntilPercent}%`),
      option(2, "3.  THIS SESSION    Continue and stop asking this session"),
      "",
      line(this.theme.fg("dim", "  Press 1, 2, or 3  ·  ↑↓ move  ·  Enter select  ·  Esc keep going")),
      this.theme.fg("warning", "━".repeat(Math.max(1, width))),
    ];
  }

  handleInput(data: string): void {
    if (data === "1") {
      this.done("compact");
      return;
    }
    if (data === "2" || this.keybindings.matches(data, "tui.select.cancel")) {
      this.done("defer");
      return;
    }
    if (data === "3") {
      this.done("disable");
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
      this.done((["compact", "defer", "disable"] as const)[this.selected]);
    }
  }

  invalidate(): void {}
}

export default function interactiveCompactionExtension(pi: ExtensionAPI): void {
  let nextPromptPercent = INITIAL_THRESHOLD_PERCENT;
  let disabledForSession = false;
  let promptOpen = false;
  let pendingCompaction: PendingCompaction | undefined;

  const reset = () => {
    nextPromptPercent = INITIAL_THRESHOLD_PERCENT;
    disabledForSession = false;
    promptOpen = false;
    pendingCompaction = undefined;
  };

  pi.on("session_start", reset);
  pi.on("session_shutdown", reset);
  pi.on("model_select", reset);

  pi.on("turn_end", async (_event, ctx) => {
    if (
      disabledForSession ||
      promptOpen ||
      pendingCompaction ||
      !isCodexModel(ctx.model)
    ) {
      return;
    }

    const usage = ctx.getContextUsage();
    if (
      usage?.percent === null ||
      usage?.percent === undefined ||
      usage.tokens === null ||
      usage.percent < nextPromptPercent
    ) {
      return;
    }

    if (!ctx.hasUI) {
      disabledForSession = true;
      return;
    }

    const deferUntilPercent = nextThreshold(nextPromptPercent, usage.percent);
    promptOpen = true;
    let choice: PromptChoice;
    try {
      choice =
        ctx.mode === "tui"
          ? await ctx.ui.custom<PromptChoice>((tui, theme, keybindings, done) =>
              new CompactionPrompt(
                usage.percent!,
                usage.tokens!,
                usage.contextWindow,
                deferUntilPercent,
                theme,
                keybindings,
                done,
                () => tui.requestRender(),
              ),
            )
          : await (async (): Promise<PromptChoice> => {
              const selected = await ctx.ui.select(
                `Context usage: ${usage.percent.toFixed(1)}%`,
                [
                  "Compact now",
                  `Keep going; ask again at ${deferUntilPercent}%`,
                  "Keep going; don't ask again this session",
                ],
              );
              if (selected === "Compact now") return "compact";
              if (selected === "Keep going; don't ask again this session") return "disable";
              return "defer";
            })();
    } finally {
      promptOpen = false;
    }

    if (choice === "disable") {
      disabledForSession = true;
      return;
    }
    if (choice === "defer") {
      nextPromptPercent = deferUntilPercent;
      return;
    }

    pendingCompaction = {
      sessionId: ctx.sessionManager.getSessionId(),
      phase: "waitingForSettle",
      usagePercent: usage.percent,
    };
    ctx.abort();
  });

  pi.on("agent_settled", (_event, ctx) => {
    const pending = pendingCompaction;
    if (
      !pending ||
      pending.phase !== "waitingForSettle" ||
      pending.sessionId !== ctx.sessionManager.getSessionId() ||
      !isCodexModel(ctx.model)
    ) {
      return;
    }

    const compacting: PendingCompaction = { ...pending, phase: "compacting" };
    pendingCompaction = compacting;
    ctx.compact({
      onComplete: () => {
        if (pendingCompaction !== compacting) return;
        pendingCompaction = undefined;
        nextPromptPercent = INITIAL_THRESHOLD_PERCENT;
        if (ctx.hasPendingMessages()) return;
        if (ctx.isIdle()) {
          pi.sendUserMessage(CONTINUATION_PROMPT);
        } else {
          pi.sendUserMessage(CONTINUATION_PROMPT, { deliverAs: "followUp" });
        }
      },
      onError: (error) => {
        if (pendingCompaction !== compacting) return;
        pendingCompaction = undefined;
        nextPromptPercent = nextThreshold(nextPromptPercent, compacting.usagePercent);
        if (ctx.hasUI) {
          ctx.ui.notify(`Compaction failed: ${error.message}`, "error");
        }
      },
    });
  });
}
