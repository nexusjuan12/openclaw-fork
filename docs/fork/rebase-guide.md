# Keeping the Fork Updated

This fork tracks `openclaw/openclaw` upstream. The changes are minimal and isolated to make rebasing straightforward.

## Modified Files

These are the only files changed from upstream:

| File                             | Change                                                                        |
| -------------------------------- | ----------------------------------------------------------------------------- |
| `src/agents/tools/web-search.ts` | Added SearXNG search provider                                                 |
| `src/config/types.tools.ts`      | Added `"searxng"` to search provider type, `"ollama"` to memory provider type |
| `src/agents/memory-search.ts`    | Added `"ollama"` to provider/fallback types                                   |
| `src/memory/embeddings.ts`       | Added `"ollama"` provider dispatch (reuses OpenAI client)                     |
| `src/memory/manager.ts`          | Added `"ollama"` to provider type annotations                                 |

## New Files (fork-only)

| File                             | Purpose                         |
| -------------------------------- | ------------------------------- |
| `scripts/install-searxng.sh`     | SearXNG pip + systemd installer |
| `scripts/ollama-tunnel.sh`       | Reverse SSH tunnel helper       |
| `scripts/setup-local-first.sh`   | Full automated setup            |
| `docs/fork/local-first-setup.md` | Setup guide                     |
| `docs/fork/rebase-guide.md`      | This file                       |

## Rebase Workflow

```bash
# One-time: add upstream remote
git remote add upstream https://github.com/openclaw/openclaw.git

# Fetch latest upstream
git fetch upstream

# Rebase onto upstream main
git rebase upstream/main

# If conflicts, resolve them (see below), then:
git rebase --continue

# Push (force needed after rebase)
git push --force-with-lease origin main
```

## Conflict Resolution

Conflicts will only occur in the 5 modified files listed above. The changes are additive (new union members, new function, new config block), so conflicts are typically easy to resolve:

- **web-search.ts**: Keep both the upstream changes and the SearXNG additions. The SearXNG code is self-contained (new functions + new case in the switch).
- **types.tools.ts**: Re-add `| "searxng"` to the provider union and the `searxng` config block.
- **memory files**: Re-add `| "ollama"` to the union types and the dispatch case.

## Checking for Upstream Changes

Before rebasing, check what upstream changed in the files you modified:

```bash
git fetch upstream
git diff main..upstream/main -- src/agents/tools/web-search.ts
git diff main..upstream/main -- src/config/types.tools.ts
git diff main..upstream/main -- src/memory/embeddings.ts
git diff main..upstream/main -- src/agents/memory-search.ts
git diff main..upstream/main -- src/memory/manager.ts
```

## After Rebasing

```bash
pnpm install
pnpm build
pnpm test
```

If the build fails, check that all type unions still include the fork additions.
