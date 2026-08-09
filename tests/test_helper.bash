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
UNINSTALL="$REPO_ROOT/uninstall.sh"
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

# --------------------------------------------------- uninstall.sh 전용 하네스
#
# 안전 원칙(제거 테스트 추가분):
#   - 명령 검색 경로는 반드시 BATS_TEST_TMPDIR 안으로 고정한다. 실제
#     /opt/homebrew/bin, /usr/local/bin, ~/.local/bin 은 절대 검색하지 않는다.
#   - Keychain 은 임시 HOME 으로 격리되지 않는다. security 스텁이 PATH 앞단에
#     실제로 잡히는지 확인하고, 스텁 로그가 비어 있는지로 호출 여부를 검증한다.

setup_uninstall_sandbox() {
  setup_sandbox || return 1

  # uninstall.sh 는 검색 경로의 상위 구성요소가 심볼릭 링크면 제거를 거부한다.
  # macOS 의 $TMPDIR 은 /var/folders/... 이고 /var 자체가 심볼릭 링크이므로,
  # 검색 경로만 물리 경로(/private/var/...)로 정규화해 둔다. HOME 은 건드리지 않는다.
  TMP_ROOT="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  FAKE_BIN_A="$TMP_ROOT/bin-a"
  FAKE_BIN_B="$TMP_ROOT/bin-b"
  mkdir -p "$FAKE_BIN_A" "$FAKE_BIN_B"
  export CLAUDE_SWITCH_BIN_DIRS="$FAKE_BIN_A:$FAKE_BIN_B"

  # 하드 안전장치: 검색 경로가 하나라도 임시 디렉터리 밖이면 즉시 실패시킨다.
  local dir saved_ifs="$IFS"
  IFS=':'
  for dir in $CLAUDE_SWITCH_BIN_DIRS; do
    case "$dir" in
      "$TMP_ROOT"/*) ;;
      *)
        IFS="$saved_ifs"
        echo "FATAL: 명령 검색 경로가 BATS_TEST_TMPDIR 밖에 있음: $dir" >&2
        return 1
        ;;
    esac
  done
  IFS="$saved_ifs"

  # Keychain 호출 감시. 어떤 테스트에서도 이 로그는 비어 있어야 한다.
  export SECURITY_STUB_LOG="$BATS_TEST_TMPDIR/security-stub.log"
  : >"$SECURITY_STUB_LOG"
  if [ ! -x "$STUBS_DIR/security" ]; then
    echo "FATAL: security 스텁이 실행 가능하지 않음: $STUBS_DIR/security" >&2
    return 1
  fi
  if [ "$(command -v security)" != "$STUBS_DIR/security" ]; then
    echo "FATAL: security 가 스텁으로 해석되지 않음: $(command -v security)" >&2
    return 1
  fi
}

# 이 저장소의 claude-switch 를 설치본처럼 배치한다.
install_owned_command() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$CS" "$dir/claude-switch"
  chmod 755 "$dir/claude-switch"
}

# 이름만 같고 이 도구가 아닌 남의 스크립트.
install_foreign_command() {
  local dir="$1"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "not this tool"\n' >"$dir/claude-switch"
  chmod 755 "$dir/claude-switch"
}

# 남의 스크립트지만 본문에 'claude-switch' 라는 낱말을 포함한다.
# 낱말이 있다는 이유만으로 지워지면 안 된다(설치 서명이 있어야만 소유로 본다).
FOREIGN_MENTION_BODY='#!/bin/bash
# 내가 직접 만든 claude-switch 관련 도우미 스크립트다.
echo "claude-switch profiles: $*"'

install_mentioning_foreign_command() {
  local dir="$1"
  mkdir -p "$dir"
  printf '%s\n' "$FOREIGN_MENTION_BODY" >"$dir/claude-switch"
  chmod 755 "$dir/claude-switch"
}

# claude-switch 를 거치지 않고 저장소 파일을 합성 값으로 직접 만든다.
seed_store_files() {
  mkdir -p "$TOKENS_DIR"
  chmod 700 "$STORE_DIR" "$TOKENS_DIR"
  printf '%s\n' "$TOKEN_A" >"$TOKENS_DIR/personal.token"
  chmod 600 "$TOKENS_DIR/personal.token"
  printf 'default=personal\n' >"$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

# 절대 건드리면 안 되는 전역·v1 경로에 합성 표식을 심는다.
seed_untouchable_files() {
  mkdir -p "$HOME/.claude" "$HOME/.claude-accounts" "$HOME/.claude-homes"
  printf 'SENTINEL-GLOBAL-CONFIG\n' >"$HOME/.claude.json"
  printf 'SENTINEL-GLOBAL-CREDENTIALS\n' >"$HOME/.claude/.credentials.json"
  printf 'SENTINEL-V1-ACCOUNTS\n' >"$HOME/.claude-accounts/personal.json"
  printf 'SENTINEL-V1-HOMES\n' >"$HOME/.claude-homes/personal"
}

assert_untouchable_files_intact() {
  assert_file_content "$HOME/.claude.json" "SENTINEL-GLOBAL-CONFIG"
  assert_file_content "$HOME/.claude/.credentials.json" "SENTINEL-GLOBAL-CREDENTIALS"
  assert_file_content "$HOME/.claude-accounts/personal.json" "SENTINEL-V1-ACCOUNTS"
  assert_file_content "$HOME/.claude-homes/personal" "SENTINEL-V1-HOMES"
}

assert_file_content() {
  local path="$1" expected="$2" actual
  [ -f "$path" ] || flunk "파일 없음: $path"
  actual="$(cat "$path")"
  if [ "$actual" != "$expected" ]; then
    flunk "파일 내용이 바뀜: $path" "예상: $expected" "실제: $actual"
  fi
}

assert_no_keychain_calls() {
  local calls
  calls="$(cat "$SECURITY_STUB_LOG" 2>/dev/null || true)"
  if [ -n "$calls" ]; then
    flunk "security(Keychain) 명령이 호출됨:" "$calls"
  fi
}

# bats 의 run 은 파이프라인을 받지 못하므로 함수로 감싼다.
purge_with_input() {
  printf '%s\n' "$1" | "$UNINSTALL" --purge
}

purge_with_closed_stdin() {
  "$UNINSTALL" --purge </dev/null
}

# 주석을 제외한 실행 코드만 남긴다(정적 금지 패턴 검사용).
uninstall_executable_code() {
  sed -e 's/[[:space:]]*#.*$//' "$UNINSTALL" | grep -v '^[[:space:]]*$' || true
}
