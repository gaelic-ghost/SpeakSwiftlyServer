#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/release.env"

release_tag=""
base_branch="$(release_branch)"
skip_validate="false"
auto_merge="true"
merge_method="${REPO_MAINTENANCE_DEFAULT_PREPARE_MERGE_METHOD:-merge}"
wait_for_merge="false"
title=""
body_file=""
explicit_body_file="false"
draft="false"
dry_run="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      release_tag="${2:-}"
      shift 2
      ;;
    --base-branch)
      base_branch="${2:-}"
      shift 2
      ;;
    --skip-validate)
      skip_validate="true"
      shift
      ;;
    --no-auto-merge)
      auto_merge="false"
      shift
      ;;
    --merge-method)
      merge_method="${2:-}"
      shift 2
      ;;
    --wait-for-merge)
      wait_for_merge="true"
      shift
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --body-file)
      body_file="${2:-}"
      explicit_body_file="true"
      shift 2
      ;;
    --draft)
      draft="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  release-prepare.sh --version <vX.Y.Z> [--base-branch <branch>] [--skip-validate] [--no-auto-merge] [--merge-method <merge|rebase|squash>] [--wait-for-merge] [--title <text>] [--body-file <path>] [--draft] [--dry-run]

This workflow is for feature branches and worktrees. It validates the checkout, stages the release candidate artifact locally, pushes the current branch, opens or updates a pull request, and enables auto-merge by default.
USAGE
      exit 0
      ;;
    *)
      die "Unknown release-prepare argument: $1"
      ;;
  esac
done

[ -n "$release_tag" ] || die "Pass --version vX.Y.Z when running the release-prepare workflow."

export RELEASE_TAG="$release_tag"
export REPO_MAINTENANCE_DRY_RUN="$dry_run"

ensure_git_repo
ensure_gh_cli
ensure_release_tag_format
branch_name="$(ensure_named_branch)"
ensure_not_on_release_branch
ensure_clean_worktree

case "$merge_method" in
  merge|rebase|squash)
    ;;
  *)
    die "Merge method must be merge, rebase, or squash."
    ;;
esac

tag_sha="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$RELEASE_TAG" 2>/dev/null || true)"
[ -z "$tag_sha" ] || die "Tag $RELEASE_TAG already exists. Release prepare is only for unpublished release candidates."

if [ "$skip_validate" != "true" ]; then
  sh "$SELF_DIR/validate-all.sh"
fi

log "Running release-prepare for $RELEASE_TAG from $branch_name against base branch $base_branch."
stage_release_artifact

if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
  log "Would push branch $branch_name to $(release_remote)."
else
  git -C "$REPO_ROOT" push -u "$(release_remote)" "$branch_name"
  log "Pushed branch $branch_name to $(release_remote)."
fi

created_body_file="false"
if [ -z "$body_file" ]; then
  body_file="$(mktemp "${TMPDIR:-/tmp}/release-prepare-body.XXXXXX")"
  created_body_file="true"
  cat >"$body_file" <<EOF
## Release Prepare

- prepares release candidate \`$RELEASE_TAG\`
- stages the local artifact under \`.release-artifacts/$RELEASE_TAG\`
- leaves final tag creation and GitHub release publication for \`scripts/repo-maintenance/release-publish.sh\` after this pull request lands on \`$base_branch\`

## Publish Follow-Up

After this pull request merges, switch to \`$base_branch\` locally and run:

\`\`\`bash
scripts/repo-maintenance/release-publish.sh --version $RELEASE_TAG --skip-live-service-refresh
\`\`\`
EOF
fi

cleanup() {
  if [ "$created_body_file" = "true" ] && [ -n "$body_file" ] && [ -f "$body_file" ]; then
    rm -f "$body_file"
  fi
}
trap cleanup EXIT INT TERM

[ -n "$title" ] || title="release: prepare $RELEASE_TAG"

pr_json="$(gh pr list --head "$branch_name" --json number,url,state,title --limit 1 2>/dev/null || true)"
if [ -n "$pr_json" ] && [ "$pr_json" != "[]" ]; then
  pr_json="$(printf '%s' "$pr_json" | jq '.[0]')"
else
  pr_json=""
fi
if [ -n "$pr_json" ]; then
  pr_number="$(printf '%s' "$pr_json" | jq -r '.number')"
  pr_url="$(printf '%s' "$pr_json" | jq -r '.url')"
  pr_state="$(printf '%s' "$pr_json" | jq -r '.state')"
  [ "$pr_state" = "OPEN" ] || die "Branch $branch_name is already associated with PR #$pr_number in state $pr_state. Close or reopen that PR before re-running release prepare."

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would update existing PR #$pr_number ($pr_url) title/body if overrides were provided."
  else
    if [ -n "$title" ] && [ "$title" != "$(printf '%s' "$pr_json" | jq -r '.title')" ]; then
      gh pr edit "$pr_number" --title "$title" >/dev/null
    fi
    if [ "$explicit_body_file" = "true" ]; then
      gh pr edit "$pr_number" --body-file "$body_file" >/dev/null
    fi
    log "Updated existing PR #$pr_number at $pr_url."
  fi
else
  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would create a pull request from $branch_name into $base_branch with title: $title"
    pr_number="DRY-RUN"
    pr_url="DRY-RUN"
  else
    if [ "$draft" = "true" ]; then
      gh pr create --base "$base_branch" --head "$branch_name" --title "$title" --body-file "$body_file" --draft >/dev/null
    else
      gh pr create --base "$base_branch" --head "$branch_name" --title "$title" --body-file "$body_file" >/dev/null
    fi
    pr_json="$(gh pr list --head "$branch_name" --json number,url --limit 1 | jq '.[0]')"
    pr_number="$(printf '%s' "$pr_json" | jq -r '.number')"
    pr_url="$(printf '%s' "$pr_json" | jq -r '.url')"
    log "Created PR #$pr_number at $pr_url."
  fi
fi

if [ "$auto_merge" = "true" ]; then
  case "$merge_method" in
    merge)
      merge_flag="--merge"
      ;;
    rebase)
      merge_flag="--rebase"
      ;;
    squash)
      merge_flag="--squash"
      ;;
  esac

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would enable auto-merge on PR #$pr_number using the $merge_method method."
  else
    gh pr merge "$pr_number" --auto "$merge_flag" --delete-branch >/dev/null
    log "Enabled auto-merge on PR #$pr_number using the $merge_method method."
  fi
else
  log "Leaving PR auto-merge disabled because --no-auto-merge was requested."
fi

if [ "$wait_for_merge" = "true" ]; then
  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would wait for PR #$pr_number to merge."
  else
    log "Waiting for PR #$pr_number to merge."
    while :; do
      pr_state="$(gh pr view "$pr_number" --json state --jq '.state')"
      case "$pr_state" in
        MERGED)
          log "PR #$pr_number is merged."
          break
          ;;
        OPEN)
          sleep 10
          ;;
        *)
          die "PR #$pr_number moved to state $pr_state before merging."
          ;;
      esac
    done
  fi
fi

log "Release prepare completed. After this PR merges, switch to $base_branch and run release-publish.sh for $RELEASE_TAG."
