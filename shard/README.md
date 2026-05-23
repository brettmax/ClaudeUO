# Shard Overlay

Custom content layered on top of the vanilla ModernUO submodule under `../server/`.
Nothing here modifies the submodule directly so upstream pulls stay clean.

## Layout

- `ClaudeUO.Admin/` &mdash; small .NET project producing `ClaudeUO.Admin.dll`. Opens a
  localhost-only TCP socket inside the running ModernUO process for the external
  restart scheduler. See `ClaudeUO.Admin/AdminSocket.cs`.

- `Distribution-overlay/` &mdash; files that need to merge into
  `../server/Distribution/` after a ModernUO build. Currently just
  `Data/assemblies.json`, which adds `ClaudeUO.Admin.dll` to the runtime load
  list. The deploy step (`../deploy/update-server.sh`) does the copy.

- `Configuration/` &mdash; reserved for shard-specific config (era, world settings,
  account caps, etc.). Empty pending the era choice.

- `Scripts/` &mdash; reserved for shard-specific in-game content scripts. Empty
  pending the era choice. Add `.cs` files under
  `ClaudeUO.Admin/` (or a sibling project) when you need them compiled.

- `Data/` &mdash; reserved for shard-specific data files (custom regions, spawns,
  etc.) that copy into `../server/Distribution/Data/` at deploy time.

## Building locally

```bash
dotnet build ClaudeUO.Admin/ClaudeUO.Admin.csproj -c Release
```

Output lands in `../server/Distribution/ClaudeUO.Admin.dll`. Then run the
ModernUO server normally &mdash; it will pick up the admin socket on startup
(default `127.0.0.1:2595`).
