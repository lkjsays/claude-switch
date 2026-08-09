#!/usr/bin/env bats
# uninstall.sh 테스트: 설치본 제거는 하되 저장소·전역 인증은 건드리지 않는다.
#
# 모든 테스트는 임시 HOME 과 임시 명령 검색 경로에서만 동작한다.
# 실제 ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, Keychain 은 검색조차 하지 않는다.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_uninstall_sandbox
}

# ==================================================================== 도움말

@test "help: --help prints v2 usage and exits 0" {
  run "$UNINSTALL" --help
  assert_success
  assert_output_contains "./uninstall.sh"
  assert_output_contains "--purge"
  assert_output_contains "--yes"
}

@test "help: -h prints the same help text" {
  run "$UNINSTALL" -h
  assert_success
  assert_output_contains "--purge"
}

@test "help: does not advertise v1 options" {
  run "$UNINSTALL" --help
  assert_success
  refute_output_contains "--keep-accounts"
}

@test "options: unknown option exits 2" {
  run "$UNINSTALL" --nope
  assert_failure 2
  assert_output_contains "알 수 없는 옵션"
}

@test "options: v1 --keep-accounts is rejected with exit 2" {
  seed_store_files
  run "$UNINSTALL" --keep-accounts
  assert_failure 2
  assert_output_contains "알 수 없는 옵션"
  assert_file_exists "$TOKENS_DIR/personal.token"
}

@test "options: --yes without --purge preserves the store" {
  seed_store_files
  run "$UNINSTALL" --yes
  assert_success
  assert_file_exists "$TOKENS_DIR/personal.token"
  assert_output_contains "보존됨"
}

# ============================================================== 기본 제거 동작

@test "default: removes an installed claude-switch command" {
  install_owned_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  assert_output_contains "제거됨: $FAKE_BIN_A/claude-switch"
  refute_file_exists "$FAKE_BIN_A/claude-switch"
}

@test "default: removes installed commands from every search directory" {
  install_owned_command "$FAKE_BIN_A"
  install_owned_command "$FAKE_BIN_B"
  run "$UNINSTALL"
  assert_success
  refute_file_exists "$FAKE_BIN_A/claude-switch"
  refute_file_exists "$FAKE_BIN_B/claude-switch"
}

@test "default: preserves profiles and tokens in the store" {
  seed_profile personal "$TOKEN_A"
  install_owned_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  assert_file_exists "$TOKENS_DIR/personal.token"
  assert_file_exists "$CONFIG_FILE"
  assert_output_contains "보존됨: $STORE_DIR"
  assert_output_contains "--purge"
  refute_token_leak
}

@test "default: reports already absent when nothing is installed" {
  run "$UNINSTALL"
  assert_success
  assert_output_contains "이미 없음"
}

@test "default: repeated runs stay idempotent" {
  install_owned_command "$FAKE_BIN_A"
  seed_store_files
  run "$UNINSTALL"
  assert_success
  run "$UNINSTALL"
  assert_success
  assert_output_contains "이미 없음"
  assert_file_exists "$TOKENS_DIR/personal.token"
}

@test "default: leaves a foreign command with the same name untouched" {
  install_foreign_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  assert_output_contains "건너뜀"
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_content "$FAKE_BIN_A/claude-switch" "$(printf '#!/bin/sh\necho "not this tool"')"
}

@test "default: does not follow a symlinked command path" {
  local target="$BATS_TEST_TMPDIR/real-command"
  cp "$CS" "$target"
  ln -s "$target" "$FAKE_BIN_A/claude-switch"
  run "$UNINSTALL"
  assert_success
  assert_output_contains "건너뜀"
  assert_file_exists "$target"
}

@test "default: skips a missing search directory without failing" {
  export CLAUDE_SWITCH_BIN_DIRS="$TMP_ROOT/nowhere:$FAKE_BIN_A"
  install_owned_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  refute_file_exists "$FAKE_BIN_A/claude-switch"
}

# =========================================== 소유권 판별 (설치 서명 정확 일치)

@test "ownership: keeps a foreign script that merely mentions claude-switch" {
  install_mentioning_foreign_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  assert_output_contains "건너뜀"
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_content "$FAKE_BIN_A/claude-switch" "$FOREIGN_MENTION_BODY"
}

# 소유권 판별은 install.sh 가 실제로 배치한 파일에도 성립해야 한다. 복사본을 흉내내는
# 것만으로는 부족하다. 설치 경로가 바뀌어 서명이 어긋나면 진짜 설치본이 제거되지 않는다.
@test "ownership: removes a command placed by install.sh" {
  run env BIN_DIR="$FAKE_BIN_A" FORCE=1 "$REPO_ROOT/install.sh"
  assert_success
  assert_file_exists "$FAKE_BIN_A/claude-switch"

  run "$UNINSTALL"
  assert_success
  assert_output_contains "제거됨: $FAKE_BIN_A/claude-switch"
  refute_file_exists "$FAKE_BIN_A/claude-switch"
}

@test "ownership: keeps a foreign script that embeds the signature mid-line" {
  mkdir -p "$FAKE_BIN_A"
  printf '#!/bin/bash\necho "claude-switch-install-signature/v2/6f1a9c0b4d7e is a string"\n' \
    >"$FAKE_BIN_A/claude-switch"
  chmod 755 "$FAKE_BIN_A/claude-switch"
  run "$UNINSTALL"
  assert_success
  assert_output_contains "건너뜀"
  assert_file_exists "$FAKE_BIN_A/claude-switch"
}

# ================================ 검색 경로 심볼릭 링크·비정상 경로 거부
#
# 안전하지 않은 검색 경로를 건너뛰고 exit 0 으로 끝내면, 설치본이 그대로 남아 있는데도
# 제거에 성공한 것처럼 보인다. 그래서 모든 검색 경로를 손대기 전에 먼저 검사하고,
# 하나라도 안전하지 않으면 아무것도 지우지 않은 채 exit 1 로 중단한다.

@test "symlink: fails without mutating when a search directory is a symlink" {
  local real="$TMP_ROOT/real-bin"
  local link="$TMP_ROOT/link-bin"
  install_owned_command "$real"
  ln -s "$real" "$link"
  export CLAUDE_SWITCH_BIN_DIRS="$link"

  run "$UNINSTALL"
  assert_failure 1
  assert_file_exists "$real/claude-switch"
  [ -L "$link" ] || flunk "symlink disappeared: $link"
}

@test "symlink: fails without mutating when a search directory parent is a symlink" {
  local real_parent="$TMP_ROOT/real-parent"
  local link_parent="$TMP_ROOT/link-parent"
  install_owned_command "$real_parent/bin"
  ln -s "$real_parent" "$link_parent"
  export CLAUDE_SWITCH_BIN_DIRS="$link_parent/bin"

  run "$UNINSTALL"
  assert_failure 1
  assert_file_exists "$real_parent/bin/claude-switch"
}

@test "paths: fails on a relative search directory without traversing it" {
  install_owned_command "$FAKE_BIN_A"
  export CLAUDE_SWITCH_BIN_DIRS="bin-a"

  run bash -c "cd '$TMP_ROOT' && '$UNINSTALL'"
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
}

@test "paths: fails on a search directory containing dot dot" {
  install_owned_command "$FAKE_BIN_A"
  export CLAUDE_SWITCH_BIN_DIRS="$TMP_ROOT/bin-b/../bin-a"

  run "$UNINSTALL"
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
}

# 순서 의존성이 핵심이다. 앞선 안전한 경로를 먼저 지우고 뒤에서 실패하면 부분 제거가
# 된다. 검사가 모든 경로보다 앞서므로 앞선 경로의 설치본도 남아 있어야 한다.

@test "atomic: a later symlinked search directory blocks removal in an earlier one" {
  local real="$TMP_ROOT/real-bin"
  local link="$TMP_ROOT/link-bin"
  install_owned_command "$FAKE_BIN_A"
  install_owned_command "$real"
  ln -s "$real" "$link"
  export CLAUDE_SWITCH_BIN_DIRS="$FAKE_BIN_A:$link"

  run "$UNINSTALL"
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_exists "$real/claude-switch"
}

@test "atomic: a later relative search directory blocks removal in an earlier one" {
  install_owned_command "$FAKE_BIN_A"
  export CLAUDE_SWITCH_BIN_DIRS="$FAKE_BIN_A:bin-b"

  run bash -c "cd '$TMP_ROOT' && '$UNINSTALL'"
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
}

@test "atomic: a later dot dot search directory blocks removal in an earlier one" {
  install_owned_command "$FAKE_BIN_A"
  export CLAUDE_SWITCH_BIN_DIRS="$FAKE_BIN_A:$TMP_ROOT/bin-b/../bin-a"

  run "$UNINSTALL"
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
}

@test "atomic: an unsafe search directory aborts before purging the store" {
  seed_store_files
  install_owned_command "$FAKE_BIN_A"
  export CLAUDE_SWITCH_BIN_DIRS="$FAKE_BIN_A:$TMP_ROOT/bin-b/../bin-a"

  run "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_exists "$TOKENS_DIR/personal.token"
}

# ==================================================================== --purge

@test "purge: deletes the store after an interactive yes" {
  seed_store_files
  run purge_with_input y
  assert_success
  assert_output_contains "삭제됨: $STORE_DIR"
  refute_file_exists "$STORE_DIR"
  refute_token_leak
}

@test "purge: preserves the store when the confirmation is declined" {
  seed_store_files
  run purge_with_input n
  assert_success
  assert_output_contains "보존됨: $STORE_DIR"
  assert_file_exists "$TOKENS_DIR/personal.token"
}

@test "purge: treats an empty answer as a decline" {
  seed_store_files
  run purge_with_input ""
  assert_success
  assert_file_exists "$TOKENS_DIR/personal.token"
}

@test "purge: preserves the store when stdin gives no answer" {
  seed_store_files
  run purge_with_closed_stdin
  assert_success
  assert_file_exists "$TOKENS_DIR/personal.token"
  assert_output_contains "보존됨: $STORE_DIR"
}

@test "purge: --yes deletes the store noninteractively" {
  seed_store_files
  run "$UNINSTALL" --purge --yes
  assert_success
  assert_output_contains "삭제됨: $STORE_DIR"
  refute_file_exists "$STORE_DIR"
}

@test "purge: also removes installed commands" {
  install_owned_command "$FAKE_BIN_A"
  seed_store_files
  run "$UNINSTALL" --purge --yes
  assert_success
  refute_file_exists "$FAKE_BIN_A/claude-switch"
  refute_file_exists "$STORE_DIR"
}

@test "purge: succeeds when the store is already absent" {
  run "$UNINSTALL" --purge --yes
  assert_success
  assert_output_contains "이미 없음: $STORE_DIR"
}

@test "purge: refuses a symlinked store and leaves the target intact" {
  local target="$BATS_TEST_TMPDIR/real-store"
  mkdir -p "$target"
  printf 'SENTINEL-STORE\n' >"$target/sentinel"
  ln -s "$target" "$STORE_DIR"

  run "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  assert_file_content "$target/sentinel" "SENTINEL-STORE"
  [ -L "$STORE_DIR" ] || flunk "심볼릭 링크가 사라짐: $STORE_DIR"
}

@test "purge: refuses a store path that is not a directory" {
  printf 'not a directory\n' >"$STORE_DIR"
  run "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_file_exists "$STORE_DIR"
}

@test "purge: a symlinked store aborts before removing installed commands" {
  local target="$BATS_TEST_TMPDIR/real-store"
  mkdir -p "$target"
  printf 'SENTINEL-STORE\n' >"$target/sentinel"
  ln -s "$target" "$STORE_DIR"
  install_owned_command "$FAKE_BIN_A"

  run "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_content "$target/sentinel" "SENTINEL-STORE"
}

@test "purge: a non-directory store aborts before removing installed commands" {
  printf 'not a directory\n' >"$STORE_DIR"
  install_owned_command "$FAKE_BIN_A"

  run "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_file_exists "$FAKE_BIN_A/claude-switch"
  assert_file_content "$STORE_DIR" "not a directory"
}

@test "purge: refuses to run when HOME is empty" {
  seed_store_files
  run env HOME= "$UNINSTALL" --purge --yes
  assert_failure 1
  assert_output_contains "HOME"
}

# ============================================== 절대 건드리지 않는 것 (행위 검증)

@test "safety: default run never touches global or v1 paths" {
  seed_untouchable_files
  seed_store_files
  install_owned_command "$FAKE_BIN_A"
  run "$UNINSTALL"
  assert_success
  assert_untouchable_files_intact
  assert_no_keychain_calls
}

@test "safety: purge never touches global or v1 paths" {
  seed_untouchable_files
  seed_store_files
  run "$UNINSTALL" --purge --yes
  assert_success
  refute_file_exists "$STORE_DIR"
  assert_untouchable_files_intact
  assert_no_keychain_calls
}

@test "safety: help never calls the macOS security command" {
  run "$UNINSTALL" --help
  assert_success
  assert_no_keychain_calls
}

# ========================================== 금지 패턴 정적 검사 (회귀 방지)

@test "purity: uninstall code contains no Keychain access" {
  local code hits
  code="$(uninstall_executable_code)"
  hits="$(printf '%s\n' "$code" | grep -n -E '(^|[^A-Za-z_.-])security([[:space:]]|$)|generic-password|Keychain' || true)"
  [ -z "$hits" ] || flunk "Keychain 조작 코드가 uninstall.sh 에 있음:" "$hits"
}

@test "purity: uninstall code contains no global credential or config paths" {
  local code hits
  code="$(uninstall_executable_code)"
  hits="$(printf '%s\n' "$code" | grep -n -E 'credentials\.json|\.claude\.json|\.claude/' || true)"
  [ -z "$hits" ] || flunk "금지된 전역 파일 경로가 uninstall.sh 에 있음:" "$hits"
}

@test "purity: uninstall code contains no v1 store manipulation" {
  local code hits
  code="$(uninstall_executable_code)"
  hits="$(printf '%s\n' "$code" | grep -n -E 'claude-accounts|claude-homes' || true)"
  [ -z "$hits" ] || flunk "v1 저장소 조작 코드가 uninstall.sh 에 있음:" "$hits"
}
