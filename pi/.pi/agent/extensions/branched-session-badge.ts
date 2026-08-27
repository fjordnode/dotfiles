import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const WIDGET_KEY = "branched-session-badge";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    const parentSession = ctx.sessionManager.getHeader().parentSession;
    if (!parentSession) {
      ctx.ui.setWidget(WIDGET_KEY, undefined);
      return;
    }

    ctx.ui.setWidget(
      WIDGET_KEY,
      [ctx.ui.theme.fg("accent", "↳ BRANCHED SESSION")],
      { placement: "aboveEditor" },
    );
  });

  pi.on("session_shutdown", (_event, ctx) => {
    ctx.ui.setWidget(WIDGET_KEY, undefined);
  });
}
