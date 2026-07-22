#!/usr/bin/env bash
# Build custom Godot web export templates for Web with C++ exceptions enabled.
#
# The default Godot web export templates are built with exceptions disabled
# (disable_exceptions=yes).  Our GDExtension uses OCCT headers that contain
# inline throw statements, which generate __cxa_allocate_exception imports
# in the SIDE_MODULE.  The main module must therefore export these symbols.
#
# This script builds custom Godot web export templates with
# `disable_exceptions=no` so the main module exports the __cxa_* symbols
# needed by our GDExtension SIDE_MODULE.
#
# No Godot source patches are applied.  We pass the Emscripten exception flag
# via scons `linkflags` instead.
#
# By default, builds all 2 combinations: debug/release (threads only).
# Use flags to restrict to specific variants.
#
# Usage:
#   ./tools/build_godot_web_templates.sh [OPTIONS] [OUTPUT_DIR]
#
# Options:
#   --mode=debug    Build only debug variant (default: both)
#   --mode=release  Build only release variant (default: both)
#   --editor        Build the editor instead of export templates
#   --clean         Clean build (remove previous build directory)
#   --version TAG   Godot version tag to build (default: auto-detect latest stable)
#   OUTPUT_DIR      Where to place the output template zips (default: demo/templates)
#
# Prerequisites:
#   - Emscripten SDK installed and activated (emcc in PATH)
#   - Python 3.9+
#   - SCons 4.4+
#   - Internet connection (for downloading Godot source)
#   - jq (for version detection from GitHub API)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults: build debug+release
BUILD_DEBUG="yes"
BUILD_RELEASE="yes"
BUILD_EDITOR=0
CLEAN=0
OUTPUT_DIR="${PROJECT_DIR}/demo/templates"
GODOT_VERSION=""  # Empty = auto-detect

EM_LINKFLAGS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode=debug)
            BUILD_DEBUG="yes"
            BUILD_RELEASE="no"
            shift
            ;;
        --mode=release)
            BUILD_DEBUG="no"
            BUILD_RELEASE="yes"
            shift
            ;;
        --editor)
            BUILD_EDITOR=1
            shift
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --version)
            GODOT_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [OUTPUT_DIR]"
            echo ""
            echo "Build custom Godot web export templates with C++ exceptions enabled."
            echo "Threads-only (nothreads is not supported due to OCCT thread dependencies)."
            echo ""
            echo "Options:"
            echo "  --mode=debug    Build only debug variant"
            echo "  --mode=release  Build only release variant"
            echo "  --editor        Build the editor instead of export templates"
            echo "  --clean         Clean build (remove previous build directory)"
            echo "  --version TAG   Godot version tag to build (default: auto-detect latest stable)"
            echo "  OUTPUT_DIR      Where to place the output (default: demo/templates)"
            exit 0
            ;;
        *)
            OUTPUT_DIR="$1"
            shift
            ;;
    esac
done

# Auto-detect latest stable Godot version (same logic as .github/workflows/main.yml)
detect_godot_version() {
    local compat_min
    compat_min=$(grep 'compatibility_minimum' "${PROJECT_DIR}/demo/addons/"*"/gdext.gdextension" | sed 's/.*= "\(.*\)"/\1/')

    local supported_json
    supported_json=$(grep '^supported_api_versions' "${PROJECT_DIR}/godot-cpp/tools/godotcpp.py" | sed 's/.*= //' | head -n 1)

    if ! echo "$supported_json" | grep -q "\"$compat_min\""; then
        echo "Error: compatibility_minimum=$compat_min is not in godot-cpp supported_api_versions" >&2
        exit 1
    fi

    # Get all supported versions >= compat_min
    local versions
    versions=$(echo "$supported_json" | jq -r '.[]')

    local latest_tag=""
    for version in $versions; do
        # Skip versions below compat_min
        if [[ "$(printf '%s\n' "$version" "$compat_min" | sort -V | head -n1)" != "$compat_min" ]]; then
            continue
        fi
        # Query GitHub API for latest release matching this major.minor prefix
        local tag
        tag=$(curl -s "https://api.github.com/repos/godotengine/godot/releases" \
            | jq -r ".[] | select(.tag_name | startswith(\"$version.\")) | .tag_name" \
            | sort -V | tail -1)
        if [ -n "$tag" ]; then
            latest_tag="$tag"
        fi
    done

    if [ -z "$latest_tag" ]; then
        echo "Error: Could not detect latest Godot version" >&2
        exit 1
    fi

    echo "$latest_tag"
}

# Check prerequisites
check_prerequisites() {
    local missing=0

    if ! command -v emcc &>/dev/null; then
        echo "Error: emcc not found. Please activate the Emscripten SDK first."
        echo "  source /path/to/emsdk/emsdk_env.sh"
        missing=1
    fi

    if ! command -v scons &>/dev/null; then
        echo "Error: scons not found. Install with: pip install scons"
        missing=1
    fi

    if ! command -v python3 &>/dev/null; then
        echo "Error: python3 not found."
        missing=1
    fi

    if ! command -v jq &>/dev/null; then
        echo "Error: jq not found. Install with: sudo apt install jq"
        missing=1
    fi

    if [ $missing -ne 0 ]; then
        exit 1
    fi

    # Validate Emscripten version matches what godot-cpp expects
    local expected_em_version
    expected_em_version=$(sed -n '/em-version:/,/default:/{s/.*default: *//p}' "${PROJECT_DIR}/godot-cpp/.github/actions/setup-godot-cpp/action.yml" | tr -d '[:space:]')
    local actual_em_version
    actual_em_version=$(emcc --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+')
    if [ -z "$expected_em_version" ]; then
        echo "Warning: Could not read expected Emscripten version from godot-cpp" >&2
    elif [ "$actual_em_version" != "$expected_em_version" ]; then
        echo "Error: Emscripten version mismatch." >&2
        echo "  Expected: ${expected_em_version} (from godot-cpp)" >&2
        echo "  Actual:   ${actual_em_version}" >&2
        echo "  Install the correct version: emsdk install ${expected_em_version} && emsdk activate ${expected_em_version}" >&2
        exit 1
    fi

    echo "Prerequisites OK"
    echo "  emcc: $(emcc --version | head -1)"
    echo "  em-version: ${actual_em_version} (matches godot-cpp: ${expected_em_version})"
    echo "  scons: $(scons --version | head -1)"
}

# Download and extract Godot source
setup_godot_source() {
    local build_dir="${PROJECT_DIR}/build"
    local godot_dir="${build_dir}/godot-${GODOT_VERSION}"

    if [ -d "$godot_dir" ]; then
        echo "Godot source already exists at: $godot_dir"
        if [ $CLEAN -eq 1 ]; then
            echo "Cleaning previous build..."
            rm -rf "$godot_dir"
        else
            return 0
        fi
    fi

    echo "Downloading Godot ${GODOT_VERSION} sources..."
    mkdir -p "$build_dir"
    cd "$build_dir"

    git clone --depth 1 --branch "${GODOT_VERSION}" \
        https://github.com/godotengine/godot.git "godot-${GODOT_VERSION}"

    cd "$PROJECT_DIR"
    echo "Godot source ready at: $godot_dir"
}

# Build a single variant (threads only)
build_one_variant() {
    local target="$1"   # template_debug, template_release, or editor

    local godot_dir="${PROJECT_DIR}/build/godot-${GODOT_VERSION}"

    echo "--- Building ${target} (threads=yes) ---"

    cd "$godot_dir"
    local scons_args=(
        -j"$(nproc)"
        platform=web
        target="${target}"
        dlink_enabled=yes
        threads=yes
        production=yes
        disable_exceptions=no
    )
    if [[ -n "${EM_LINKFLAGS}" ]]; then
        scons_args+=(linkflags="${EM_LINKFLAGS}")
    fi
    # Force all standard libraries (libc++, libc++abi, etc.) into the main
    # module so that side modules (GDExtensions) can import their symbols at
    # runtime. Without this, symbols like std::__2::__hash_memory are missing.
    # See: https://emscripten.org/docs/compiling/Dynamic-Linking.html#system-libraries
    EMCC_FORCE_STDLIBS=1 scons "${scons_args[@]}"

    cd "$PROJECT_DIR"
}

# Install a template zip to the output dir
install_template_zip() {
    local target="$1"   # template_debug or template_release

    local godot_dir="${PROJECT_DIR}/build/godot-${GODOT_VERSION}"

    local zip_file="${godot_dir}/bin/godot.web.${target}.wasm32.dlink.zip"
    [ ! -f "$zip_file" ] && zip_file="${godot_dir}/bin/godot.web.${target}.wasm32.pthreads.dlink.zip"
    [ ! -f "$zip_file" ] && zip_file="${godot_dir}/bin/godot.web.${target}.wasm32.pthreads.zip"
    if [ ! -f "$zip_file" ]; then
        echo "Error: Could not find built zip for ${target} (threads=yes)" >&2
        ls "${godot_dir}/bin/"*.zip 2>/dev/null || true
        exit 1
    fi

    local mode_name
    [ "$target" = "template_debug" ] && mode_name="debug" || mode_name="release"

    local dest_dir="${OUTPUT_DIR}/threads"
    mkdir -p "$dest_dir"
    cp "$zip_file" "${dest_dir}/web_${mode_name}.zip"
    echo "Installed: ${dest_dir}/web_${mode_name}.zip"
}

# Install editor binary to the output dir
install_editor_binary() {
    local godot_dir="${PROJECT_DIR}/build/godot-${GODOT_VERSION}"

    local zip_file="${godot_dir}/bin/godot.web.editor.wasm32.pthreads.dlink.zip"
    [ ! -f "$zip_file" ] && zip_file="${godot_dir}/bin/godot.web.editor.wasm32.pthreads.zip"
    if [ ! -f "$zip_file" ]; then
        echo "Error: Could not find built editor zip (threads=yes)" >&2
        ls "${godot_dir}/bin/"*.zip 2>/dev/null || true
        exit 1
    fi

    local dest_dir="${OUTPUT_DIR}/editor/threads"
    mkdir -p "$dest_dir"
    cp "$zip_file" "${dest_dir}/web_editor.zip"
    echo "Installed: ${dest_dir}/web_editor.zip"
}

# Build all selected variants
build_web() {
    local godot_dir="${PROJECT_DIR}/build/godot-${GODOT_VERSION}"

    if [ ! -d "$godot_dir" ]; then
        echo "Error: Godot source not found at $godot_dir"
        exit 1
    fi

    local targets=()
    [ "$BUILD_DEBUG" = "yes" ] && targets+=("template_debug")
    [ "$BUILD_RELEASE" = "yes" ] && targets+=("template_release")

    if [ $BUILD_EDITOR -eq 1 ]; then
        echo ""
        echo "=== Building Godot Web editor ==="
        echo "  Version: ${GODOT_VERSION}"
        echo "  Exceptions: enabled (disable_exceptions=no)"
        echo "  Threads: yes"
        echo ""

        build_one_variant "editor"
        install_editor_binary
    else
        echo ""
        echo "=== Building Godot Web export templates ==="
        echo "  Version: ${GODOT_VERSION}"
        echo "  Exceptions: enabled (disable_exceptions=no)"
        echo "  Variants: debug=${BUILD_DEBUG} release=${BUILD_RELEASE} threads=yes"
        echo ""

        for target in "${targets[@]}"; do
            build_one_variant "$target"
            install_template_zip "$target"
        done
    fi

    cd "$PROJECT_DIR"
}

# Main
main() {
    # Auto-detect version if not specified
    if [ -z "$GODOT_VERSION" ]; then
        echo "Auto-detecting latest stable Godot version..."
        GODOT_VERSION=$(detect_godot_version)
        echo "Detected: ${GODOT_VERSION}"
    fi

    echo ""
    echo "=== Building Custom Godot Web Build ==="
    echo "  Godot version: ${GODOT_VERSION}"
    echo "  Output: ${OUTPUT_DIR}"
    echo ""

    check_prerequisites
    setup_godot_source
    build_web

    echo ""
    echo "=== Build complete ==="
    find "${OUTPUT_DIR}" -name "*.zip" -exec ls -la {} \;

    echo ""
    echo "Done! Output installed to: ${OUTPUT_DIR}"
    if [ $BUILD_EDITOR -eq 1 ]; then
        echo "  editor/threads/web_editor.zip"
    else
        echo "  threads/web_debug.zip, threads/web_release.zip"
    fi
}

main "$@"
