# Repo-Maintenance Syncing Steps

Add repo-specific `.sh` files here when the repository needs deterministic shared-sync steps.

The top-level `scripts/repo-maintenance/sync-shared.sh` entrypoint discovers and runs every `*.sh` file in this directory in lexical order.
