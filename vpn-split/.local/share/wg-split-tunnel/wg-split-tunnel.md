# WireGuard Split Tunneling + Kill Switch (Linux/Fedora Asahi)

Per-app VPN split tunneling for Proton WireGuard, with a kill switch and
AGH DNS via LAN. Default is VPN-on; specific apps launched with `novpn`
bypass to direct. Once the kill switch is installed by `wg-split-up`,
non-`novpn` traffic is blocked if the tunnel goes down.

## TL;DR

```sh
# Normal use
curl -4 ifconfig.me              # shows VPN IP
novpn curl -4 ifconfig.me        # shows real IP
novpn brave-browser              # launch any app outside the VPN

# Toggle via DMS bar widgets (wg-p / wg-h / ks), or CLI
nmcli connection down wg-proton  # if kill switch is installed, non-novpn traffic is blocked
nmcli connection up wg-proton    # back to normal

# Intentional direct browsing (disables kill switch)
sudo wg-kill-switch-off
# auto-reinstalled on next wg-split-up
```

## Deployment models

Two remote designs are possible:

1. **Separate modes (recommended)**
   - **At home**: `wg-proton` is the active full tunnel.
   - **When remote**: `wg-home` is the active full tunnel back to OPNsense.
     OPNsense then forwards internet-bound traffic via its own Proton tunnel.
   - Only one full-tunnel WG connection is normally active at a time.
   - `novpn` remains the explicit per-app escape hatch in either mode.

2. **Dual-tunnel remote mode (alternative)**
   - `wg-proton` stays up for normal internet.
   - `wg-home` is a second, LAN-only tunnel for `10.10.0.0/16`.
   - Both tunnels may be active at once when remote.

The recommended design for this host is **separate modes**. It is simpler to
reason about, simpler to document, and easier to recover when something breaks.
The dual-tunnel design is valid, but it adds host-side routing and DNS
complexity for a performance benefit that may not be worth the extra moving
parts.

## Architecture

Four independent pieces:

1. **cgroup membership** (systemd user slice `novpn.slice`)
   - `novpn` wrapper uses `systemd-run --user --scope --slice=novpn.slice`
     to place a command in the slice before exec. Sockets created by the
     command (and children) are tagged with that cgroup.
   - `novpn-anchor.service` runs `sleep infinity` in the slice permanently.
     Required because nftables resolves the cgroup path to an inode at
     rule-load time — the directory has to exist.
   - The scripts do **not** hardcode UID `1000` anymore. They discover the
     live `novpn.slice` path by globbing under `/sys/fs/cgroup/user.slice/...`
     so the setup keeps working if the user ID changes.

2. **nftables packet marking** (`table inet split-tunnel`)
   - `output` chain, type `route`: if a socket's cgroup is `novpn.slice`,
     sets `meta mark 0x6e76` and saves to conntrack. Subsequent packets
     in the same connection restore the mark from conntrack.
   - `prerouting` chain: restore mark from conntrack for inbound replies.
   - `postrouting` nat chain: masquerade marked packets leaving the
     physical interface (otherwise the source IP stays as the WG tunnel
     IP from the initial routing pass).

3. **Policy routing** (table `novpn`, id 26642)
   - `ip rule add fwmark 0x6e76 table novpn priority 100` — higher
     priority than any WG ip rules.
   - Table `novpn` has the real default gateway + local subnet routes.
   - The nftables `type route` hook triggers `ip_route_me_harder()` when
     the mark changes, kicking the kernel to re-route via this table.

4. **Kill switch** (`table inet kill-switch`)
   - `output` chain at priority 0: drops packets heading to the physical
     interface that aren't one of:
     - non-physical interface (wg*, lo)
     - LAN destination (10.10.0.0/24)
     - IPv6 link-local
   - WG-encapsulated (peer endpoint auto-detected via `wg show`)
   - novpn mark (0x6e76)
   - Separate table from split-tunnel — survives `wg-split-down`.
   - Peer endpoint whitelist is rebuilt each `wg-split-up` run, so
     switching Proton servers is fine.
   - A user-readable state file at `~/.local/state/wg-killswitch-active`
     mirrors whether the kill switch is installed so bar widgets can show
     status without needing `sudo`.
   - The currently selected full-tunnel mode is tracked at
     `/run/wg-split-tunnel/active-full-tunnel`, which lets dispatcher
     refreshes resolve rare dual-up states deterministically without
     falling back to "last up wins".

## Network setup

- **wg-proton**: NetworkManager-managed WireGuard. Endpoint = Proton
  server. `AllowedIPs = 0.0.0.0/0`. DNS removed at the NM level
  (`ipv4.dns ""`, `ipv4.ignore-auto-dns yes`, `ipv4.dns-search ""`).
  IPv6 disabled (`ipv6.method disabled`).
- **wg-home**: NetworkManager-managed WireGuard. Endpoint = home WAN IP.
  In the recommended design, `AllowedIPs = 0.0.0.0/0`. This is a normal
  full-tunnel VPN back home, not a LAN-only route. OPNsense then forwards
  internet-bound traffic onward via its own Proton WireGuard tunnel. DNS
  at `10.10.70.1` is valid in this mode because it is the far end of the
  WireGuard tunnel itself.
- **Main (Wi-Fi)**: IPv6 disabled (`ipv6.method disabled`) to prevent
  v6 leaks (split tunnel is v4-only).
- **DNS**: goes to AGH on OPNsense at 10.10.0.1 via wlp1s0f0 (DHCP-pushed).
  AGH forwards upstream via OPNsense's own Proton tunnel, so queries never
  leak to the ISP. For `wg-proton`, `10.10.0.1` must *not* be set as DNS
  on the WG connection itself, because it is a LAN IP and unreachable
  inside the direct-to-Proton tunnel. For `wg-home` in the recommended
  full-tunnel-to-home design, the tunnel DNS is `10.10.70.1` (the OPNsense
  WireGuard-side address), which is valid because it is reachable through
  the tunnel itself. In the alternative LAN-only `wg-home` design, DNS
  handling needs separate thought. Apps with built-in DoH (Firefox TRR,
  Chrome Secure DNS) bypass systemd-resolved entirely — disable app-level
  DoH if you care.
- **Linger**: `loginctl enable-linger hugo` so the user session and
  anchor service exist at boot, before login — otherwise the nftables
  cgroup rule fails when NM autoconnects wg-proton early.

## File inventory

| Path | Purpose |
|------|---------|
| `~/.local/bin/novpn` | Launch a command in novpn.slice |
| `~/.local/lib/wg-split-lib.sh` | Shared helper library sourced by wg-split-up/down |
| `~/.local/bin/novpn-brave-origin` | Launch Brave Origin nightly in a separate novpn-only profile |
| `~/.local/share/applications/novpn-brave-origin.desktop` | Desktop entry for Walker/app launchers |
| `~/.local/bin/wg-split-up` | Install full-tunnel mode state: novpn bypass + kill switch (sudo) |
| `~/.local/bin/wg-split-down` | Remove full-tunnel state; keep novpn bypass + kill switch (sudo) |
| `~/.local/bin/wg-kill-switch-off` | Explicitly remove kill switch (sudo) |
| `~/.local/bin/wg-status-proton` | Bar status script (outputs colored `wg-p`) |
| `~/.local/bin/wg-status-home` | Bar status script (outputs colored `wg-h`) |
| `~/.local/bin/wg-status-killswitch` | Bar status script (outputs colored `ks`) |
| `~/.local/bin/wg-toggle-proton` | Click-to-toggle wg-proton |
| `~/.local/bin/wg-toggle-home` | Click-to-toggle wg-home |
| `~/.local/bin/wg-toggle-killswitch` | Click-to-toggle kill switch |
| `~/.config/systemd/user/novpn.slice` | Systemd slice definition |
| `~/.config/systemd/user/novpn-anchor.service` | Keeps the cgroup alive |
| `/etc/NetworkManager/dispatcher.d/50-wg-split-tunnel` | Auto-run wg-split-up/down on WG state changes |
| `/etc/iproute2/rt_tables` | Names table 26642 as `novpn` |

## Multi-WG

The scripts detect any active `wg*` interface — not just `wg0`. Designed
to support:

- **wg-proton** — full tunnel direct to Proton. Intended primary mode at
  home. `AllowedIPs = 0.0.0.0/0`.
- **wg-home** — full tunnel to OPNsense via home WAN IP. Intended primary
  mode when remote. `AllowedIPs = 0.0.0.0/0`. OPNsense then routes that
  traffic onward via its own Proton tunnel.

`wg-split-down` keeps the active mode state up if any full tunnel is still
active, so dropping one tunnel doesn't break the other. When the last full
tunnel goes down, it removes the full-tunnel state but preserves the `novpn`
bypass path and leaves the kill switch active so the host stays fail-closed
until a tunnel is brought back up or `wg-kill-switch-off` is run explicitly.

These are intended as separate operating modes, not normal simultaneous
connections. Both are full tunnels that claim the default route. `novpn`
remains the explicit per-app escape hatch in either mode.

If both full tunnels are brought up, `wg-split-up` only resolves the
ambiguity when it is called with an explicit preferred interface (for
example from the widget toggle path). In that case it keeps the requested
tunnel and brings the other down. Without an explicit preference, dual-up
state is treated as an error unless a previously selected mode is available
from `/run/wg-split-tunnel/active-full-tunnel`, which allows dispatcher
refreshes and teardown paths to stay deterministic without falling back to
"last up wins".

Alternative design: when remote, `wg-proton` can stay up as the internet
tunnel while `wg-home` is reduced to a LAN-only tunnel (for example
`AllowedIPs = 10.10.0.0/16`). That model is not the recommended design for
this host, but it is a valid option if lower latency matters more than
simplicity.

## DMS bar widgets

`intervalCommand` plugin × 3 instances:

- **wg-p**
  - command: `~/.local/bin/wg-status-proton`
  - click: `~/.local/bin/wg-toggle-proton`
  - interval: `5s`
  - status meaning: green `wg-p` when `wg-proton` is up, gray when down
  - click behavior: if `wg-proton` is up, bring it down; otherwise bring
    `wg-home` down first (if needed) and then bring `wg-proton` up
- **wg-h**
  - command: `~/.local/bin/wg-status-home`
  - click: `~/.local/bin/wg-toggle-home`
  - interval: `5s`
  - status meaning: green `wg-h` when `wg-home` is up, gray when down
  - click behavior: if `wg-home` is up, bring it down; otherwise bring
    `wg-proton` down first (if needed) and then bring `wg-home` up
- **ks**
  - command: `~/.local/bin/wg-status-killswitch`
  - click: `~/.local/bin/wg-toggle-killswitch`
  - interval: `5s`
  - status meaning: green `ks` when the kill switch is installed, gray when
    it is not
  - click behavior: if the kill switch is active, disable it with
    `wg-kill-switch-off`; if a full tunnel is up, re-enable it with
    `wg-split-up`; if no tunnel is up, re-enable it with `wg-split-down`
    so the host returns to fail-closed + `novpn`-only mode

The toggle helpers enforce the recommended separate-modes design: bringing
up one full tunnel first brings the other down. The kill-switch widget reads
`~/.local/state/wg-killswitch-active`, so it stays reliable even when the bar
cannot run `sudo` for status checks.

Status scripts emit `<font color="#a6e3a1">wg-p</font>` (green, Catppuccin)
when the tunnel is up, `<font color="#6c7086">wg-p</font>` (gray) when
down. Qt's `Text` component auto-detects HTML and renders the color —
no plugin patching needed.

Equivalent in Noctalia: the built-in `CustomButton` widget has
`textCommand` + `leftClickExec` + `textIntervalMs` — no plugin install.
Map the same pairs directly:

- `wg-p`: `textCommand="~/.local/bin/wg-status-proton"`,
  `leftClickExec="~/.local/bin/wg-toggle-proton"`,
  `textIntervalMs=5000`
- `wg-h`: `textCommand="~/.local/bin/wg-status-home"`,
  `leftClickExec="~/.local/bin/wg-toggle-home"`,
  `textIntervalMs=5000`
- `ks`: `textCommand="~/.local/bin/wg-status-killswitch"`,
  `leftClickExec="~/.local/bin/wg-toggle-killswitch"`,
  `textIntervalMs=5000`

These scripts are shell-agnostic and do not depend on DMS-specific features.

## Reserved namespace

Don't collide with these for unrelated routing/firewall work:

| Value | Purpose |
|-------|---------|
| fwmark `0x6e76` | novpn bypass |
| ip rule priority `100` | novpn fwmark → bypass table |
| routing table `26642` (aka `novpn`) | bypass routes |

Note: `0xca6c` / `0xca6d` are common wg-quick-style values you may see in
other setups, but this host's NetworkManager-managed WireGuard currently
uses `wireguard.fwmark: 0x0`, so they are not active parts of this design.

## Verification

```sh
curl -4 ifconfig.me                   # VPN IP expected
novpn curl -4 ifconfig.me             # real IP expected
novpn-brave-origin                    # separate Brave instance outside the VPN
resolvectl status                     # wg-proton should list no DNS; wg-home should list DNS 10.10.70.1
ip rule show                          # priority 100: fwmark 0x6e76 → 26642
ip route show table novpn             # default via real gateway
sudo nft list table inet split-tunnel # bypass rules + counters
sudo nft list table inet kill-switch  # kill-switch rules + counters

# Kill switch test (blocks internet briefly)
nmcli connection down wg-proton
curl -4 --max-time 3 ifconfig.me      # should fail (exit 28)
nmcli connection up wg-proton
```

## Key lessons (gotchas worth remembering)

- **`socket cgroupv2 level N "path"` needs the full cgroup path from root**,
  not just the leaf name. Level 4 in the user's systemd hierarchy is
  `novpn.slice` under `user.slice/user-UID.slice/user@UID.service/`.
- **The cgroup dir must exist at rule-load time** — hence the anchor
  service. Without it, `nft -f` fails with "No such file or directory".
- **The cgroup path is discovered dynamically** by globbing the live
  `novpn.slice` under `/sys/fs/cgroup/user.slice/.../user@...service/`.
  This avoids hardcoding UID `1000` and keeps the setup portable across
  user IDs.
- **`masquerade` is terminal in nft** — `counter` must come before it,
  `comment` cannot follow.
- **Masquerade is required**, not optional — initial routing to wg-proton
  sets source to the WG tunnel IP; without SNAT the bypass packets go out
  with an unroutable source and replies never come back.
- **`wg-split-down` intentionally omits the SNAT chain** when no full
  tunnel is active. In that state, new `novpn` traffic is already routed
  directly via the physical interface, so the kernel should pick the
  correct source address without an extra masquerade pass.
- **systemd-resolved uses `SO_BINDTODEVICE`** to pin DNS queries to the
  interface that advertised the DNS server. If `DNS = 10.10.0.1` is set
  on wg-proton, resolved sends queries via wg-proton (into the tunnel)
  and the LAN DNS is unreachable — even though `ip route get` says
  otherwise. Fix is to leave DNS off the direct-to-Proton WG connection
  entirely. This caveat does **not** apply to wg-home, where the tunnel DNS
  is `10.10.70.1` on the far end of the home WireGuard link.
- **NM-managed WG does not set fwmark on the interface** (shows
  `wireguard.fwmark:0x0`). Encapsulated UDP goes out *unmarked* — so a
  mark-based kill-switch rule never catches it. Solution: auto-detect
  peer endpoints with `wg show <iface> endpoints` and whitelist
  `ip daddr <peer-ip> udp dport <peer-port>`.
- **Upstream gotcha**: when OPNsense routes this machine's LAN through
  Proton at the router level, host-level split tunneling appears broken
  because the router re-tunnels everything. Sanity check:
  `nmcli connection down wg-proton && curl -4 ifconfig.me` — if still a
  Proton IP, the issue is on OPNsense.
- **Dispatcher must match the interface pattern** — `wg*` glob, not
  hardcoded `wg0`, so renaming (e.g., `wg-proton`, `wg-home`) doesn't
  silently break auto-setup.

## Limitations

- **Not boot-persistent by itself**: kill-switch table is installed by
  `wg-split-up` when a WG interface comes up, and preserved by
  `wg-split-down` when the last full tunnel goes down. On first boot after
  reinstall, or if you manually flush nftables before any WG tunnel has
  come up, there's still a window where traffic could leak. In practice NM
  autoconnects wg-proton at boot, which triggers the dispatcher, which
  runs wg-split-up.
- **Treat wg-proton and wg-home as alternative full-tunnel modes**:
  both use `AllowedIPs = 0.0.0.0/0`, so bringing both up at once needs
  explicit precedence and is not a normal operating mode.
- **Existing sockets don't move**: `novpn` only affects sockets opened
  *after* the process is in the slice. Restart an app under `novpn` if
  you want to re-route it; moving an already-running PID won't retag
  open connections.
- **No IPv6 split tunneling**: IPv6 is disabled at the Wi-Fi layer.
  Extending the split tunnel to IPv6 would require mirroring the nft
  rules, ip-6 rule, and an IPv6 bypass table. Not worth the complexity
  for this use case.
- **Wi-Fi roam / gateway change**: long-lived TCP sessions in novpn
  apps break because the gateway IP changes. The dispatcher re-applies
  the policy, but the kernel won't migrate live sockets.
- **rp_filter assumption**: system uses loose mode (`rp_filter=2`) on
  wlp1s0f0. Strict mode (`=1`) would drop return traffic for bypass
  packets.

## Troubleshooting

**`novpn` shows VPN IP, not real IP**
- Verify your upstream isn't also VPN-routing this machine:
  `nmcli connection down wg-proton && curl -4 ifconfig.me`
- Check cgroup of a command run under novpn:
  `novpn sh -c 'cat /proc/self/cgroup'` — should contain `novpn.slice`.
- Check nft counters: `sudo nft list table inet split-tunnel` — the
  "cgroup match" counter should increment when you run a novpn test.

**Kill switch blocking DNS / everything**
- `sudo nft list table inet kill-switch` — look at counters on the
  `drop` line. If it's catching WG traffic, the peer-endpoint accept
  rule is missing. Re-run `sudo wg-split-up` with a WG interface up to
  rebuild the endpoint whitelist.
- Quick escape: `sudo wg-kill-switch-off`.

**DNS broken after a config change**
- `resolvectl status` — make sure `wg-proton` link has no `DNS Servers`
  and no `DNS Domain: ~.`. If it does, NM auto-added it; clear with:
  ```sh
  nmcli connection modify wg-proton ipv4.dns "" ipv4.ignore-auto-dns yes ipv4.dns-search ""
  nmcli connection down wg-proton && nmcli connection up wg-proton
  ```
- For `wg-home`, expect `DNS Servers: 10.10.70.1` and `DNS Domain: ~.`.

**Split tunnel not activating on boot**
- Verify linger is on: `loginctl show-user hugo | grep Linger` →
  `Linger=yes`.
- Check anchor service: `systemctl --user status novpn-anchor.service`.
- Check dispatcher fired: `journalctl -u NetworkManager-dispatcher.service --since boot`.
