#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Create independent GitHub PRs from the audit fix stack.

The script builds each PR branch in a temporary clone so the current checkout is
left untouched. By default it pushes branches to origin and opens PRs against
opentoonz/opentoonz:master.

Options:
  --dry-run       Print the PR plan without creating branches, pushing, or
                  calling gh.
  --no-push       Create local branches in the temporary clone, but do not push.
  --no-pr         Push branches, but do not create GitHub PRs.
  --force         Recreate remote branches with --force-with-lease.
  -h, --help      Show this help.

Environment:
  BASE_REF        Local ref/SHA used as the branch base. Default: origin/master
  BASE_BRANCH     Upstream PR base branch. Default: master
  BASE_REPO       Upstream GitHub repository. Default: opentoonz/opentoonz
  PUSH_REMOTE     Remote to push head branches to. Default: origin
  HEAD_OWNER      GitHub owner for PR heads. Default: inferred from PUSH_REMOTE
  BRANCH_PREFIX   Prefix for generated branch names. Default: codex/audit

Example:
  scripts/create-audit-fix-prs.sh

  BASE_REF=origin/master BRANCH_PREFIX=bgyss/audit \
    scripts/create-audit-fix-prs.sh --force
USAGE
}

DRY_RUN=0
NO_PUSH=0
NO_PR=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --no-push)
            NO_PUSH=1
            ;;
        --no-pr)
            NO_PR=1
            ;;
        --force)
            FORCE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

BASE_REF="${BASE_REF:-origin/master}"
BASE_BRANCH="${BASE_BRANCH:-master}"
BASE_REPO="${BASE_REPO:-opentoonz/opentoonz}"
PUSH_REMOTE="${PUSH_REMOTE:-origin}"
BRANCH_PREFIX="${BRANCH_PREFIX:-codex/audit}"

SVG_COMMIT="a620de8bb460b061b0af69cda1a6b1965fdb70a6"
PLT_COMMIT="00d08dbe35642d5e1591f9b0b966ce77fe4aabd4"
TLV_COMMIT="92066d5e914d222df4b5703eac870ea9a97144b4"
EXTERNFX_COMMIT="d5f0531c1fde36c839523ea0c69b0e69ea71bf62"
CRASH_COMMIT="4e8122e2b511782d47f2e1d577a469779b5108c6"
THIRDPARTY_COMMIT="18068c0b5dae345968c7524a58cd9c5e762d693e"
DELETE_COMMIT="8bfbdfee8df3b362005de270f73ea23f92ce62bc"
PLT_COPY_COMMIT="17c8d7ac7bf90a2034261c70be6100dccc04e102"

FIX_KEYS=(
    svg
    plt
    tlv
    externfx
    crash
    thirdparty
    delete
)

repo_root="$(git rev-parse --show-toplevel)"
base_sha="$(git rev-parse --verify "$BASE_REF")"

infer_head_owner() {
    local url owner_repo
    url="$(git -C "$repo_root" remote get-url --push "$PUSH_REMOTE" 2>/dev/null || true)"
    case "$url" in
        git@github.com:*)
            owner_repo="${url#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            owner_repo="${url#ssh://git@github.com/}"
            ;;
        https://github.com/*)
            owner_repo="${url#https://github.com/}"
            ;;
        *)
            return 1
            ;;
    esac
    owner_repo="${owner_repo%.git}"
    printf '%s\n' "${owner_repo%%/*}"
}

HEAD_OWNER="${HEAD_OWNER:-$(infer_head_owner || true)}"

require_commit() {
    git -C "$repo_root" cat-file -e "$1^{commit}" ||
        { echo "Missing source commit: $1" >&2; exit 1; }
}

for commit in "$SVG_COMMIT" "$PLT_COMMIT" "$TLV_COMMIT" "$EXTERNFX_COMMIT" \
    "$CRASH_COMMIT" "$THIRDPARTY_COMMIT" "$DELETE_COMMIT" "$PLT_COPY_COMMIT"; do
    require_commit "$commit"
done

if [[ "$NO_PR" -eq 0 && -z "$HEAD_OWNER" ]]; then
    echo "Could not infer HEAD_OWNER from remote '$PUSH_REMOTE'. Set HEAD_OWNER explicitly." >&2
    exit 1
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
    if [[ "$NO_PR" -eq 0 ]]; then
        command -v gh >/dev/null || { echo "gh is required unless --no-pr is used" >&2; exit 1; }
    fi
fi

branch_for() {
    case "$1" in
        svg) printf '%s-svg-parser-fixed-buffers\n' "$BRANCH_PREFIX" ;;
        plt) printf '%s-plt-tzp-color-metadata-validation\n' "$BRANCH_PREFIX" ;;
        tlv) printf '%s-tlv-tzl-header-table-validation\n' "$BRANCH_PREFIX" ;;
        externfx) printf '%s-external-fx-qprocess\n' "$BRANCH_PREFIX" ;;
        crash) printf '%s-crash-symbolizer-qprocess\n' "$BRANCH_PREFIX" ;;
        thirdparty) printf '%s-third-party-tool-paths\n' "$BRANCH_PREFIX" ;;
        delete) printf '%s-file-browser-level-deletion\n' "$BRANCH_PREFIX" ;;
        *) echo "Unknown fix key: $1" >&2; exit 1 ;;
    esac
}

title_for() {
    case "$1" in
        svg) printf 'Harden SVG parser fixed buffers\n' ;;
        plt) printf 'Validate PLT/TZP color metadata\n' ;;
        tlv) printf 'Validate TLV/TZL header tables\n' ;;
        externfx) printf 'Run external FX without shell parsing\n' ;;
        crash) printf 'Run crash symbolizer without shell parsing\n' ;;
        thirdparty) printf 'Handle empty third-party tool paths\n' ;;
        delete) printf 'Delete level sidecars from the file browser\n' ;;
        *) echo "Unknown fix key: $1" >&2; exit 1 ;;
    esac
}

commit_message_for() {
    case "$1" in
        svg) printf 'Harden SVG parser fixed buffers\n' ;;
        plt) printf 'Validate PLT/TZP color metadata\n' ;;
        tlv) printf 'Validate TLV/TZL header tables\n' ;;
        externfx) printf 'Run external FX without a shell\n' ;;
        crash) printf 'Run crash symbolizer without a shell\n' ;;
        thirdparty) printf 'Handle empty third-party tool paths\n' ;;
        delete) printf 'Delete level sidecars from file browser\n' ;;
        *) echo "Unknown fix key: $1" >&2; exit 1 ;;
    esac
}

write_audit_cmake() {
    cat <<'CMAKE'
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/svg_parser_regression.cpp")
    add_executable(svg_parser_regression svg_parser_regression.cpp)

    target_include_directories(svg_parser_regression PRIVATE ${CMAKE_SOURCE_DIR})

    target_link_libraries(svg_parser_regression
        Qt5::Core
        Qt5::Gui
        Qt5::Network
        Qt5::OpenGL
        Qt5::Svg
        Qt5::Xml
        Qt5::Script
        Qt5::Widgets
        Qt5::PrintSupport
        Qt5::Multimedia
        tnzcore
        tnzbase
        toonzlib
    )

    if(BUILD_ENV_APPLE)
        add_custom_command(
            TARGET svg_parser_regression POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:tnzcore>
                $<TARGET_FILE:tnzbase>
                $<TARGET_FILE:tnzext>
                $<TARGET_FILE:toonzlib>
                $<TARGET_FILE_DIR:svg_parser_regression>
            VERBATIM
        )
    endif()

    add_test(NAME svg_parser_regression COMMAND svg_parser_regression)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tzp_color_names_regression.c")
    add_executable(tzp_color_names_regression
        tzp_color_names_regression.c
        ${CMAKE_SOURCE_DIR}/image/tzp/avl.c
    )

    target_include_directories(tzp_color_names_regression PRIVATE ${CMAKE_SOURCE_DIR})

    add_test(NAME tzp_color_names_regression COMMAND tzp_color_names_regression)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tzl_header_regression.cpp")
    add_executable(tzl_header_regression tzl_header_regression.cpp)

    target_include_directories(tzl_header_regression PRIVATE ${CMAKE_SOURCE_DIR})

    target_link_libraries(tzl_header_regression
        Qt5::Core
        image
    )

    if(BUILD_ENV_APPLE)
        add_custom_command(
            TARGET tzl_header_regression POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:tnzcore>
                $<TARGET_FILE:tnzbase>
                $<TARGET_FILE:tnzext>
                $<TARGET_FILE:toonzlib>
                $<TARGET_FILE:image>
                $<TARGET_FILE_DIR:tzl_header_regression>
            VERBATIM
        )
    endif()

    add_test(NAME tzl_header_regression COMMAND tzl_header_regression)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/externfx_process_regression.cpp")
    add_executable(externfx_process_regression externfx_process_regression.cpp)

    target_include_directories(externfx_process_regression PRIVATE ${CMAKE_SOURCE_DIR})

    target_link_libraries(externfx_process_regression
        Qt5::Core
        tnzbase
        image
    )

    if(BUILD_ENV_APPLE)
        add_custom_command(
            TARGET externfx_process_regression POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:tnzcore>
                $<TARGET_FILE:tnzbase>
                $<TARGET_FILE:tnzext>
                $<TARGET_FILE:toonzlib>
                $<TARGET_FILE:image>
                $<TARGET_FILE_DIR:externfx_process_regression>
            VERBATIM
        )
    endif()

    add_test(NAME externfx_process_regression COMMAND externfx_process_regression)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty_empty_path_regression.cpp")
    add_executable(thirdparty_empty_path_regression thirdparty_empty_path_regression.cpp)

    target_include_directories(thirdparty_empty_path_regression PRIVATE ${CMAKE_SOURCE_DIR})

    target_link_libraries(thirdparty_empty_path_regression
        Qt5::Core
        toonzlib
    )

    if(BUILD_ENV_APPLE)
        add_custom_command(
            TARGET thirdparty_empty_path_regression POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:tnzcore>
                $<TARGET_FILE:tnzbase>
                $<TARGET_FILE:tnzext>
                $<TARGET_FILE:toonzlib>
                $<TARGET_FILE_DIR:thirdparty_empty_path_regression>
            VERBATIM
        )
    endif()

    add_test(NAME thirdparty_empty_path_regression COMMAND thirdparty_empty_path_regression)
endif()
CMAKE
}

install_test_harness() {
    git checkout "$SVG_COMMIT" -- \
        toonz/sources/CMakeLists.txt \
        toonz/sources/tests/CMakeLists.txt
    mkdir -p toonz/sources/tests/audit
    write_audit_cmake > toonz/sources/tests/audit/CMakeLists.txt
}

prepare_fix() {
    case "$1" in
        svg)
            install_test_harness
            git checkout "$SVG_COMMIT" -- \
                toonz/sources/image/svg/tiio_svg.cpp \
                toonz/sources/tests/audit/svg_parser_regression.cpp
            ;;
        plt)
            install_test_harness
            git checkout "$PLT_COMMIT" -- \
                toonz/sources/image/tzp/tiio_plt.cpp \
                toonz/sources/tests/audit/tzp_color_names_regression.c
            git checkout "$PLT_COPY_COMMIT" -- \
                toonz/sources/image/tzp/avl.c
            ;;
        tlv)
            install_test_harness
            git checkout "$TLV_COMMIT" -- \
                toonz/sources/image/tzl/tiio_tzl.cpp \
                toonz/sources/tests/audit/tzl_header_regression.cpp
            ;;
        externfx)
            install_test_harness
            git checkout "$EXTERNFX_COMMIT" -- \
                toonz/sources/tnzbase/texternfx.cpp \
                toonz/sources/tests/audit/externfx_process_regression.cpp
            ;;
        crash)
            git checkout "$CRASH_COMMIT" -- \
                toonz/sources/toonz/crashhandler.cpp
            ;;
        thirdparty)
            install_test_harness
            git checkout "$THIRDPARTY_COMMIT" -- \
                toonz/sources/toonzlib/thirdparty.cpp \
                toonz/sources/tests/audit/thirdparty_empty_path_regression.cpp
            ;;
        delete)
            git checkout "$DELETE_COMMIT" -- \
                toonz/sources/toonz/fileselection.cpp
            ;;
        *)
            echo "Unknown fix key: $1" >&2
            exit 1
            ;;
    esac
}

write_body() {
    case "$1" in
        svg)
            cat > "$2" <<'BODY'
## Summary

- Bounds fixed local copies and scans in the SVG parser.
- Rejects or truncates oversized SVG path-like tokens before stack storage can overflow.
- Adds `svg_parser_regression` with deliberately oversized SVG input.

## Validation

- Original split source commit: `a620de8bb`
- Regression target: `svg_parser_regression`
- Previous full-stack validation included the regression test and `image` target build.
BODY
            ;;
        plt)
            cat > "$2" <<'BODY'
## Summary

- Handles missing optional `TOONZCOLORNAMES` data in PLT/TZP metadata.
- Caps parsed effect parameter counts before copying into fixed local storage.
- Replaces the remaining touched `strcpy`/`strncpy` helpers with exact-length copies.
- Adds `tzp_color_names_regression` for missing metadata and excessive parameter counts.

## Validation

- Original split source commits: `00d08dbe3`, `17c8d7ac7`
- Regression target: `tzp_color_names_regression`
- Previous full-stack validation included the regression test, `image` target build, and focused Semgrep re-scan.
BODY
            ;;
        tlv)
            cat > "$2" <<'BODY'
## Summary

- Validates TLV/TZL frame counts, offset-table positions, table byte sizes, suffix lengths, and checked read/seek behavior.
- Fails malformed TLV headers cleanly before decoded values drive unchecked table logic.
- Adds `tzl_header_regression`.

## Validation

- Original split source commit: `92066d5e9`
- Regression target: `tzl_header_regression`
- Previous full-stack validation included the regression test and `image` target build.
BODY
            ;;
        externfx)
            cat > "$2" <<'BODY'
## Summary

- Replaces POSIX external-FX `system()` command execution with `QProcess`.
- Passes the selected executable and options as explicit arguments so shell metacharacters remain data.
- Adds `externfx_process_regression` for a payload that would create a marker file if interpreted by a shell.

## Validation

- Original split source commit: `d5f0531c1`
- Regression target: `externfx_process_regression`
- Previous full-stack validation included the regression test and `tnzbase` target build.
BODY
            ;;
        crash)
            cat > "$2" <<'BODY'
## Summary

- Runs `atos`/`addr2line` via `QProcess` instead of composing a shell command for `popen`.
- Uses explicit argument lists, merged output, and a bounded wait while preserving symbolization behavior.

## Validation

- Original split source commit: `4e8122e2b`
- Previous full-stack validation built the `OpenToonz` target.
- This path is build-validated because a reliable unit test would require a crash harness.
BODY
            ;;
        thirdparty)
            cat > "$2" <<'BODY'
## Summary

- Handles blank FFmpeg, FFprobe, and Rhubarb preference paths before indexing the first character.
- Keeps existing relative-path behavior for non-empty configured tool paths.
- Adds `thirdparty_empty_path_regression`.

## Validation

- Original split source commit: `18068c0b5`
- Regression target: `thirdparty_empty_path_regression`
- Previous full-stack validation included the regression test and `toonzlib` target build.
BODY
            ;;
        delete)
            cat > "$2" <<'BODY'
## Summary

- Routes simple-level deletion from the file browser through `TXshSimpleLevel::removeFiles`.
- Preserves the existing recycle-bin behavior for non-level files.
- Avoids leaving related palette, hook, or sidecar resources behind.

## Validation

- Original split source commit: `8bfbdfee8`
- Previous full-stack validation built the `OpenToonz` target.
- A non-destructive UI unit test was not added because this path intentionally moves user-visible files to the platform trash.
BODY
            ;;
        *)
            echo "Unknown fix key: $1" >&2
            exit 1
            ;;
    esac
}

echo "Base ref:       $BASE_REF ($base_sha)"
echo "PR base:        $BASE_REPO:$BASE_BRANCH"
echo "Push remote:    $PUSH_REMOTE"
echo "Head owner:     ${HEAD_OWNER:-"(not needed)"}"
echo "Branch prefix:  $BRANCH_PREFIX"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
    for key in "${FIX_KEYS[@]}"; do
        printf 'would create %-50s %s\n' "$(branch_for "$key")" "$(title_for "$key")"
    done
    exit 0
fi

workdir="$(mktemp -d /private/tmp/opentoonz-audit-prs.XXXXXX)"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT

git clone --no-hardlinks --quiet "$repo_root" "$workdir"

fetch_url="$(git -C "$repo_root" remote get-url "$PUSH_REMOTE")"
push_url="$(git -C "$repo_root" remote get-url --push "$PUSH_REMOTE")"
git -C "$workdir" remote set-url "$PUSH_REMOTE" "$fetch_url"
git -C "$workdir" remote set-url --push "$PUSH_REMOTE" "$push_url"

cd "$workdir"

for key in "${FIX_KEYS[@]}"; do
    branch="$(branch_for "$key")"
    title="$(title_for "$key")"
    commit_message="$(commit_message_for "$key")"

    echo "Creating $branch"
    git switch --quiet --detach "$base_sha"
    git switch --quiet -c "$branch"
    prepare_fix "$key"
    git add -A
    git commit --quiet -m "$commit_message"

    if [[ "$NO_PUSH" -eq 0 ]]; then
        if [[ "$FORCE" -eq 1 ]]; then
            git push --force-with-lease --set-upstream "$PUSH_REMOTE" "$branch"
        else
            git push --set-upstream "$PUSH_REMOTE" "$branch"
        fi
    fi

    if [[ "$NO_PR" -eq 0 ]]; then
        body_file="$(mktemp /private/tmp/opentoonz-pr-body.XXXXXX)"
        write_body "$key" "$body_file"
        existing_url="$(gh pr list \
            --repo "$BASE_REPO" \
            --head "$HEAD_OWNER:$branch" \
            --state all \
            --json url \
            --jq '.[0].url')"
        if [[ -n "$existing_url" ]]; then
            echo "PR already exists: $existing_url"
        else
            gh pr create \
                --repo "$BASE_REPO" \
                --base "$BASE_BRANCH" \
                --head "$HEAD_OWNER:$branch" \
                --title "$title" \
                --body-file "$body_file"
        fi
        rm -f "$body_file"
    fi
done
