# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식과
[Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다.

## [Unreleased] — 2.0.0 준비 중

`v2-oauth-token` 브랜치에서 개발 중입니다. 아직 `main`에 병합하거나 태그를 만들지
않았습니다. 릴리스 전에 실제 계정 두 개 이상으로 `tests/e2e.md` 절차를 통과해야 합니다.

### 파괴적 변경 (Breaking)

- **전역 인증을 더 이상 건드리지 않습니다.** v1은 `~/.claude/.credentials.json`과
  macOS Keychain의 `Claude Code-credentials` 항목을 직접 교체했습니다. v2는 이 경로를
  읽지도, 쓰지도, 지우지도 않습니다.
- **`claude-switch <profile>`의 의미가 바뀌었습니다.** v1은 "다음 `claude` 호출부터 이
  계정"이라는 전역 전환이었고, v2는 "지금 이 프로필로 `claude`를 실행"하는 `run`
  축약형입니다.
- **v1 프로필은 자동 변환되지 않습니다.** v1은 `/login`이 만든 access/refresh 토큰
  쌍이고, v2는 `claude setup-token`이 발급하는 1년 OAuth 토큰입니다. 수명과 발급
  경로가 달라 안전한 변환이 불가능합니다. 계정마다 새로 발급해 다시 등록해야 합니다.
- **`~/.claude-accounts`가 있으면 v2 명령을 막습니다.** 존재만 감지하고 내용은 읽지
  않습니다. `claude-switch migrate-check --acknowledge`로 수동 재등록 원칙을 확인해야
  명령이 열립니다. 디렉터리 삭제 여부는 사용자가 직접 결정합니다.
- **`capture` 서브커맨드 제거.** 실행하면 exit 2와 재등록 안내만 출력합니다.
- **Anthropic 비공개 OAuth API(`api.anthropic.com/api/oauth/profile`) 호출을
  제거했습니다.**
- **저장소 위치가 바뀌었습니다.** `~/.claude-accounts` → `~/.claude-switch`.

### 추가

- `run <profile> [-- <claude args...>]` — 프로필 토큰을 자식 프로세스의
  `CLAUDE_CODE_OAUTH_TOKEN`에만 주입하고 `exec claude`로 교체합니다. TTY, `Ctrl-C`,
  종료코드, stdin 파이프, 빈 인자와 공백이 그대로 보존됩니다.
- `<profile> [-- <args>]` — `run` 축약형. 서브커맨드와 이름이 겹치는 프로필은
  `run`을 명시해야 합니다.
- `add <profile> [--stdin] [--force]` — 비표시 입력으로 토큰을 등록합니다. 토큰을
  위치 인자로 주면 거부합니다. 자동화는 `--stdin`만 허용합니다.
- `list` — 프로필과 지문(SHA-256 앞 8자), 기본 프로필 표시.
- `default [<profile>]` — 기본 프로필 설정·조회. 첫 `add`가 자동으로 기본이 됩니다.
- `remove <profile>` — 로컬 토큰 파일만 삭제하고 revoke 안내를 출력합니다.
- `verify [<profile>]` — 권한·지문 검사 후 `claude auth status --text`로 계정·조직을
  확인합니다. 자식 출력에 토큰이 섞여 나오면 `[redacted]`로 마스킹합니다.
- `doctor` — 저장소 권한, 심볼릭 링크, 빈·잘못된 토큰, 기본 프로필, `claude` 경로,
  충돌 환경변수, v1 잔재를 진단합니다.
- `migrate-check [--acknowledge]` — v1 잔재 확인과 수동 재등록 승인.
- `--isolate` — 그 실행에만 `CLAUDE_CONFIG_DIR=~/.claude-switch/isolated/<profile>`를
  씁니다. 기본값은 설정 공유입니다.
- `--bare` 차단 — `claude --bare`는 OAuth 토큰을 읽지 않으므로 실행 전에 exit 2로
  막습니다.
- 종료 코드 규약: 0 성공 / 1 상태 오류 / 2 사용법 오류 / 127 `claude` 없음 /
  그 외는 `claude`의 종료 코드 그대로.
- `install.sh` — v1 설치본을 감지해 확인을 요구하고(비대화형은 `FORCE=1`), 설치 전
  문법 검사와 설치 후 `claude` 존재 확인을 합니다.
- Bats 테스트(`tests/unit.bats`, `tests/integration.bats`)와 macOS GitHub Actions CI.
  테스트는 임시 `$HOME`, 합성 토큰, 가짜 `claude` 스텁만 사용합니다.
- 수동 E2E 절차 문서 `tests/e2e.md`.

### 보안

- 저장소 `0700`, `config`·토큰 파일·승인 표시 파일 `0600`. `umask 077`.
- `list`·`run`·`verify`·`remove`는 저장소와 토큰 디렉터리가 실제 디렉터리이고
  권한이 `0700`인지 확인한 뒤에만 토큰을 읽거나 삭제합니다.
- 저장소·토큰 경로가 심볼릭 링크면 읽기·쓰기·실행을 모두 거부합니다.
- 프로필명은 `^[A-Za-z0-9][A-Za-z0-9._-]*$`만 허용해 경로 탈출을 막습니다.
- 토큰은 환경변수로만 전달합니다. 명령행 인자에 실리지 않아 `ps`에 노출되지 않습니다.
- 출력에는 항상 복원 불가능한 지문(`fp:` + SHA-256 앞 8자)만 씁니다.
- `config`는 절대 `source`하지 않고 엄격한 `key=value` 정규식으로만 읽습니다.
- 환경변수로 통제 가능한 상위 인증과 라우팅 충돌
  (`CLAUDE_CODE_USE_BEDROCK`·`CLAUDE_CODE_USE_VERTEX`·`CLAUDE_CODE_USE_FOUNDRY`·
  `ANTHROPIC_API_KEY`·`ANTHROPIC_AUTH_TOKEN`·`ANTHROPIC_BASE_URL`)은 경고하고 자식
  `claude`에서 제거합니다. 부모 셸은 변경하지 않습니다.
- `verify`는 `claude auth status`의 false positive를 막기 위해 고정된 최소 프롬프트로
  실제 모델 요청까지 수행하며, 서버가 토큰을 거부하면 exit 1로 실패합니다.
- `apiKeyHelper`와 활성 Gateway 세션은 환경변수가 아니며 OAuth보다 우선할 수 있어,
  `verify`에서 OAuth 인증원과 실제 모델 호출 성공을 확인하도록 문서화했습니다.
- 토큰은 평문 파일로 저장됩니다. FileVault 사용과 백업·동기화 제외를 권고합니다.

### 이번 릴리스에 포함하지 않음 (후속 과제)

- macOS Keychain 백엔드 — 명시적 opt-in, headless 프롬프트 위험 고지 필요.
- 1Password CLI 백엔드 — `op read` 참조만 저장.
- `shell-init` — 셸 통합(프롬프트 표시, 자동완성).
- 보안 백엔드 실패 시 평문 파일로 조용히 강등하는 자동 fallback은 넣지 않습니다.

## [1.0.0] — 태그 `v1.0.0` (deprecated)

Keychain 프롬프트 없이 `~/.claude/.credentials.json`을 심볼릭 링크·복사로 갈아끼우고
`~/.claude.json` 스냅샷을 관리하던 전역 전환 방식. v2로 대체되었습니다.

소스는 `v1.0.0` 태그와 `v1` 브랜치에 보존되어 있습니다. 되돌릴 수는 있지만 **v1
프로필 토큰이 이미 만료됐을 수 있어 인증 상태까지 복구된다고 보장하지 않습니다.**
