#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034  # 변수 다수는 .bats 테스트 파일에서 사용된다
# shellcheck disable=SC2154  # status/output 은 bats 의 run 이 설정한다
#
# 공통 테스트 하네스.
#
# 안전 원칙:
#   - 모든 테스트는 임시 $HOME 에서만 동작한다.
#   - 실제 ~/.claude-accounts, ~/.claude, ~/.claude.json, Keychain 은 절대 건드리지 않는다.
#   - 토큰은 합성 값(TESTTOKEN 포함)만 쓰고, 실제 claude 대신 tests/stubs/claude 를 쓴다.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CS="$REPO_ROOT/claude-switch"
STUBS_DIR="$REPO_ROOT/tests/stubs"

# 합성 토큰. 어떤 출력에도 나타나면 안 되므로 TESTTOKEN 이라는 표식을 넣는다.
TOKEN_A="sk-ant-oat01-TESTTOKEN-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TOKEN_B="sk-ant-oat01-TESTTOKEN-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
LEAK_MARKER="TESTTOKEN"

setup_sandbox() {
  local real_home="$HOME"

  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  # 하드 안전장치: 임시 HOME 이 아니면 즉시 실패시킨다.
  if [ "$HOME" = "$real_home" ]; then
    echo "FATAL: 테스트 HOME 이 실제 HOME 과 동일함: $HOME" >&2
    return 1
  fi
  case "$HOME" in
    "$BATS_TEST_TMPDIR"/*) ;;
    *)
      echo "FATAL: 테스트 HOME 이 BATS_TEST_TMPDIR 밖에 있음: $HOME" >&2
      return 1
      ;;
  esac

  # 실제 claude 바이너리가 실행될 가능성을 두 겹으로 막는다.
  if [ ! -x "$STUBS_DIR/claude" ]; then
    echo "FATAL: claude 스텁이 실행 가능하지 않음: $STUBS_DIR/claude" >&2
    return 1
  fi
  export PATH="$STUBS_DIR:$PATH"
  export CLAUDE_SWITCH_CLAUDE_BIN="$STUBS_DIR/claude"
  if [ "$(command -v claude)" != "$STUBS_DIR/claude" ]; then
    echo "FATAL: claude 가 스텁으로 해석되지 않음: $(command -v claude)" >&2
    return 1
  fi

  export CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/claude-stub.log"
  : >"$CLAUDE_STUB_LOG"

  unset CLAUDE_CODE_OAUTH_TOKEN
  unset ANTHROPIC_API_KEY
  unset ANTHROPIC_AUTH_TOKEN
  unset CLAUDE_CODE_USE_BEDROCK
  unset CLAUDE_CODE_USE_VERTEX
  unset CLAUDE_CODE_USE_FOUNDRY
  unset ANTHROPIC_BASE_URL
  unset CLAUDE_CONFIG_DIR
  unset CLAUDE_STUB_EXIT
  unset CLAUDE_STUB_AUTH_STATUS_EXIT
  unset CLAUDE_STUB_INFERENCE_EXIT
  unset CLAUDE_STUB_STDOUT
  unset CLAUDE_STUB_READ_STDIN
  unset CLAUDE_STUB_AUTH_EXIT
  unset CLAUDE_STUB_AUTH_OUTPUT

  STORE_DIR="$HOME/.claude-switch"
  TOKENS_DIR="$STORE_DIR/tokens"
  CONFIG_FILE="$STORE_DIR/config"
  ISOLATED_DIR="$STORE_DIR/isolated"
  ACK_FILE="$STORE_DIR/.v1-acknowledged"
  V1_DIR="$HOME/.claude-accounts"
}

# ---------------------------------------------------------------- assert 헬퍼

flunk() {
  { if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else cat; fi; } >&2
  return 1
}

assert_success() {
  if [ "$status" -ne 0 ]; then
    flunk "예상: exit 0, 실제: exit $status" "출력:" "$output"
  fi
}

assert_failure() {
  local expected="${1:-}"
  if [ -z "$expected" ]; then
    if [ "$status" -eq 0 ]; then
      flunk "예상: 0 이 아닌 exit, 실제: exit 0" "출력:" "$output"
    fi
  elif [ "$status" -ne "$expected" ]; then
    flunk "예상: exit $expected, 실제: exit $status" "출력:" "$output"
  fi
}

assert_output_contains() {
  local needle="$1"
  case "$output" in
    *"$needle"*) ;;
    *) flunk "출력에 '$needle' 없음" "출력:" "$output" ;;
  esac
}

refute_output_contains() {
  local needle="$1"
  case "$output" in
    *"$needle"*) flunk "출력에 '$needle' 가 있어선 안 됨" "출력:" "$output" ;;
    *) ;;
  esac
}

# 어떤 출력에도 토큰 원문이 새지 않았는지 확인한다.
refute_token_leak() {
  refute_output_contains "$LEAK_MARKER"
}

assert_mode() {
  local path="$1" expected="$2" actual
  actual="$(stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null)"
  if [ "$actual" != "$expected" ]; then
    flunk "권한 불일치: $path 예상 $expected, 실제 ${actual:-없음}"
  fi
}

assert_file_exists() {
  [ -f "$1" ] || flunk "파일 없음: $1"
}

refute_file_exists() {
  [ ! -e "$1" ] || flunk "파일이 있어선 안 됨: $1"
}

# ------------------------------------------------------------------ 유틸리티

sha256_of() {
  printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
}

fingerprint_of() {
  sha256_of "$1" | cut -c1-8
}

# 프로필을 백엔드 계약을 우회하지 않고 등록한다(--stdin 경로 사용).
seed_profile() {
  local name="$1" token="$2"
  printf '%s\n' "$token" | "$CS" add "$name" --stdin >/dev/null 2>&1
}

stub_log() {
  cat "$CLAUDE_STUB_LOG" 2>/dev/null || true
}
