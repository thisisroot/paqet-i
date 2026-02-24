# AGENTS.md — Coding Agent Instructions for paqet-i

This is a fork of the [paqet](https://github.com/hanselime/paqet) project. paqet is a
bidirectional packet-level proxy using KCP over raw TCP sockets with encryption.

The primary additions in this fork are four shell scripts in `scripts/` for installing
and uninstalling paqet on Ubuntu (server and client roles).

---

## Repository Layout

```
cmd/            # Cobra CLI entry points (main.go, run, dump, ping, secret, iface, version)
internal/       # Core logic: conf, client, server, socket, socks, forward, protocol, tnet, flog
example/        # server.yaml.example and client.yaml.example
scripts/        # install-paqet-server.sh, install-paqet-client.sh,
                # uninstall-paqet-server.sh, uninstall-paqet-client.sh
```

---

## Build Commands

Requires: Go 1.25+, CGO enabled, `libpcap-dev` installed on Linux.

```bash
# Development build (local, no version injection)
CGO_ENABLED=1 go build -o paqet ./cmd/main.go

# Production build (matches CI — strips debug info, injects version)
CGO_ENABLED=1 go build -v -a -trimpath \
  -gcflags "all=-l=4" \
  -ldflags "-s -w -buildid= \
    -X 'paqet/cmd/version.Version=dev' \
    -X 'paqet/cmd/version.GitCommit=$(git rev-parse HEAD)' \
    -X 'paqet/cmd/version.GitTag=dev' \
    -X 'paqet/cmd/version.BuildTime=$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)'" \
  -o paqet ./cmd/main.go

# Install libpcap dependency (Ubuntu/Debian)
sudo apt install libpcap-dev
```

---

## Test Commands

There are no test files in the repository at this time. When adding tests:

```bash
# Run all tests
go test ./...

# Run tests in a single package
go test ./internal/conf/...

# Run a single named test
go test ./internal/conf/ -run TestFunctionName -v

# Run tests with race detector
go test -race ./...
```

---

## Lint / Format

```bash
# Format all Go files
gofmt -w ./...

# Or use goimports (preferred — also fixes import ordering)
goimports -w ./...

# Vet
go vet ./...

# golangci-lint (if installed)
golangci-lint run ./...
```

---

## Go Code Style Guidelines

### Imports
- Group imports in three blocks separated by blank lines:
  1. Standard library
  2. Internal packages (`paqet/...`)
  3. Third-party packages
- Use the full module path for internal imports: `paqet/internal/flog`, not relative paths.

### Formatting
- Use `gofmt` / `goimports` — no manual indentation changes.
- No trailing whitespace; files end with a newline.
- Keep lines reasonably short (~100 chars), but do not break logical expressions arbitrarily.

### Naming Conventions
- Packages: short, lowercase, no underscores (e.g. `flog`, `tnet`, `conf`).
- Exported types / functions: `PascalCase`.
- Unexported fields: `camelCase`.
- Acronyms stay uppercase: `KCP`, `TCP`, `UDP`, `MAC`, `IP`.
- Config struct fields use YAML tags matching the config file keys (snake_case):
  `RouterMAC string \`yaml:"router_mac"\``.

### Types
- Prefer named types for config structs; embed validation and `setDefaults()` as methods.
- Use `error` return values; do not panic except in truly unrecoverable init paths.
- Use `context.Context` for cancellation on long-running goroutines.

### Error Handling
- Wrap errors with `fmt.Errorf("...context: %w", err)` to preserve the chain.
- Collect multiple validation errors into a slice and return them together (see
  `internal/conf/conf.go:writeErr`).
- Never swallow errors silently. Log with `flog.Errorf` before continuing if a goroutine
  cannot return an error.

### Concurrency
- Use `sync.WaitGroup.Go` (Go 1.22+ method) for managed goroutine spawning.
- Cancel via `context.Context`; propagate the context down from `Start()`.
- Close listeners from a separate goroutine watching `ctx.Done()` to unblock `Accept()`.

### Logging
- Use `paqet/internal/flog` for all log output — not `log`, not `fmt.Println`.
- Available: `flog.Debugf`, `flog.Infof`, `flog.Warnf`, `flog.Errorf`, `flog.Fatalf`.

---

## Shell Script Style Guidelines (scripts/)

All four scripts share a common structure:
- `set -e` at the top.
- Color variables (`RED`, `GREEN`, `YELLOW`, `BLUE`, `NC`) for output.
- Helper functions: `print_info`, `print_success`, `print_warning`, `print_error`, `print_header`.
- Root-detection block setting `IS_ROOT`, `SUDO_CMD`, `CURRENT_USER`.

Follow this style when modifying or merging scripts:
- Quote all variable expansions: `"${VAR}"`.
- Use `command -v <tool> &> /dev/null` to check for optional dependencies.
- Fallback gracefully when an optional step fails rather than hard-exiting.
- Always run `$SUDO_CMD netfilter-persistent save` after any iptables change.
- Do not hard-code architecture — the current scripts target `linux-amd64` only; document
  this limitation explicitly if merging scripts.

---

## Primary Agent Tasks for This Fork

This fork has two specific tasks that agents should focus on:

### Task 1 — Merge the four scripts into one unified script

**Goal:** Create `scripts/paqet-manage.sh` that handles all four workflows (install server,
install client, uninstall server, uninstall client) via a single entry point.

**Approach:**
1. Accept a `MODE` argument or interactive menu: `install-server`, `install-client`,
   `uninstall-server`, `uninstall-client`.
2. Refactor shared boilerplate (colors, print helpers, root detection, apt update,
   binary download/install, libpcap install, systemd service management) into reusable
   shell functions at the top of the file.
3. Call those functions from mode-specific sections.
4. Keep the existing four scripts intact as a fallback until the merged script is verified.

**Verification:** Run `bash -n scripts/paqet-manage.sh` (syntax check) and manually trace
each mode's call path to confirm no variable bleeds between modes.

### Task 2 — Verify commands in the scripts are correct

Check each command in all four scripts for accuracy. Known areas to audit:

| Check | What to verify |
|---|---|
| Binary filename | After extraction, the binary is named `paqet_linux_amd64`, not `paqet`. The `mv` renames it correctly — confirm this matches the actual release artifact. |
| `paqet secret` output | `SECRET_KEY=$(paqet secret \| tail -n 1)` — verify `paqet secret` prints the key on the last line; adjust if format changes. |
| libpcap symlink | `ln -sf /usr/lib/x86_64-linux-gnu/libpcap.so /usr/lib/x86_64-linux-gnu/libpcap.so.0.8` — only valid on amd64; flag for arm64 equivalents. |
| MAC detection | `arp -n ${GATEWAY_IP} \| grep ${GATEWAY_IP} \| awk '{print $3}'` — can return `<incomplete>` if ARP is slow; add a retry loop. |
| iptables rules | All three rules use `-A` (append) on install and `-D` (delete) on uninstall — confirm symmetry. |
| `netfilter-persistent` | Called without `|| true` on install — if it fails (e.g. not yet installed), the script aborts. Install it first or add error tolerance. |
| UFW step (client uninstall) | `if [ "$REMOVE_UFW" = "yes" ] 2>/dev/null` — the `2>/dev/null` redirect on an `if` condition is a no-op and misleading; remove it. |
| `set -e` + `|| true` | iptables `-D` commands use `|| true` to tolerate missing rules — correct pattern given `set -e`. |

For each finding, produce a fix in the relevant script (or in the merged script if Task 1
is done first).

---

## Configuration Reference

Config files live in `/etc/paqet/` after installation.

- Server: `/etc/paqet/server.yaml` — requires `role: "server"`, `listen.addr`, `network.interface`, `network.ipv4.addr`, `network.ipv4.router_mac`, `transport.kcp.key`.
- Client: `/etc/paqet/client.yaml` — requires `role: "client"`, `socks5[].listen`, `network.interface`, `network.ipv4.addr`, `network.ipv4.router_mac`, `server.addr`, `transport.kcp.key`.

See `example/server.yaml.example` and `example/client.yaml.example` for all options.

---

## Release / CI Notes

- CI builds are triggered on `v*.*.*` tags via `.github/workflows/build.yml`.
- The release artifact name pattern is: `paqet-linux-amd64-<version>.tar.gz`.
- The binary inside the tarball is named `paqet_linux_amd64` (underscore-separated).
- `PAQET_VERSION` in the scripts must be kept in sync with actual release tags on the
  upstream repo (`github.com/hanselime/paqet`).
