# claude-switch v2 OAuth Token 전환 구현 계획

> **[완료 — 2026-08-19]** 이 계획은 `v2.0.0`(`3b6b325`)으로 구현·릴리스되었습니다.
> **현재 동작의 기준은 이 문서가 아니라 `README.md`·`CHANGELOG.md`입니다.** 아래 내용은
> 착수 시점의 의도이며 다음 항목이 실제와 다릅니다:
>
> - **§3 v1 보존** — `v1.0.0` 태그와 `v1` 브랜치는 **만들지 않았습니다.** v1 코드는 일반
>   Git 히스토리(v2 재작성 이전 커밋)에만 있습니다.
> - **§4 공개 명령** — `shell-init`은 구현하지 않고 후속 과제로 이연했습니다.
> - **§1 현재 상태** — HEAD·프로필 목록·도구 설치 상태는 모두 그 시점의 값입니다.
>   (프로필은 4개 → 3개로 통합, `bats`·`shellcheck`는 설치됨, SSH 인증 복구됨)
> - **§2 착수 전 검증** — 판정 결과는 공유 기본값 + `--isolate` 선택 기능이었습니다.
> - 수동 E2E 결과는 `tests/e2e-results.md`에 있습니다. 이 과정에서 문서 4곳의 사실오류를
>   발견해 정정했으며, **CLI가 setup-token의 계정 정체성을 반환하지 않는다**는 제약이
>   드러나 `README.md`에 "알려진 제약"으로 명시했습니다.

> **For Hermes:** 구현 시 Claude Code에 작업을 위임하고, 각 단계마다 명세 준수와 코드 품질을 검토한다. 오빠의 별도 구현 승인을 받기 전에는 실행하지 않는다.

**Goal:** macOS Keychain과 `~/.claude/.credentials.json`을 직접 조작하는 v1을 폐기하고, Anthropic이 문서화한 `CLAUDE_CODE_OAUTH_TOKEN`과 `claude setup-token`만으로 여러 합법적 Claude 계정을 선택 실행하는 v2 래퍼를 만든다.

**Architecture:** 전역 Claude 인증 상태는 변경하지 않는다. `claude-switch run <profile> -- <claude args>`가 보관된 프로필 토큰을 읽어 자식 프로세스의 `CLAUDE_CODE_OAUTH_TOKEN`에만 주입한 뒤 `exec claude "$@"`로 실행한다. 기존 v1 자격증명은 자동 변환·복사·삭제하지 않는다.

**Tech Stack:** Bash, Claude Code CLI 2.1.219+, 공식 `CLAUDE_CODE_OAUTH_TOKEN`, `claude setup-token`, Bats, ShellCheck, GitHub Actions(macOS).

---

## 1. 현재 상태와 수정된 전제

- 저장소: `/Users/kjlee/Projects/claude-switch`
- 현재 브랜치: `main`
- 현재 HEAD: `ca691ed`
- 작업 트리: 깨끗함
- 태그: 없음
- 설치본과 저장소의 `claude-switch`는 일치함
- 등록된 v1 프로필: `office`, `personal`, `team-enterprise`, `team-standard`
- 현재 `~/.claude/.credentials.json`: **없음**
- 현재 Claude 로그인: macOS Keychain 기반이며 실제 Claude 호출은 성공함
- `bats`, `shellcheck`, `op`: 현재 미설치
- GitHub 원격 push/fetch: 현재 SSH `Permission denied (publickey)`로 막힐 수 있음

### v2 불변 원칙

1. `~/.claude/.credentials.json`을 읽거나 쓰지 않는다.
2. `~/.claude.json`을 계정 전환 목적으로 읽거나 쓰지 않는다.
3. Keychain의 Anthropic 서비스 `Claude Code-credentials`를 읽거나 삭제하지 않는다.
4. Anthropic 비공개 OAuth API를 호출하지 않는다.
5. v1 access/refresh token을 v2 토큰으로 자동 변환하지 않는다.
6. 공식 문서에 없는 `CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR` 같은 내부 변수는 사용하지 않는다.
7. 토큰을 명령행 인자, 로그, Git, CI 출력에 노출하지 않는다.
8. `--bare`는 OAuth 토큰을 읽지 않으므로 v2 실행 경로에서 지원하지 않고 명확히 안내한다.

---

## 2. 착수 전 차단성 검증

실제 구현 전에 별도의 테스트용 `setup-token` 하나를 오빠가 직접 발급한다. 토큰 값은 채팅이나 명령행 인자로 전달하지 않는다.

### 검증 항목

1. `CLAUDE_CODE_OAUTH_TOKEN`이 기존 macOS Keychain 로그인보다 우선하는지 확인한다.
2. 토큰 A/B를 바꿔 실행했을 때 `claude auth status`가 각각 올바른 계정과 조직을 표시하는지 확인한다.
3. 공유 `~/.claude.json` 때문에 이메일·조직·청구 계정 표시가 오염되지 않는지 확인한다.
4. `claude -p`와 인터랙티브 `claude` 모두 환경변수 인증으로 동작하는지 확인한다.
5. `--continue`와 `--resume`이 공유 설정에서 계정 간 세션을 섞을 가능성을 기록한다.

### 판정

- 인증과 계정 표시가 정확하면 `CLAUDE_CONFIG_DIR` 공유를 기본값으로 유지하고 `--isolate`를 선택 기능으로 둔다.
- 계정 표시나 세션이 섞이면 프로필별 `CLAUDE_CONFIG_DIR` 격리를 기본값으로 바꾸고, 기존 세션 기록이 분리된다는 경고를 README 최상단에 둔다.
- 환경변수보다 Keychain 인증이 우선한다면 현재 설계를 중단하고 공식 `apiKeyHelper` 기반 대안을 다시 설계한다.

### 완료 조건

- 실제 토큰 원문을 남기지 않은 검증 로그
- 환경변수 우선순위 판정
- 공유 또는 격리 기본값 확정
- 각 실행이 올바른 이메일·조직을 사용한다는 확인

---

## 3. v1 보존 전략

### 작업

1. 현재 HEAD `ca691ed`에 로컬 annotated tag `v1.0.0`을 만든다.
2. `v1` 보존 브랜치를 만든다.
3. v1 README에 deprecated 배너를 추가한다.
4. v1 README의 curl 설치 URL을 `main`이 아니라 `v1` 브랜치 또는 `v1.0.0` 태그에 고정한다.
5. GitHub SSH 인증을 복구한 뒤에만 tag와 branch를 push한다.
6. `v2-oauth-token` 브랜치에서 v2를 개발한다.

### 주의

v1 소스 롤백은 가능하지만, 기존 v1 프로필 토큰이 만료됐을 수 있으므로 **v1 인증 상태까지 정상 복구된다고 보장하지 않는다.** v1은 코드 보존 및 비상 비교용이다.

### 완료 조건

- 로컬 `v1.0.0` 태그와 `v1` 브랜치 존재
- SSH 인증 복구 후 원격 tag/branch 확인
- v1 설치 문서가 더 이상 변경 가능한 `main` 파일을 가리키지 않음
- v2 작업 브랜치에서 v1 파일이 보존됨

---

## 4. v2 CLI 설계

### 공개 명령

```text
claude-switch run <profile> [-- <claude args...>]
claude-switch <profile> [-- <claude args...>]       # run 축약형
claude-switch list
claude-switch add <profile> [--stdin]
claude-switch remove <profile>
claude-switch default <profile>
claude-switch verify <profile>
claude-switch doctor
claude-switch migrate-check [--acknowledge]
claude-switch shell-init
```

### 의도적으로 제공하지 않을 명령

- 토큰을 출력하는 `env` 명령
- `add <profile> <token>` 형태
- v1의 전역 credentials 교체 명령
- v1 `capture`의 암묵적 호환

### 하위호환 정책

- v1의 “전환 후 다음 `claude`부터 적용” 의미는 재현하지 않는다.
- v2의 `claude-switch <profile>`은 전역 전환이 아니라 해당 프로필로 Claude를 즉시 실행하는 축약형이다.
- v1 서브커맨드에는 exit 2와 마이그레이션 안내를 반환한다.
- README와 CHANGELOG에 breaking change를 명시한다.

### 완료 조건

- `--help`에 v2 명령만 노출
- v1 자격증명 조작 함수가 소스에서 제거됨
- v1 명령 실행 시 자격증명을 건드리지 않고 안내만 출력

---

## 5. 실행 모델

### 핵심 흐름

```bash
run_profile() {
  local profile="$1"
  shift

  local token
  token="$(read_token "$profile")" || die "프로필 토큰을 읽을 수 없음"
  [ -n "$token" ] || die "빈 토큰"

  export CLAUDE_CODE_OAUTH_TOKEN="$token"
  exec claude "$@"
}
```

실제 구현에서는 토큰 변수 취급 구간에서 xtrace를 강제로 끄고, 오류 메시지에 변수 값을 넣지 않는다.

### 요구사항

- 자식 셸이 아닌 `exec` 사용
- TTY, Ctrl-C, 종료코드 보존
- `--` 뒤 인자 무가공 전달
- 공백과 빈 인자 보존
- stdin 파이프 전달
- 실행 시작 시 프로필 이름만 stderr에 표시
- `--bare`가 전달되면 토큰 인증이 동작하지 않는다는 경고 후 exit 2

### 완료 조건

- 인터랙티브 실행 성공
- `-p` 실행 성공
- Ctrl-C와 종료코드 전달 성공
- `ps` 명령행에 토큰 원문이 나타나지 않음
- stdout/stderr에 토큰 원문이 나타나지 않음

---

## 6. 토큰 저장 백엔드

### 1차 구현 기본값

`file` 백엔드만 먼저 구현한다.

```text
~/.claude-switch/                       0700
~/.claude-switch/config                 0600
~/.claude-switch/tokens/<profile>.token 0600
```

### 선택 이유

- Hermes, SSH, 백그라운드 실행에서 GUI 프롬프트 없이 동작해야 한다.
- 기존 Keychain 방식은 ACL 프롬프트와 원격 hang이 프로젝트 탄생 원인이었다.
- 1Password CLI는 현재 설치되지 않았고 로그인·오프라인 상태에 따른 실패 처리가 추가로 필요하다.

### 후속 백엔드

- macOS Keychain: 명시적 opt-in, headless 프롬프트 위험 고지
- 1Password CLI: `op read` 참조만 저장하고 토큰은 1Password에서 읽는 opt-in
- 자동 fallback 금지: 보안 백엔드 실패 시 평문 파일로 조용히 강등하지 않는다.

### 보안 요구사항

- `umask 077`
- 디렉터리 0700, 토큰 파일 0600 검증
- 심볼릭 링크 거부
- 프로필명 `^[A-Za-z0-9._-]+$`
- 토큰 원문 출력 금지
- 지문은 SHA-256 앞 8자처럼 원문을 복원할 수 없는 값 사용
- FileVault 및 백업 제외 권고를 README에 기록

### 완료 조건

- file 백엔드 write/read/delete 계약 테스트 통과
- 잘못된 권한과 심볼릭 링크를 `doctor`가 실패로 보고
- 토큰 파일이 Git에 포함되지 않음

---

## 7. 등록과 마이그레이션

### 신규 등록

1. 사용자가 별도 터미널에서 `claude setup-token`을 실행한다.
2. 브라우저에서 원하는 계정·조직을 승인한다.
3. 출력된 토큰을 `claude-switch add <profile>`의 비표시 입력에 붙여넣는다.
4. 자동화는 `--stdin`만 허용한다.
5. 등록 직후 `verify <profile>`로 이메일·조직을 확인한다.
6. 스크롤백 정리를 안내한다.

### 자동 마이그레이션 금지

v1은 access/refresh token 쌍이고 v2는 `setup-token` 장기 OAuth 토큰이다. 수명과 발급 경로가 달라 안전한 변환이 불가능하다. v2는 `~/.claude-accounts`의 존재만 감지하고 내용을 읽거나 삭제하지 않는다.

### 잔재 처리

- 첫 실행 시 v1 디렉터리를 감지하면 마이그레이션 안내를 출력한다.
- `migrate-check --acknowledge`로 사용자가 수동 재등록 원칙을 확인해야 v2 명령이 열린다.
- v1 디렉터리 삭제는 사용자가 별도로 결정한다.

### 완료 조건

- 네 프로필 모두 각각 새 `setup-token`으로 재등록
- 각 `verify`가 올바른 계정·조직을 표시
- v1 파일의 mtime과 내용이 전혀 변하지 않음

---

## 8. 파일별 변경

### Modify: `claude-switch`

전면 재작성한다.

- 삭제: Keychain Anthropic 항목 삭제, credentials write-back, config write-back, 비공개 profile API, v1 capture/add-from-file
- 유지: `set -euo pipefail`, 프로필명 검증, 한국어 메시지 스타일
- 추가: v1 residue guard, file backend, add/run/list/default/remove/verify/doctor/migrate-check/shell-init

### Modify: `README.md`

- 공식 OAuth 토큰 기반 구조 설명
- v1과 v2 차이
- `run` 래퍼 사용법
- setup-token 등록
- 평문 파일 백엔드 위험과 권한
- `--bare` 비호환
- 공유/격리 설정의 세션 영향
- 수동 마이그레이션
- 긴급 revoke 절차

### Modify: `install.sh`

- 설치 전 v1 바이너리 탐지
- 대화형 확인 또는 비대화형 `FORCE=1`
- 설치 후 `claude` 존재 확인
- syntax check 유지

### Create

- `tests/test_helper.bash`
- `tests/unit.bats`
- `tests/integration.bats`
- `tests/stubs/claude`
- `tests/e2e.md`
- `.github/workflows/ci.yml`
- `CHANGELOG.md`

---

## 9. TDD 구현 순서

### Task 1: v1 보존

- 태그·브랜치 생성
- v1 문서 URL 고정
- GitHub SSH 인증이 되기 전에는 push하지 않음
- 검증 후 커밋

### Task 2: 테스트 하네스

- Bats와 ShellCheck 설치
- 테스트마다 임시 `$HOME` 사용
- 가짜 `claude` 스텁 생성
- 실제 `~/.claude*` 접근 시 테스트 실패

### Task 3: 프로필명과 권한 검증

- 실패 테스트 작성
- traversal, 공백, 특수문자, 심볼릭 링크 거부 구현
- 0700/0600 검증

### Task 4: file 백엔드

- write/read/delete 실패 테스트
- 최소 구현
- 토큰 누출 grep 테스트

### Task 5: add/list/default/remove

- 토큰 비표시 입력 테스트
- 토큰 인자 거부 테스트
- 지문 출력 테스트
- 기본 프로필 관리

### Task 6: run/verify

- 인자 전달, stdin, TTY, Ctrl-C, 종료코드 테스트
- `CLAUDE_CODE_OAUTH_TOKEN` 주입 확인
- `--bare` 차단 테스트

### Task 7: v1 가드와 doctor

- v1 디렉터리 존재 시 차단 테스트
- acknowledge 후 진행 테스트
- 실제 v1 파일 불변 테스트

### Task 8: 설치와 문서

- v1 설치본 탐지
- 강제 설치 정책
- README·CHANGELOG 작성

### Task 9: CI와 실제 E2E

- 합성 토큰만 쓰는 macOS CI
- 오빠가 직접 발급한 토큰으로 수동 E2E
- 서로 다른 두 계정 교차 실행
- 로그와 프로세스 목록에서 토큰 누출 검사

---

## 10. 검증 명령

```bash
bash -n claude-switch install.sh
shellcheck -S warning claude-switch install.sh
bats tests/
git status --short
```

수동 E2E:

```bash
claude-switch add e2e-test
claude-switch verify e2e-test
claude-switch run e2e-test -- -p "다른 설명 없이 OK만 출력"
claude-switch remove e2e-test
```

검증 전후:

```bash
stat ~/.claude-accounts ~/.claude/.credentials.json 2>/dev/null || true
ps -eo args | grep -i 'sk-ant' | grep -v grep
```

### 최종 완료 조건

- 단위·통합 테스트 전부 통과
- ShellCheck warning 0
- 실제 계정 두 개 이상 교차 E2E 성공
- 프로필별 이메일·조직 확인
- 토큰 원문 누출 0
- v1 디렉터리와 Anthropic Keychain 항목 불변
- 설치본과 저장소 파일 일치
- GitHub CI 통과

---

## 11. 릴리스와 롤백

1. `v2-oauth-token` 브랜치에서 구현한다.
2. 네 계정을 재등록하고 최소 1주 실사용한다.
3. `main`에 병합하고 `v2.0.0` 태그를 만든다.
4. README 상단에 30일간 breaking migration 배너를 유지한다.
5. 문제가 생기면 `v1.0.0` 소스를 재설치할 수 있지만, v1 토큰 유효성은 별도로 재확인한다.
6. v2 토큰 유출 시 Anthropic에서 즉시 revoke하고 해당 프로필 파일을 삭제한 뒤 재발급한다.

---

## 12. 구현 전 오빠 확인이 필요한 결정

### D1. Claude 설정 격리

**권장:** 공유 기본값, `--isolate` 선택 기능. 단, 착수 전 실측에서 계정 표시나 세션 오염이 발견되면 격리 기본값으로 변경한다.

### D2. 기본 토큰 저장소

**권장:** 1차 릴리스는 0600 file. Hermes·SSH·백그라운드 신뢰성을 우선한다. 1Password와 Keychain은 후속 opt-in으로 구현한다.

### D3. v1 하위호환

**권장:** 자격증명 동작은 호환하지 않고 명확히 차단·안내한다. v1 소스는 태그와 브랜치로만 보존한다.

### D4. 릴리스 범위

**권장:** 첫 릴리스는 file 백엔드와 핵심 run/add/verify/doctor만 구현한다. Keychain, 1Password, shell-init은 핵심 안정화 후 후속 릴리스로 분리한다.
