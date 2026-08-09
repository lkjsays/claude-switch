#!/usr/bin/env bats
# 단위 테스트: 인터페이스 계약, 소스 순수성, 입력 검증, 파일 백엔드 계약.

load test_helper

setup() {
  setup_sandbox
}

# ============================================================ help / version

@test "help: lists only v2 commands" {
  run "$CS" --help
  assert_success
  assert_output_contains "claude-switch run <profile>"
  assert_output_contains "claude-switch add <profile>"
  assert_output_contains "claude-switch list"
  assert_output_contains "claude-switch default <profile>"
  assert_output_contains "claude-switch remove <profile>"
  assert_output_contains "claude-switch verify <profile>"
  assert_output_contains "claude-switch doctor"
  assert_output_contains "claude-switch migrate-check"
}

@test "help: does not expose v1-only commands" {
  run "$CS" --help
  assert_success
  refute_output_contains "capture"
  refute_output_contains "add <name> <path>"
}

@test "help: -h and help print the same help text" {
  run "$CS" -h
  assert_success
  assert_output_contains "claude-switch run <profile>"

  run "$CS" help
  assert_success
  assert_output_contains "claude-switch run <profile>"
}

@test "version: prints the version" {
  run "$CS" --version
  assert_success
  assert_output_contains "claude-switch 2."
}

@test "no args: prints usage and exits 2" {
  run "$CS"
  assert_failure 2
  assert_output_contains "claude-switch run <profile>"
}

@test "unknown option: exits 2" {
  run "$CS" --nope
  assert_failure 2
  assert_output_contains "알 수 없는 옵션"
}

# ======================================================= 소스 순수성 (불변 원칙)

@test "purity: source never mentions global Claude credential or config files" {
  run grep -n -e 'credentials\.json' -e '\.claude\.json' "$CS"
  [ "$status" -ne 0 ] || flunk "금지된 전역 파일 경로가 소스에 있음:" "$output"
}

@test "purity: no Keychain (security) manipulation code" {
  run grep -n -E '(^|[^A-Za-z_-])security[[:space:]]+(find|delete|add)-generic-password' "$CS"
  [ "$status" -ne 0 ] || flunk "Keychain 조작 코드가 소스에 있음:" "$output"
}

@test "purity: no private Anthropic API calls" {
  run grep -n -e 'api\.anthropic\.com' -e 'oauth/profile' -e 'urllib' "$CS"
  [ "$status" -ne 0 ] || flunk "비공개 API 호출이 소스에 있음:" "$output"
}

@test "purity: no undocumented internal environment variables" {
  run grep -n -e 'CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR' "$CS"
  [ "$status" -ne 0 ] || flunk "비공식 내부 변수가 소스에 있음:" "$output"
}

@test "purity: v1 directory is referenced only once for existence detection" {
  local count
  count="$(grep -c 'claude-accounts' "$CS" || true)"
  [ "$count" -eq 1 ] || flunk "claude-accounts 참조가 $count 곳 (1 곳이어야 함)"
}

@test "purity: no pattern passing the token as a command line argument" {
  run grep -n -E 'CLAUDE_CODE_OAUTH_TOKEN=.*(claude|CLAUDE_BIN)' "$CS"
  [ "$status" -ne 0 ] || flunk "env 인자 경유 토큰 전달이 소스에 있음:" "$output"
}

@test "purity: does not source the config file" {
  run grep -n -E '^[[:space:]]*(\.|source)[[:space:]]+"?\$(CONFIG_FILE|\{CONFIG_FILE)' "$CS"
  [ "$status" -ne 0 ] || flunk "config 파일을 source 하고 있음:" "$output"
}

# ========================================================== 프로필명 검증

@test "profile name: rejects path traversal attempts" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add '../evil' --stdin"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
  refute_file_exists "$BATS_TEST_TMPDIR/evil.token"
}

@test "profile name: rejects slashes" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add 'a/b' --stdin"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

@test "profile name: rejects spaces" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add 'a b' --stdin"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

@test "profile name: rejects shell metacharacters" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add 'a;rm' --stdin"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

@test "profile name: rejects dot names (. and ..)" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add '.' --stdin"
  assert_failure 2
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add '..' --stdin"
  assert_failure 2
}

@test "profile name: rejects names starting with a hyphen" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add --stdin -- '-evil'"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

@test "profile name: accepts allowed character combinations" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add 'team-enterprise.v2_1' --stdin"
  assert_success
  assert_file_exists "$TOKENS_DIR/team-enterprise.v2_1.token"
}

# ====================================================== file 백엔드 write 계약

@test "backend: store directories are 0700 and token files are 0600" {
  seed_profile personal "$TOKEN_A"
  assert_mode "$STORE_DIR" 700
  assert_mode "$TOKENS_DIR" 700
  assert_mode "$TOKENS_DIR/personal.token" 600
}

@test "backend: config file is 0600" {
  seed_profile personal "$TOKEN_A"
  assert_file_exists "$CONFIG_FILE"
  assert_mode "$CONFIG_FILE" 600
}

@test "backend: token file stores only a single token line" {
  seed_profile personal "$TOKEN_A"
  run cat "$TOKENS_DIR/personal.token"
  assert_success
  [ "$output" = "$TOKEN_A" ] || flunk "저장된 토큰이 입력과 다름"
  run wc -l <"$TOKENS_DIR/personal.token"
  [ "$(echo "$output" | tr -d ' ')" = "1" ] || flunk "토큰 파일이 1줄이 아님: $output"
}

@test "add: output shows only the fingerprint, never the raw token" {
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add personal --stdin"
  assert_success
  refute_token_leak
  assert_output_contains "$(fingerprint_of "$TOKEN_A")"
}

@test "add: does not overwrite an existing profile" {
  seed_profile personal "$TOKEN_A"
  run bash -c "printf '%s\n' '$TOKEN_B' | '$CS' add personal --stdin"
  assert_failure 1
  assert_output_contains "이미 있습니다"
  refute_token_leak
  run cat "$TOKENS_DIR/personal.token"
  [ "$output" = "$TOKEN_A" ] || flunk "기존 토큰이 변경됨"
}

@test "add --force: overwrites an existing profile" {
  seed_profile personal "$TOKEN_A"
  run bash -c "printf '%s\n' '$TOKEN_B' | '$CS' add personal --stdin --force"
  assert_success
  refute_token_leak
  run cat "$TOKENS_DIR/personal.token"
  [ "$output" = "$TOKEN_B" ] || flunk "토큰이 덮어써지지 않음"
}

@test "add: rejects an empty token" {
  run bash -c "printf '\n' | '$CS' add personal --stdin"
  assert_failure 1
  assert_output_contains "빈 토큰"
  refute_file_exists "$TOKENS_DIR/personal.token"
}

@test "add: rejects a token containing whitespace" {
  run bash -c "printf '%s\n' 'sk-ant-oat01-TESTTOKEN AAA' | '$CS' add personal --stdin"
  assert_failure 1
  assert_output_contains "허용되지 않는 문자"
  refute_file_exists "$TOKENS_DIR/personal.token"
}

@test "add: strips CR from a pasted token before storing" {
  run bash -c "printf '%s\r\n' '$TOKEN_A' | '$CS' add personal --stdin"
  assert_success
  run cat "$TOKENS_DIR/personal.token"
  [ "$output" = "$TOKEN_A" ] || flunk "CR 이 제거되지 않음"
}

@test "add: rejects when the token file path is a symlink" {
  mkdir -p "$TOKENS_DIR"
  chmod 700 "$STORE_DIR" "$TOKENS_DIR"
  ln -s "$BATS_TEST_TMPDIR/elsewhere.token" "$TOKENS_DIR/personal.token"
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add personal --stdin --force"
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  refute_file_exists "$BATS_TEST_TMPDIR/elsewhere.token"
}

@test "add: rejects when the store directory is a symlink" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere-store"
  ln -s "$BATS_TEST_TMPDIR/elsewhere-store" "$STORE_DIR"
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add personal --stdin"
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  refute_file_exists "$BATS_TEST_TMPDIR/elsewhere-store/tokens/personal.token"
}

@test "add: rejects a token given as a positional argument" {
  run "$CS" add personal "$TOKEN_A"
  assert_failure 2
  assert_output_contains "명령행 인자로 받지 않습니다"
  refute_file_exists "$TOKENS_DIR/personal.token"
}

@test "add: rejects when not a TTY and --stdin is missing" {
  run bash -c "'$CS' add personal </dev/null"
  assert_failure 2
  assert_output_contains "--stdin"
  refute_file_exists "$TOKENS_DIR/personal.token"
}

@test "store: token files are not tracked by Git" {
  run bash -c "cd '$REPO_ROOT' && git ls-files | grep -E '\.token$|^tokens/' || true"
  [ -z "$output" ] || flunk "Git 에 토큰 파일이 추적되고 있음: $output"
}
