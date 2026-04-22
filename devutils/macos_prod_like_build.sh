#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_WORKSPACE="$(cd "${REPO_ROOT}/.." && pwd)/helium-macos"

WORKSPACE_DIR="${DEFAULT_WORKSPACE}"
CHECKOUT_REF="main"
SKIP_DEPENDENCIES=0
SKIP_BUILD=0

usage() {
  echo "Usage: $0 [--workspace DIR] [--ref REF] [--skip-deps] [--skip-build]"
  echo
  echo "Bootstraps and runs a production-like Helium macOS build on Apple Silicon."
  echo
  echo "Options:"
  echo "  --workspace DIR   Path for helium-macos checkout (default: ${DEFAULT_WORKSPACE})"
  echo "  --ref REF         Git ref to checkout in helium-macos (default: main)"
  echo "  --skip-deps       Skip Homebrew/Xcode/Python dependency installation"
  echo "  --skip-build      Skip the final ./build.sh invocation"
  echo "  -h, --help        Show this help message"
}

log() {
  printf '[helium-macos-setup] %s\n' "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE_DIR="$2"
      shift 2
      ;;
    --ref)
      CHECKOUT_REF="$2"
      shift 2
      ;;
    --skip-deps)
      SKIP_DEPENDENCIES=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper is for macOS only." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This helper is intended for Apple Silicon (arm64)." >&2
  exit 1
fi

require_cmd git

if [[ ${SKIP_DEPENDENCIES} -eq 0 ]]; then
  require_cmd brew
  require_cmd xcodebuild

  log "Installing/updating Homebrew dependencies"
  brew install python@3.13 ninja coreutils readline quilt

  if brew list --formula binutils >/dev/null 2>&1; then
    log "Unlinking Homebrew binutils so Xcode toolchain is used"
    brew unlink binutils || true
  fi

  log "Installing Metal toolchain"
  xcodebuild -downloadComponent MetalToolchain

  PYTHON313_BIN="$(brew --prefix python@3.13)/bin/python3.13"
  if [[ ! -x "${PYTHON313_BIN}" ]]; then
    echo "Could not find python3.13 from Homebrew at ${PYTHON313_BIN}" >&2
    exit 1
  fi

  log "Installing Python build dependencies"
  "${PYTHON313_BIN}" -m pip install httplib2==0.22.0 requests pillow
fi

if [[ -d "${WORKSPACE_DIR}/.git" ]]; then
  log "Updating existing helium-macos checkout at ${WORKSPACE_DIR}"
  git -C "${WORKSPACE_DIR}" fetch origin
else
  log "Cloning helium-macos into ${WORKSPACE_DIR}"
  mkdir -p "$(dirname "${WORKSPACE_DIR}")"
  git clone --recurse-submodules https://github.com/imputnet/helium-macos.git "${WORKSPACE_DIR}"
fi

log "Checking out ${CHECKOUT_REF}"
git -C "${WORKSPACE_DIR}" checkout "${CHECKOUT_REF}"
git -C "${WORKSPACE_DIR}" pull origin "${CHECKOUT_REF}"
git -C "${WORKSPACE_DIR}" submodule update --init --recursive

if [[ ${SKIP_BUILD} -eq 1 ]]; then
  log "Setup complete (build skipped by flag)."
  exit 0
fi

log "Running production-like build: ./build.sh"
(
  cd "${WORKSPACE_DIR}"
  ./build.sh
)

log "Build finished. Look for DMG output under ${WORKSPACE_DIR}/build/"
