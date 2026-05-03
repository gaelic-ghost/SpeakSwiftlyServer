#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_profile_env
load_env_file "$SELF_DIR/config/release.env"

mode="${REPO_MAINTENANCE_DEFAULT_RELEASE_MODE:-standard}"
release_tag=""
skip_validate="false"
skip_gh_release="false"
skip_version_bump="false"
base_branch="${REPO_MAINTENANCE_RELEASE_BRANCH:-main}"
review_comments_addressed="false"
skip_branch_cleanup="false"
dry_run="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --version)
      release_tag="${2:-}"
      shift 2
      ;;
    --skip-validate)
      skip_validate="true"
      shift
      ;;
    --skip-gh-release)
      skip_gh_release="true"
      shift
      ;;
    --skip-version-bump)
      skip_version_bump="true"
      shift
      ;;
    --base-branch)
      base_branch="${2:-}"
      shift 2
      ;;
    --review-comments-addressed)
      review_comments_addressed="true"
      shift
      ;;
    --skip-branch-cleanup)
      skip_branch_cleanup="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  release.sh --mode standard --version <vX.Y.Z> [--base-branch main] [--skip-validate] [--skip-version-bump] [--skip-gh-release] [--review-comments-addressed] [--skip-branch-cleanup] [--dry-run]
  release.sh --mode submodule --version <vX.Y.Z> [--skip-validate] [--skip-gh-release] [--dry-run]
USAGE
      exit 0
      ;;
    *)
      die "Unknown release argument: $1"
      ;;
  esac
done

[ -n "$release_tag" ] || die "Pass --version vX.Y.Z when running the release workflow."

export REPO_MAINTENANCE_RELEASE_MODE="$mode"
export RELEASE_TAG="$release_tag"
export REPO_MAINTENANCE_SKIP_GH_RELEASE="$skip_gh_release"
export REPO_MAINTENANCE_DRY_RUN="$dry_run"

ensure_clean_worktree() {
  status_output="$(git -C "$REPO_ROOT" status --porcelain)"
  [ -z "$status_output" ] || die "Release workflow requires committed changes and a clean worktree before it can continue."
}

ensure_gh_cli() {
  command -v gh >/dev/null 2>&1 || die "Standard release mode requires the GitHub CLI gh so it can create the pull request, watch CI, inspect review comments, merge, and publish the release."
}

ensure_semver_tag() {
  case "$RELEASE_TAG" in
    v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*.[0-9]*-*)
      ;;
    *)
      die "Release tag must use vX.Y.Z SemVer syntax."
      ;;
  esac
}

current_branch() {
  git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true
}

ensure_branch_release_context() {
  branch_name="$(current_branch)"
  [ -n "$branch_name" ] || die "Standard release mode requires a named feature branch or worktree instead of detached HEAD."
  [ "$branch_name" != "$base_branch" ] || die "Standard release mode must run from a release branch or worktree, not protected $base_branch."
  printf '%s\n' "$branch_name"
}

run_version_bump() {
  release_version="${RELEASE_TAG#v}"
  version_bump_script="$SELF_DIR/version-bump.sh"

  if [ "$skip_version_bump" = "true" ]; then
    log "Skipping repo version bump because --skip-version-bump was requested."
    return 0
  fi

  [ -x "$version_bump_script" ] || die "Standard release mode expected an executable repo-specific version bump hook at $version_bump_script. Add that hook so the repo's version surfaces move together, or rerun with --skip-version-bump when this release intentionally has no version-bearing files."

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would run $version_bump_script $release_version with RELEASE_TAG=$RELEASE_TAG."
    return 0
  fi

  RELEASE_VERSION="$release_version" "$version_bump_script" "$release_version"

  if [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    die "Version bump hook completed without changing files. Update $version_bump_script to edit the repo's version surfaces, or rerun with --skip-version-bump if this release intentionally has no version bump."
  fi

  git -C "$REPO_ROOT" add -A
  git -C "$REPO_ROOT" commit -m "release: bump versions for $RELEASE_TAG"
  log "Committed version bump for $RELEASE_TAG."
}

create_release_tag() {
  head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  tag_sha="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$RELEASE_TAG" 2>/dev/null || true)"

  if [ -n "$tag_sha" ]; then
    tag_commit_sha="$(git -C "$REPO_ROOT" rev-list -n 1 "$RELEASE_TAG")"
    [ "$tag_commit_sha" = "$head_sha" ] || die "Tag $RELEASE_TAG already exists and does not point at HEAD."
    log "Tag $RELEASE_TAG already points at HEAD."
    return 0
  fi

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would create annotated tag $RELEASE_TAG at HEAD."
    return 0
  fi

  git -C "$REPO_ROOT" tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG"
  log "Created annotated tag $RELEASE_TAG."
}

push_release_branch() {
  branch_name="$1"

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would push branch $branch_name to origin."
    return 0
  fi

  git -C "$REPO_ROOT" push -u origin "$branch_name"
  log "Pushed branch $branch_name."
  wait_for_remote_branch "$branch_name"
}

push_release_tag() {
  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would push tag $RELEASE_TAG to origin."
    return 0
  fi

  git -C "$REPO_ROOT" push origin "$RELEASE_TAG"
  log "Pushed tag $RELEASE_TAG."
  wait_for_remote_tag "$RELEASE_TAG"
}

create_or_update_pr() {
  branch_name="$1"
  PR_NUMBER=""

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would create or update a release PR from $branch_name into $base_branch."
    PR_NUMBER="DRY-RUN"
    return 0
  fi

  body_file="$(mktemp "${TMPDIR:-/tmp}/repo-maintenance-release-pr.XXXXXX")"
  trap 'rm -f "$body_file"' EXIT INT TERM

  cat >"$body_file" <<EOF
## Release

- prepares $RELEASE_TAG from branch \`$branch_name\`
- keeps protected \`$base_branch\` updates behind pull request review and CI
- release tag \`$RELEASE_TAG\` will be created after CI and the review-comment gate pass, so failed or still-discussed release candidates do not get tagged

## Review Loop

Before merge and tagging, \`scripts/repo-maintenance/release.sh\` watches CI and stops on review comments unless the maintainer has already addressed or resolved them and reruns with \`--review-comments-addressed\`.
EOF

  pr_number="$(gh pr list --head "$branch_name" --base "$base_branch" --json number --jq '.[0].number // empty' --limit 1)"
  if [ -n "$pr_number" ]; then
    pr_url="$(gh pr view "$pr_number" --json url --jq '.url')"
    gh pr edit "$pr_number" --title "release: prepare $RELEASE_TAG" --body-file "$body_file" >/dev/null
    log "Updated existing release PR #$pr_number at $pr_url."
  else
    gh pr create --base "$base_branch" --head "$branch_name" --title "release: prepare $RELEASE_TAG" --body-file "$body_file" >/dev/null
    pr_number="$(gh pr list --head "$branch_name" --base "$base_branch" --json number --jq '.[0].number // empty' --limit 1)"
    [ -n "$pr_number" ] || die "GitHub CLI did not return a release PR number after creating the pull request."
    pr_url="$(gh pr view "$pr_number" --json url --jq '.url')"
    log "Created release PR #$pr_number at $pr_url."
    PR_NUMBER="$pr_number"
    return 0
  fi

  PR_NUMBER="$pr_number"
}

watch_ci() {
  pr_number="$1"

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would watch CI for PR #$pr_number."
    return 0
  fi

  wait_for_initial_pr_checks "$pr_number"

  log "Watching CI for PR #$pr_number."
  if ! gh pr checks "$pr_number" --watch; then
    die "CI is not green for PR #$pr_number. Fix the failing checks, push the branch, and rerun release.sh so it can watch CI again."
  fi
  log "CI is green for PR #$pr_number."
}

wait_for_initial_pr_checks() {
  pr_number="$1"
  timeout_seconds="$(github_wait_timeout "${REPO_MAINTENANCE_INITIAL_CHECK_TIMEOUT_SECONDS:-}")"
  poll_seconds="$(github_wait_poll_seconds "${REPO_MAINTENANCE_INITIAL_CHECK_POLL_SECONDS:-}")"
  elapsed_seconds="0"
  last_state="no check data returned yet"

  log "Waiting up to ${timeout_seconds}s for GitHub to report initial checks on PR #$pr_number."

  while :; do
    last_state="$(gh pr checks "$pr_number" --json name,state,workflow --jq 'map(.name + ":" + .state) | join(", ")' 2>/dev/null || printf 'no checks reported')"
    check_count="$(gh pr checks "$pr_number" --json name,state,workflow --jq 'length' 2>/dev/null || printf '0')"
    case "$check_count" in
      ''|*[!0-9]*)
        check_count="0"
        ;;
    esac

    if [ "$check_count" -gt 0 ]; then
      log "Found $check_count initial check(s) for PR #$pr_number."
      return 0
    fi

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      die "No checks were reported for PR #$pr_number after ${timeout_seconds}s. Last observed state: $last_state. Confirm the GitHub Actions workflow triggers for the release branch, Actions is enabled, and the branch push succeeded before rerunning release.sh."
    fi

    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
  done
}

wait_for_pr_review_state() {
  pr_number="$1"
  timeout_seconds="$(github_wait_timeout "${REPO_MAINTENANCE_PR_REVIEW_TIMEOUT_SECONDS:-}")"
  poll_seconds="$(github_wait_poll_seconds "${REPO_MAINTENANCE_PR_REVIEW_POLL_SECONDS:-}")"
  elapsed_seconds="0"
  last_state="PR review/comment state has not been read yet"

  log "Waiting up to ${timeout_seconds}s for GitHub review/comment state on PR #$pr_number."

  while :; do
    last_state="$(gh pr view "$pr_number" --json reviewDecision,comments,reviews --jq '"reviewDecision=" + (.reviewDecision // "") + ", comments=" + ((.comments | length) | tostring) + ", reviews=" + ((.reviews | length) | tostring)' 2>/dev/null || printf 'GitHub did not return PR review/comment state')"
    case "$last_state" in
      "GitHub did not return PR review/comment state")
        ;;
      *)
        log "GitHub review/comment state is readable for PR #$pr_number: $last_state."
        return 0
        ;;
    esac

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      die "GitHub review/comment state for PR #$pr_number was not readable after ${timeout_seconds}s. Last observed state: $last_state. Confirm the PR exists and GitHub is returning review data before rerunning release.sh."
    fi

    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
  done
}

check_pr_comments() {
  pr_number="$1"

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would check PR #$pr_number for comments and requested changes."
    return 0
  fi

  wait_for_pr_review_state "$pr_number"

  review_decision="$(gh pr view "$pr_number" --json reviewDecision --jq '.reviewDecision // ""')"
  comment_count="$(gh pr view "$pr_number" --json comments,reviews --jq '([.comments[]?, (.reviews[]? | select(.state == "COMMENTED"))] | length)')"

  if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
    gh pr view "$pr_number" --comments
    die "PR #$pr_number has requested changes. Address valid concerns in code, or add out-of-scope concerns to ROADMAP.md, resolve the threads, push, and rerun release.sh."
  fi

  if [ "$comment_count" != "0" ] && [ "$review_comments_addressed" != "true" ]; then
    gh pr view "$pr_number" --comments
    die "PR #$pr_number has review or discussion comments. Address and resolve valid concerns, add out-of-scope concerns to ROADMAP.md, then rerun release.sh with --review-comments-addressed once the comment pass is intentionally complete."
  fi

  log "PR #$pr_number has no blocking review state."
}

merge_pr() {
  pr_number="$1"

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would merge PR #$pr_number into $base_branch with a merge commit and delete the remote branch."
    return 0
  fi

  gh pr merge "$pr_number" --merge --delete-branch
  log "Merged PR #$pr_number into $base_branch."
}

fast_forward_base_branch() {
  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would fast-forward local $base_branch from origin/$base_branch."
    return 0
  fi

  git -C "$REPO_ROOT" fetch origin "$base_branch"
  if git -C "$REPO_ROOT" switch "$base_branch" 2>/dev/null || git -C "$REPO_ROOT" checkout "$base_branch" 2>/dev/null; then
    git -C "$REPO_ROOT" pull --ff-only origin "$base_branch"
    log "Fast-forwarded local $base_branch."
  else
    die "Could not check out local $base_branch, likely because another worktree owns it. Fast-forward $base_branch from origin/$base_branch in that checkout, then rerun release.sh so the release tag is created from the reviewed base branch."
  fi
}

create_github_release() {
  if [ "$REPO_MAINTENANCE_SKIP_GH_RELEASE" = "true" ]; then
    log "Skipping GitHub release creation because --skip-gh-release was requested."
    return 0
  fi

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would create a GitHub release for $RELEASE_TAG with gh release create --verify-tag."
    return 0
  fi

  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    log "GitHub release $RELEASE_TAG already exists."
    return 0
  fi

  gh release create "$RELEASE_TAG" --verify-tag --generate-notes
  log "Created GitHub release $RELEASE_TAG."
  wait_for_github_release "$RELEASE_TAG"
}

cleanup_merged_branches() {
  release_branch_name="$1"

  if [ "$skip_branch_cleanup" = "true" ]; then
    log "Skipping local merged-branch cleanup because --skip-branch-cleanup was requested."
    return 0
  fi

  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would prune origin and delete local branches already merged into $base_branch, including $release_branch_name when safe."
    return 0
  fi

  git -C "$REPO_ROOT" remote prune origin
  for merged_branch in $(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' --merged "$base_branch" refs/heads); do
    case "$merged_branch" in
      "$base_branch")
        ;;
      *)
        git -C "$REPO_ROOT" branch -d "$merged_branch" >/dev/null 2>&1 || warn "Could not delete local merged branch $merged_branch; it may be checked out in another worktree."
        ;;
    esac
  done
  log "Cleaned up local branches already merged into $base_branch where safe."
}

run_standard_release() {
  ensure_git_repo
  ensure_gh_cli
  ensure_semver_tag
  branch_name="$(ensure_branch_release_context)"
  ensure_clean_worktree

  if [ "$skip_validate" != "true" ]; then
    sh "$SELF_DIR/validate-all.sh"
  fi

  run_version_bump
  ensure_clean_worktree
  push_release_branch "$branch_name"
  create_or_update_pr "$branch_name"
  pr_number="$PR_NUMBER"
  watch_ci "$pr_number"
  check_pr_comments "$pr_number"
  merge_pr "$pr_number"
  fast_forward_base_branch
  create_release_tag
  push_release_tag
  create_github_release
  cleanup_merged_branches "$branch_name"
  log "Standard release flow completed successfully for $RELEASE_TAG."
}

if [ "$mode" = "standard" ]; then
  run_standard_release
  exit 0
fi

if [ "$skip_validate" != "true" ]; then
  sh "$SELF_DIR/validate-all.sh"
fi

log "Running repo-maintenance release flow in $REPO_MAINTENANCE_RELEASE_MODE mode for $RELEASE_TAG with the $REPO_MAINTENANCE_PROFILE profile."
run_dispatch_dir "$SELF_DIR/release" "release"

if [ "$REPO_MAINTENANCE_RELEASE_MODE" = "submodule" ]; then
  log "Submodule release finished. Update the parent repository's submodule pointer in a separate follow-up commit."
fi

log "Repo-maintenance release flow completed successfully."
