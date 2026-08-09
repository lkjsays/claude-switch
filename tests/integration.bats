#!/usr/bin/env bats
# 통합 테스트: 명령 단위 동작. 임시 HOME 과 가짜 claude 스텁만 사용한다.

# `run -<code>` 로 예상 종료코드를 명시하기 위해 필요하다(bats 1.5.0+).
bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_sandbox
}

# ==================================================================== list

@test "list: prints guidance when there are no profiles" {
  run "$CS" list
  assert_success
  assert_output_contains "프로필 없음"
  assert_output_contains "claude-switch add"
}

@test "list: shows profiles and fingerprints without exposing tokens" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  run "$CS" list
  assert_success
  assert_output_contains "personal"
  assert_output_contains "office"
  assert_output_contains "$(fingerprint_of "$TOKEN_A")"
  assert_output_contains "$(fingerprint_of "$TOKEN_B")"
  refute_token_leak
}

@test "list: marks the default profile" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  run "$CS" list
  assert_success
  assert_output_contains "● personal"
  assert_output_contains "(default)"
}

@test "list: -l and --list produce the same result" {
  seed_profile personal "$TOKEN_A"
  run "$CS" -l
  assert_success
  assert_output_contains "personal"
  run "$CS" --list
  assert_success
  assert_output_contains "personal"
}

@test "list: refuses a symlinked token directory without reading profiles" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR" "$BATS_TEST_TMPDIR/real-tokens"
  ln -s "$BATS_TEST_TMPDIR/real-tokens" "$TOKENS_DIR"
  run "$CS" list
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  refute_output_contains "personal"
  refute_token_leak
}

# ================================================================= default

@test "default: the first add becomes the default profile" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  run "$CS" default
  assert_success
  assert_output_contains "personal"
}

@test "default: changes the default profile" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  run "$CS" default office
  assert_success
  assert_output_contains "office"
  run "$CS" default
  assert_success
  assert_output_contains "office"
}

@test "default: rejects a missing profile" {
  seed_profile personal "$TOKEN_A"
  run "$CS" default ghost
  assert_failure 1
  assert_output_contains "없음"
  run "$CS" default
  assert_output_contains "personal"
}

@test "default: prints guidance when no default profile is set" {
  run "$CS" default
  assert_success
  assert_output_contains "기본 프로필 없음"
}

@test "default: invalid name exits 2" {
  run "$CS" default "a b"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

# ================================================================== remove

@test "remove: deletes the profile token file" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  run "$CS" remove office
  assert_success
  assert_output_contains "삭제됨"
  refute_file_exists "$TOKENS_DIR/office.token"
  assert_file_exists "$TOKENS_DIR/personal.token"
}

@test "remove: missing profile exits 1" {
  run "$CS" remove ghost
  assert_failure 1
  assert_output_contains "없음"
}

@test "remove: clears and reports the default when the default profile is removed" {
  seed_profile personal "$TOKEN_A"
  run "$CS" remove personal
  assert_success
  assert_output_contains "기본 프로필"
  run "$CS" default
  assert_success
  assert_output_contains "기본 프로필 없음"
}

@test "remove: the rm alias also works" {
  seed_profile personal "$TOKEN_A"
  run "$CS" rm personal
  assert_success
  refute_file_exists "$TOKENS_DIR/personal.token"
}

@test "remove: reports the leftover isolated directory path" {
  seed_profile personal "$TOKEN_A"
  mkdir -p "$STORE_DIR/isolated/personal"
  run "$CS" remove personal
  assert_success
  assert_output_contains "isolated/personal"
  [ -d "$STORE_DIR/isolated/personal" ] || flunk "격리 디렉터리를 임의로 삭제했음"
}

@test "remove: invalid name exits 2" {
  run "$CS" remove "../evil"
  assert_failure 2
  assert_output_contains "잘못된 프로필 이름"
}

@test "remove: refuses a symlinked token directory and preserves the target" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR" "$BATS_TEST_TMPDIR/real-tokens"
  ln -s "$BATS_TEST_TMPDIR/real-tokens" "$TOKENS_DIR"
  run "$CS" remove personal
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  assert_file_exists "$BATS_TEST_TMPDIR/real-tokens/personal.token"
}

# ===================================================================== run

@test "run: injects the token as CLAUDE_CODE_OAUTH_TOKEN in the child process" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- -p hello
  assert_success
  run stub_log
  assert_output_contains "TOKEN_PRESENT=1"
  assert_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_A")"
}

@test "run: injects a different token per profile" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  "$CS" run office -- -p hi >/dev/null 2>&1
  run stub_log
  assert_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_B")"
  refute_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_A")"
}

@test "run: passes args after -- verbatim including spaces and empty strings" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- -p "" "a b" --model sonnet
  assert_success
  run stub_log
  assert_output_contains "ARG[-p]"
  assert_output_contains "ARG[]"
  assert_output_contains "ARG[a b]"
  assert_output_contains "ARG[--model]"
  assert_output_contains "ARG[sonnet]"
  assert_output_contains "ARGC=5"
}

@test "run: passes remaining args verbatim even without --" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -p hello
  assert_success
  run stub_log
  assert_output_contains "ARG[-p]"
  assert_output_contains "ARG[hello]"
  assert_output_contains "ARGC=2"
}

@test "run: propagates the child exit code" {
  seed_profile personal "$TOKEN_A"
  CLAUDE_STUB_EXIT=42 run "$CS" run personal -- -p hi
  assert_failure 42
}

@test "run: forwards the stdin pipe to the child" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_READ_STDIN=1
  run bash -c "printf 'piped-input\n' | '$CS' run personal -- -p"
  assert_success
  run stub_log
  assert_output_contains "STDIN=piped-input"
}

@test "run: announces the profile name on stderr only and keeps stdout clean" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_STDOUT="claude-output"
  run bash -c "'$CS' run personal -- -p hi 2>/dev/null"
  assert_success
  [ "$output" = "claude-output" ] || flunk "stdout 이 오염됨: $output"

  run bash -c "'$CS' run personal -- -p hi 2>&1 >/dev/null"
  assert_success
  assert_output_contains "personal"
}

@test "run: never exposes the raw token on stdout/stderr or in child argv" {
  seed_profile personal "$TOKEN_A"
  run bash -c "'$CS' run personal -- -p hi 2>&1"
  assert_success
  refute_token_leak
  run stub_log
  refute_token_leak
}

@test "run: missing profile exits 1" {
  run "$CS" run ghost -- -p hi
  assert_failure 1
  assert_output_contains "없음"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨: $output"
}

@test "run: --bare is blocked with exit 2 and claude is not executed" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- --bare -p hi
  assert_failure 2
  assert_output_contains "--bare"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨: $output"
}

@test "run: --bare is blocked in the shorthand form too" {
  seed_profile personal "$TOKEN_A"
  run "$CS" personal -- --bare
  assert_failure 2
  assert_output_contains "--bare"
}

@test "shorthand: claude-switch <profile> runs the profile" {
  seed_profile personal "$TOKEN_A"
  run "$CS" personal -- -p hi
  assert_success
  run stub_log
  assert_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_A")"
  assert_output_contains "ARG[-p]"
}

@test "shorthand: missing profile exits 1 with guidance" {
  run "$CS" ghost
  assert_failure 1
  assert_output_contains "없음"
  assert_output_contains "claude-switch list"
}

@test "shorthand: a profile named like a subcommand is reachable via run" {
  seed_profile list "$TOKEN_A"
  run "$CS" list
  assert_success
  assert_output_contains "fp:"

  run "$CS" run list -- -p hi
  assert_success
  run stub_log
  assert_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_A")"
}

@test "run: uses the default profile when the profile is omitted" {
  seed_profile personal "$TOKEN_A"
  seed_profile office "$TOKEN_B"
  "$CS" default office >/dev/null
  run "$CS" run -- -p hi
  assert_success
  run stub_log
  assert_output_contains "TOKEN_SHA256=$(sha256_of "$TOKEN_B")"
}

@test "run: exits 2 when neither profile nor default exists" {
  run "$CS" run
  assert_failure 2
  assert_output_contains "기본 프로필"
}

@test "run: by default CLAUDE_CONFIG_DIR is left untouched (shared)" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- -p hi
  assert_success
  run stub_log
  assert_output_contains "CONFIG_DIR="
  refute_output_contains "CONFIG_DIR=$HOME/.claude-switch/isolated"
}

@test "run --isolate: creates a profile-specific CLAUDE_CONFIG_DIR with 0700 and passes it" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run --isolate personal -- -p hi
  assert_success
  run stub_log
  assert_output_contains "CONFIG_DIR=$STORE_DIR/isolated/personal"
  assert_mode "$STORE_DIR/isolated/personal" 700
}

@test "run --isolate: also works in the shorthand form" {
  seed_profile personal "$TOKEN_A"
  run "$CS" --isolate personal -- -p hi
  assert_success
  run stub_log
  assert_output_contains "CONFIG_DIR=$STORE_DIR/isolated/personal"
}

@test "run: refuses to run when token file permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 644 "$TOKENS_DIR/personal.token"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "권한"
  assert_output_contains "chmod 600"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "run: refuses to run when store directory permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 755 "$STORE_DIR"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "저장소"
  assert_output_contains "700"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "run: refuses to run when token directory permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 755 "$TOKENS_DIR"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "토큰 디렉터리"
  assert_output_contains "700"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "run: refuses to follow a symlinked token directory" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR" "$BATS_TEST_TMPDIR/real-tokens"
  ln -s "$BATS_TEST_TMPDIR/real-tokens" "$TOKENS_DIR"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "run: refuses to run when the token is a symlink" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR/personal.token" "$BATS_TEST_TMPDIR/real.token"
  ln -s "$BATS_TEST_TMPDIR/real.token" "$TOKENS_DIR/personal.token"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "run: refuses to run when the token file is empty" {
  seed_profile personal "$TOKEN_A"
  : >"$TOKENS_DIR/personal.token"
  chmod 600 "$TOKENS_DIR/personal.token"
  run "$CS" run personal -- -p hi
  assert_failure 1
  assert_output_contains "빈 토큰"
}

@test "run: warns and removes higher-precedence environment credentials from the child" {
  seed_profile personal "$TOKEN_A"
  export ANTHROPIC_API_KEY="«redacted:sk-…»"
  export ANTHROPIC_AUTH_TOKEN="synthetic-auth-token"
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_VERTEX=1
  export CLAUDE_CODE_USE_FOUNDRY=1
  export ANTHROPIC_BASE_URL="https://gateway.invalid"
  run "$CS" run personal -- -p hi
  assert_success
  assert_output_contains "ANTHROPIC_API_KEY"
  assert_output_contains "ANTHROPIC_AUTH_TOKEN"
  assert_output_contains "CLAUDE_CODE_USE_BEDROCK"
  assert_output_contains "CLAUDE_CODE_USE_VERTEX"
  assert_output_contains "CLAUDE_CODE_USE_FOUNDRY"
  assert_output_contains "ANTHROPIC_BASE_URL"
  run stub_log
  assert_output_contains "ANTHROPIC_API_KEY_PRESENT=0"
  assert_output_contains "ANTHROPIC_AUTH_TOKEN_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_BEDROCK_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_VERTEX_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_FOUNDRY_PRESENT=0"
  assert_output_contains "ANTHROPIC_BASE_URL_PRESENT=0"
}

@test "run: exits 127 with guidance when claude is not found" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_SWITCH_CLAUDE_BIN="$BATS_TEST_TMPDIR/no-such-claude"
  run -127 "$CS" run personal -- -p hi
  assert_failure 127
  assert_output_contains "claude"
}

# ================================================================== verify

@test "verify: shows local state and account information" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_AUTH_OUTPUT="Account: office@example.com
Organization: ACME Enterprise"
  run "$CS" verify personal
  assert_success
  assert_output_contains "personal"
  assert_output_contains "fp:$(fingerprint_of "$TOKEN_A")"
  assert_output_contains "office@example.com"
  assert_output_contains "ACME Enterprise"
  refute_token_leak
}

@test "verify: calls auth status with --text" {
  seed_profile personal "$TOKEN_A"
  "$CS" verify personal >/dev/null 2>&1
  run stub_log
  assert_output_contains "ARG[auth]"
  assert_output_contains "ARG[status]"
  assert_output_contains "ARG[--text]"
  refute_token_leak
}

@test "verify: removes higher-precedence environment credentials for auth status" {
  seed_profile personal "$TOKEN_A"
  export ANTHROPIC_API_KEY="«redacted:sk-…»"
  export ANTHROPIC_AUTH_TOKEN="synthetic-auth-token"
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_VERTEX=1
  export CLAUDE_CODE_USE_FOUNDRY=1
  export ANTHROPIC_BASE_URL="https://gateway.invalid"
  run "$CS" verify personal
  assert_success
  run stub_log
  assert_output_contains "ANTHROPIC_API_KEY_PRESENT=0"
  assert_output_contains "ANTHROPIC_AUTH_TOKEN_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_BEDROCK_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_VERTEX_PRESENT=0"
  assert_output_contains "CLAUDE_CODE_USE_FOUNDRY_PRESENT=0"
  assert_output_contains "ANTHROPIC_BASE_URL_PRESENT=0"
}

@test "verify: fails when auth status passes but a live model request is rejected" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_INFERENCE_EXIT=1
  export CLAUDE_STUB_STDERR="API Error: 401 OAuth access token is invalid"
  run "$CS" verify personal
  assert_failure 1
  assert_output_contains "실제 모델 호출 실패"
  assert_output_contains "401"
  refute_token_leak
}

@test "verify: missing profile exits 1" {
  run "$CS" verify ghost
  assert_failure 1
  assert_output_contains "없음"
}

@test "verify: loose permissions exit 1" {
  seed_profile personal "$TOKEN_A"
  chmod 604 "$TOKENS_DIR/personal.token"
  run "$CS" verify personal
  assert_failure 1
  assert_output_contains "권한"
}

@test "verify: a symlink exits 1" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR/personal.token" "$BATS_TEST_TMPDIR/real.token"
  ln -s "$BATS_TEST_TMPDIR/real.token" "$TOKENS_DIR/personal.token"
  run "$CS" verify personal
  assert_failure 1
  assert_output_contains "심볼릭 링크"
}

@test "verify: reports authentication failure with exit 1" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_AUTH_EXIT=1
  run "$CS" verify personal
  assert_failure 1
  assert_output_contains "인증 확인 실패"
  refute_token_leak
}

@test "verify: runs local checks only and warns when claude is missing" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_SWITCH_CLAUDE_BIN="$BATS_TEST_TMPDIR/no-such-claude"
  run "$CS" verify personal
  assert_success
  assert_output_contains "fp:$(fingerprint_of "$TOKEN_A")"
  assert_output_contains "건너뜀"
}

@test "verify: masks the token if it appears in child output" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_STUB_AUTH_OUTPUT="token echo: $TOKEN_A"
  run "$CS" verify personal
  assert_success
  refute_token_leak
  assert_output_contains "[redacted]"
}

@test "verify: checks the default profile when the profile is omitted" {
  seed_profile personal "$TOKEN_A"
  run "$CS" verify
  assert_success
  assert_output_contains "personal"
}

# ============================================================== v1 잔재 가드
#
# v1 디렉터리는 존재만 감지하고 내용을 읽거나 지우지 않는다.

seed_v1_residue() {
  mkdir -p "$V1_DIR"
  printf '{"claudeAiOauth":{"accessToken":"v1-DO-NOT-TOUCH"}}\n' \
    >"$V1_DIR/personal.json"
  printf 'personal\n' >"$V1_DIR/.current"
  V1_SNAPSHOT="$BATS_TEST_TMPDIR/v1-snapshot"
  v1_state >"$V1_SNAPSHOT"
}

# v1 디렉터리와 그 안의 항목만 본다(이름·권한·mtime·크기·내용 해시).
v1_state() {
  stat -f '%N mode=%Lp mtime=%m size=%z' \
    "$V1_DIR" "$V1_DIR"/* "$V1_DIR"/.current 2>&1
  shasum -a 256 "$V1_DIR"/* "$V1_DIR"/.current 2>&1
}

assert_v1_untouched() {
  local now="$BATS_TEST_TMPDIR/v1-now"
  v1_state >"$now"
  diff "$V1_SNAPSHOT" "$now" >/dev/null ||
    flunk "v1 디렉터리가 변경됨:" "$(diff "$V1_SNAPSHOT" "$now")"
}

@test "v1 guard: blocks run when leftovers exist and are unacknowledged" {
  seed_profile personal "$TOKEN_A"
  seed_v1_residue
  run "$CS" run personal -- -p hi
  assert_failure 2
  assert_output_contains "migrate-check"
  assert_v1_untouched
  run stub_log
  [ -z "$output" ] || flunk "claude 가 실행되어선 안 됨"
}

@test "v1 guard: blocks add/list/default/remove/verify when leftovers are unacknowledged" {
  seed_v1_residue
  local c
  for c in "list" "default" "verify" "remove personal"; do
    run bash -c "'$CS' $c"
    assert_failure 2
    assert_output_contains "migrate-check"
  done
  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add personal --stdin"
  assert_failure 2
  assert_output_contains "migrate-check"
  assert_v1_untouched
}

@test "v1 guard: doctor, migrate-check and help are not blocked" {
  seed_v1_residue
  run "$CS" --help
  assert_success
  run "$CS" --version
  assert_success
  run "$CS" migrate-check
  assert_failure 2
  assert_output_contains "v1"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "v1"
  assert_v1_untouched
}

@test "v1 guard: all commands open up after acknowledgement" {
  seed_v1_residue
  run "$CS" migrate-check --acknowledge
  assert_success
  assert_output_contains "승인"
  assert_mode "$ACK_FILE" 600

  run bash -c "printf '%s\n' '$TOKEN_A' | '$CS' add personal --stdin"
  assert_success
  run "$CS" list
  assert_success
  assert_output_contains "personal"
  run "$CS" run personal -- -p hi
  assert_success
  assert_v1_untouched
}

@test "v1 guard: does not read leftover contents (works with an unreadable directory)" {
  seed_v1_residue
  "$CS" migrate-check --acknowledge >/dev/null
  local orig_mode
  orig_mode="$(stat -f '%Lp' "$V1_DIR")"
  chmod 000 "$V1_DIR"
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- -p hi
  local rc="$status" out="$output"
  chmod "$orig_mode" "$V1_DIR"
  [ "$rc" -eq 0 ] || flunk "잔재 내용을 읽으려 해서 실패함: $out"
  assert_v1_untouched
}

@test "v1 guard: blocks nothing when there are no leftovers" {
  seed_profile personal "$TOKEN_A"
  run "$CS" run personal -- -p hi
  assert_success
  run "$CS" migrate-check
  assert_success
  assert_output_contains "없습니다"
}

@test "v1 compat: the capture subcommand only prints guidance with exit 2" {
  seed_v1_residue
  run "$CS" capture personal
  assert_failure 2
  assert_output_contains "v1"
  assert_output_contains "claude setup-token"
  assert_v1_untouched
}

@test "migrate-check: unknown option exits 2" {
  run "$CS" migrate-check --nope
  assert_failure 2
  assert_output_contains "알 수 없는 옵션"
}

@test "migrate-check: states explicitly that it performs no automatic conversion" {
  seed_v1_residue
  run "$CS" migrate-check
  assert_failure 2
  assert_output_contains "자동"
  assert_output_contains "claude setup-token"
  refute_file_exists "$TOKENS_DIR/personal.token"
  assert_v1_untouched
}

# ================================================================== doctor

@test "doctor: exits 0 on a healthy setup" {
  seed_profile personal "$TOKEN_A"
  run "$CS" doctor
  assert_success
  assert_output_contains "personal"
  assert_output_contains "fp:$(fingerprint_of "$TOKEN_A")"
  assert_output_contains "doctor OK"
  refute_token_leak
}

@test "doctor: exits 0 with guidance even when there are no profiles" {
  run "$CS" doctor
  assert_success
  assert_output_contains "프로필 없음"
}

@test "doctor: exits 1 with a remedy when token permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 644 "$TOKENS_DIR/personal.token"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "chmod 600"
}

@test "doctor: exits 1 when the token is a symlink" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR/personal.token" "$BATS_TEST_TMPDIR/real.token"
  ln -s "$BATS_TEST_TMPDIR/real.token" "$TOKENS_DIR/personal.token"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "심볼릭 링크"
}

@test "doctor: refuses a symlinked token directory without reading profiles" {
  seed_profile personal "$TOKEN_A"
  mv "$TOKENS_DIR" "$BATS_TEST_TMPDIR/real-tokens"
  ln -s "$BATS_TEST_TMPDIR/real-tokens" "$TOKENS_DIR"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "토큰 디렉터리"
  assert_output_contains "심볼릭 링크"
  refute_output_contains "fp:$(fingerprint_of "$TOKEN_A")"
  refute_token_leak
}

@test "doctor: refuses a symlinked store without reading profiles" {
  seed_profile personal "$TOKEN_A"
  mv "$STORE_DIR" "$BATS_TEST_TMPDIR/real-store"
  ln -s "$BATS_TEST_TMPDIR/real-store" "$STORE_DIR"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "저장소가 심볼릭 링크"
  refute_output_contains "fp:$(fingerprint_of "$TOKEN_A")"
  refute_token_leak
}

@test "doctor: exits 1 when store directory permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 755 "$STORE_DIR"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "700"
}

@test "doctor: exits 1 when config permissions are loose" {
  seed_profile personal "$TOKEN_A"
  chmod 644 "$CONFIG_FILE"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "chmod 600"
}

@test "doctor: exits 1 when the default points at a missing profile" {
  seed_profile personal "$TOKEN_A"
  rm -f "$TOKENS_DIR/personal.token"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "기본 프로필"
}

@test "doctor: exits 1 when claude is not found" {
  seed_profile personal "$TOKEN_A"
  export CLAUDE_SWITCH_CLAUDE_BIN="$BATS_TEST_TMPDIR/no-such-claude"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "claude"
}

@test "doctor: warns about conflicting environment variables" {
  seed_profile personal "$TOKEN_A"
  export ANTHROPIC_API_KEY="«redacted:sk-…»"
  export ANTHROPIC_AUTH_TOKEN="synthetic-auth-token"
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_VERTEX=1
  export CLAUDE_CODE_USE_FOUNDRY=1
  export ANTHROPIC_BASE_URL="https://gateway.invalid"
  run "$CS" doctor
  assert_output_contains "ANTHROPIC_API_KEY"
  assert_output_contains "ANTHROPIC_AUTH_TOKEN"
  assert_output_contains "CLAUDE_CODE_USE_BEDROCK"
  assert_output_contains "CLAUDE_CODE_USE_VERTEX"
  assert_output_contains "CLAUDE_CODE_USE_FOUNDRY"
  assert_output_contains "ANTHROPIC_BASE_URL"
}

@test "doctor: reports an empty token file with exit 1" {
  seed_profile personal "$TOKEN_A"
  : >"$TOKENS_DIR/personal.token"
  chmod 600 "$TOKENS_DIR/personal.token"
  run "$CS" doctor
  assert_failure 1
  assert_output_contains "빈 토큰"
}

# ============================================================== install.sh
#
# 모든 테스트는 BIN_DIR 또는 임시 HOME 안에서만 설치한다.
# 실제 ~/.local/bin 은 절대 건드리지 않는다.

@test "install.sh: validates the source with macOS system bash" {
  run grep -F '/bin/bash -n "$SRC"' "$REPO_ROOT/install.sh"
  assert_success
}

@test "install.sh: installs into BIN_DIR as an executable" {
  run env BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_success
  [ -x "$BATS_TEST_TMPDIR/bin/claude-switch" ] || flunk "설치본이 실행 가능하지 않음"
  diff "$REPO_ROOT/claude-switch" "$BATS_TEST_TMPDIR/bin/claude-switch" >/dev/null ||
    flunk "설치본이 저장소 파일과 다름"
}

@test "install.sh: defaults to .local/bin under the temporary HOME" {
  run bash "$REPO_ROOT/install.sh"
  assert_success
  [ -x "$HOME/.local/bin/claude-switch" ] || flunk "기본 위치에 설치되지 않음"
}

@test "install.sh: does not install when the source has a syntax error" {
  local fake="$BATS_TEST_TMPDIR/fakerepo"
  mkdir -p "$fake"
  cp "$REPO_ROOT/install.sh" "$fake/"
  printf 'if then fi\n' >"$fake/claude-switch"
  run env BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$fake/install.sh"
  assert_failure
  refute_file_exists "$BATS_TEST_TMPDIR/bin/claude-switch"
}

@test "install.sh: fails when the source is missing" {
  local fake="$BATS_TEST_TMPDIR/emptyrepo"
  mkdir -p "$fake"
  cp "$REPO_ROOT/install.sh" "$fake/"
  run env BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$fake/install.sh"
  assert_failure
  assert_output_contains "claude-switch"
}

@test "install.sh: refuses a symlink destination without touching its target" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf 'ORIGINAL\n# CLAUDE_CODE_OAUTH_TOKEN marker\n' >"$BATS_TEST_TMPDIR/real-target"
  ln -s "$BATS_TEST_TMPDIR/real-target" "$BATS_TEST_TMPDIR/bin/claude-switch"
  run env FORCE=1 BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_failure 1
  assert_output_contains "심볼릭 링크"
  run cat "$BATS_TEST_TMPDIR/real-target"
  assert_output_contains "ORIGINAL"
  refute_output_contains "claude-switch 2"
}

@test "install.sh: detects a v1 installation and does not overwrite without FORCE" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nACCOUNTS_DIR="$HOME/.claude-accounts"\n' \
    >"$BATS_TEST_TMPDIR/bin/claude-switch"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude-switch"
  run bash -c "BIN_DIR='$BATS_TEST_TMPDIR/bin' bash '$REPO_ROOT/install.sh' </dev/null"
  assert_failure 2
  assert_output_contains "v1"
  assert_output_contains "FORCE=1"
  grep -q "ACCOUNTS_DIR" "$BATS_TEST_TMPDIR/bin/claude-switch" ||
    flunk "기존 v1 설치본이 덮어써짐"
}

@test "install.sh: overwrites a v1 installation when FORCE=1" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nACCOUNTS_DIR="$HOME/.claude-accounts"\n' \
    >"$BATS_TEST_TMPDIR/bin/claude-switch"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude-switch"
  run env FORCE=1 BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_success
  assert_output_contains "v1"
  diff "$REPO_ROOT/claude-switch" "$BATS_TEST_TMPDIR/bin/claude-switch" >/dev/null ||
    flunk "v2 로 덮어써지지 않음"
}

@test "install.sh: updates a v2 installation without confirmation" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$REPO_ROOT/claude-switch" "$BATS_TEST_TMPDIR/bin/claude-switch"
  printf '# stale\n' >>"$BATS_TEST_TMPDIR/bin/claude-switch"
  run bash -c "BIN_DIR='$BATS_TEST_TMPDIR/bin' bash '$REPO_ROOT/install.sh' </dev/null"
  assert_success
  diff "$REPO_ROOT/claude-switch" "$BATS_TEST_TMPDIR/bin/claude-switch" >/dev/null ||
    flunk "설치본이 갱신되지 않음"
}

@test "install.sh: warns when claude is missing but the install still succeeds" {
  run env -u CLAUDE_SWITCH_CLAUDE_BIN PATH="/usr/bin:/bin" \
    BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_success
  assert_output_contains "claude"
  [ -x "$BATS_TEST_TMPDIR/bin/claude-switch" ] || flunk "설치되지 않음"
}

@test "install.sh: prints guidance when BIN_DIR is not on PATH" {
  run env BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_success
  assert_output_contains "PATH"
}

@test "install.sh: points to the setup-token procedure as the next step" {
  run env BIN_DIR="$BATS_TEST_TMPDIR/bin" bash "$REPO_ROOT/install.sh"
  assert_success
  assert_output_contains "claude setup-token"
  assert_output_contains "claude-switch add"
}
