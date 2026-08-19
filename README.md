# claude-switch

> **v2 breaking change (2026-08)**
> v1과 v2는 동작 방식이 다릅니다. v1은 전역 Claude 자격증명(`~/.claude/.credentials.json`,
> macOS Keychain)을 직접 갈아끼웠고, **v2는 전역 인증을 전혀 건드리지 않습니다.**
> v2는 프로필별 OAuth 토큰을 해당 `claude` 프로세스에만 주입하는 실행 래퍼입니다.
> **v1 프로필은 자동 변환되지 않습니다.** 계정마다 `claude setup-token`으로 새 토큰을
> 발급해 다시 등록해야 합니다. v1 전용 `v1` 브랜치나 `v1.0.0` 태그는 없습니다.
> v1 코드는 일반 Git 히스토리(v2 재작성 이전 커밋)에만 남아 있습니다.

여러 Claude 계정을 프로필로 등록해 두고, 원하는 계정으로 `claude`를 즉시 실행하는 CLI 래퍼.

```bash
claude setup-token                 # 별도 터미널에서 계정 A 승인
claude-switch add personal         # 토큰을 비표시 입력으로 붙여넣기
claude-switch verify personal      # 저장 상태 + 실제 OAuth 요청 확인
                                   # (이메일·조직은 브라우저 승인 화면에서 확인)

claude-switch personal             # personal 계정으로 claude 실행
claude-switch office -- -p "요약"  # office 계정으로 비대화형 실행
```

## v1과 무엇이 다른가

| | v1 | v2 |
|---|---|---|
| 토큰 종류 | `/login`이 만든 access/refresh 쌍 | `claude setup-token`의 1년 OAuth 토큰 |
| 적용 방식 | 전역 자격증명 파일·Keychain 교체 | 자식 프로세스 환경변수 주입 |
| 전역 상태 | 변경함 | **변경하지 않음** |
| `claude-switch <profile>` | "다음 claude 호출부터 이 계정" | "**지금 이 계정으로 claude 실행**" |
| Keychain | 항목 삭제 | 읽지도 지우지도 않음 |
| 비공개 API | `api.anthropic.com/api/oauth/profile` 호출 | 호출하지 않음 |
| 동시 사용 | 불가(전역 상태가 하나) | 가능(터미널마다 다른 프로필) |

v2가 지키는 불변 원칙:

1. `~/.claude/.credentials.json`을 읽거나 쓰지 않는다.
2. `~/.claude.json`을 계정 전환 목적으로 읽거나 쓰지 않는다.
3. Keychain의 `Claude Code-credentials`를 읽거나 삭제하지 않는다.
4. Anthropic 비공개 OAuth API를 호출하지 않는다.
5. v1 토큰을 v2 토큰으로 자동 변환하지 않는다.
6. 문서화되지 않은 내부 환경변수를 쓰지 않는다.
7. 토큰을 명령행 인자, 로그, Git, CI 출력에 노출하지 않는다.

이 원칙은 `tests/unit.bats`의 "순수성" 테스트가 소스를 직접 검사해 강제합니다.

## 동작 원리

```
claude-switch run personal -- -p "안녕"
   │
   ├─ ~/.claude-switch/tokens/personal.token 읽기 (0600, 심볼릭 링크 거부)
   ├─ CLAUDE_CODE_OAUTH_TOKEN 을 이 프로세스 환경에만 export
   └─ exec claude -p "안녕"        ← 전역 인증 상태는 그대로
```

`exec`로 교체하므로 TTY, Ctrl-C, 종료코드, stdin 파이프가 그대로 보존됩니다.
토큰은 환경변수로만 전달되며 명령행 인자에 실리지 않습니다(`ps`에 노출되지 않음).

### 저장소

```
~/.claude-switch/                        0700
~/.claude-switch/config                  0600   default=<profile>
~/.claude-switch/tokens/<profile>.token  0600   토큰 원문 1줄
~/.claude-switch/isolated/<profile>/     0700   --isolate 전용 CLAUDE_CONFIG_DIR
~/.claude-switch/.v1-acknowledged        0600   v1 수동 재등록 승인 표시
```

## 설치

```bash
git clone https://github.com/lkjsays/claude-switch.git
cd claude-switch
./install.sh
```

기본 설치 위치는 `~/.local/bin/claude-switch`. 위치 변경:

```bash
PREFIX=/opt/homebrew ./install.sh       # /opt/homebrew/bin/claude-switch
BIN_DIR=/usr/local/bin ./install.sh     # /usr/local/bin/claude-switch
```

v1 설치본이 발견되면 확인을 요청합니다. 비대화형 환경에서는 `FORCE=1 ./install.sh`.

### 제거

```bash
./uninstall.sh                 # 설치된 claude-switch 명령만 제거 (저장소 보존)
./uninstall.sh --purge         # ~/.claude-switch 까지 제거 (삭제 전 확인)
./uninstall.sh --purge --yes   # 확인 없이 저장소까지 제거
```

기본 실행은 **프로필과 토큰을 지우지 않습니다.** `~/.claude-switch`는 그대로 두고,
이 도구가 설치한 `claude-switch` 실행 파일만 제거합니다. 삭제는 `--purge`를 명시했을
때만 일어나며, `--yes` 없이 실행하면 삭제 전에 확인을 요청합니다. 확인을 거절하거나
입력이 없으면(비대화형 EOF) 저장소를 그대로 보존하고 exit 0으로 끝납니다.

제거 스크립트도 v2의 불변 원칙을 그대로 지킵니다:

- `~/.claude/.credentials.json`, `~/.claude.json`, Keychain의 `Claude Code-credentials`를
  읽지도 지우지도 않습니다. **v2는 전역 인증을 바꾼 적이 없으므로 되돌릴 것도 없습니다.**
- v1 저장소(`~/.claude-accounts`, `~/.claude-homes`)를 건드리지 않습니다. 삭제 여부는
  직접 결정하세요.
- `~/.claude-switch`가 심볼릭 링크이거나 디렉터리가 아니면 `--purge`는 대상을 따라가지
  않고 exit 1로 거부합니다. 이 검사는 **설치본을 지우기 전에** 이뤄지므로, 명령만
  지워지고 저장소는 남는 어중간한 상태가 생기지 않습니다.
- 제거 대상은 소스에 박힌 **설치 서명 줄이 정확히 일치하는 파일뿐**입니다. 본문에
  `claude-switch`라는 낱말이 있다는 이유만으로는 지우지 않으므로, 이름만 같은 남의
  스크립트는 그대로 남습니다.
- 명령 파일 자체가 심볼릭 링크이면 따라가지 않고 건너뜁니다(그 경로만 건너뛰고 나머지
  검색은 계속하며 exit 0).
- **검색 경로 자체나 그 상위 경로 구성요소가 심볼릭 링크이거나, 절대 경로가 아니거나
  `..`가 섞여 있으면** 링크 너머를 해석하지 않고 **exit 1로 중단합니다.** 이 검사는
  **모든 검색 경로에 대해 삭제가 시작되기 전에** 끝나므로, 앞선 경로의 설치본만 지워지고
  뒤에서 실패하는 부분 제거가 생기지 않습니다. 건너뛴 뒤 성공으로 끝내면 설치본이 남아
  있는데도 제거에 성공한 것처럼 보이므로, 조용히 넘어가지 않습니다.
- 존재하지 않는 정상적인 절대 경로는 안전하게 취급합니다(설치본이 없을 뿐입니다).
- 여러 번 실행해도 결과가 같습니다(idempotent).

검색 위치는 설치와 대칭입니다. 기본값은 `$BIN_DIR`, `$PREFIX/bin`, `~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`이며 `CLAUDE_SWITCH_BIN_DIRS`(콜론 구분)로 통째로
바꿀 수 있습니다.

```bash
BIN_DIR=/usr/local/bin ./uninstall.sh
```

### 요구사항

- macOS 또는 Linux, bash 3.2+
- `claude` CLI (Claude Code 2.1.219+, `claude setup-token` 지원 버전)
- `shasum` (지문 계산)
- Claude 구독 계정 (`setup-token`은 구독이 필요)

## 사용법

### 토큰 등록

```bash
claude setup-token          # 브라우저에서 원하는 계정·조직 승인 → 토큰 출력
claude-switch add personal  # 비표시 입력에 붙여넣기 (화면에 표시되지 않음)
```

- `claude setup-token`은 1년 유효 OAuth 토큰을 터미널에 출력하며 자체적으로 저장하지 않습니다.
- `setup-token`은 관리 설정의 `forceLoginMethod`는 따르지만 `forceLoginOrgUUID`는 강제하지
  않습니다. Team/Enterprise 계정은 브라우저 승인 화면에서 이메일과 조직을 반드시 확인하세요.
  `verify`는 실제 모델 요청 성공 여부를 검사하지만 setup-token의 이메일·조직은 표시하지 않습니다.
- 토큰을 명령행 인자로 받지 않습니다: `claude-switch add personal sk-ant-...` → 거부.
- 자동화에서는 stdin만 허용: `pbpaste | claude-switch add personal --stdin`.
- 등록 후 **셸 스크롤백과 클립보드를 지우세요.** `setup-token` 출력은 스크롤백에 남습니다.
- 덮어쓰려면 `--force`.

### 실행

```bash
claude-switch run personal                  # 인터랙티브
claude-switch personal                      # run 축약형
claude-switch personal -- -p "요약해줘"      # -- 뒤 인자는 claude 로 그대로 전달
claude-switch run -- -p "안녕"               # 프로필 생략 시 기본 프로필
echo "질문" | claude-switch personal -- -p   # stdin 파이프도 그대로
```

`list`, `add`, `doctor` 같은 서브커맨드와 이름이 같은 프로필은 축약형으로 실행할 수
없습니다. `claude-switch run list` 처럼 `run`을 명시하세요.

### 관리

```bash
claude-switch list                 # 프로필과 지문(SHA-256 앞 8자), 기본 프로필 표시
claude-switch default office       # 기본 프로필 설정
claude-switch default              # 기본 프로필 조회
claude-switch verify personal      # 권한·지문·auth status + 실제 최소 모델 요청
claude-switch remove personal      # 프로필 삭제
claude-switch doctor               # 저장소 전체 진단
claude-switch migrate-check        # v1 잔재 확인
```

`verify`는 `claude auth status`만 믿지 않고 고정된 최소 프롬프트로 실제 모델 요청까지
실행합니다. 따라서 소량의 구독 사용량과 네트워크 연결이 필요하며, 서버가 토큰을 거부하면
exit 1로 실패합니다.

#### 알려진 제약: 등록 후에는 프로필의 계정을 확인할 수 없습니다

`CLAUDE_CODE_OAUTH_TOKEN` 인증에서 `claude auth status`는 **계정 정체성을 해석하지
않습니다.** `--text`는 인증원 한 줄(`Auth token: CLAUDE_CODE_OAUTH_TOKEN`)만,
`--json`은 `loggedIn`·`authMethod`·`apiProvider`만 반환합니다. 전역 `/login` 인증에서는
이메일·조직이 나오지만 토큰 인증에서는 나오지 않습니다.

따라서 `verify`는 **토큰이 유효하고 살아 있다는 것**까지만 보장하고, 그 토큰이 어느
계정인지는 알려주지 못합니다. 서로 다른 프로필도 `verify` 출력이 동일하게 보입니다
(구별되는 것은 지문뿐이며, 지문은 토큰이 다르다는 뜻일 뿐입니다).

**계정을 확인할 수 있는 유일한 지점은 `claude setup-token`의 브라우저 승인 화면입니다.**
프로필마다 등록할 때 그 화면에서 이메일·조직을 직접 확인하고, 프로필 이름을 계정과
헷갈리지 않게 지으세요.

### 설정 격리 (`--isolate`)

기본값은 **공유**입니다. 모든 프로필이 같은 `~/.claude` 설정과 세션 기록을 씁니다.
공식 `claude` 자식 프로세스가 실행 중 `~/.claude.json` 메타데이터를 갱신할 수 있지만,
`claude-switch` 자체는 이 파일을 읽거나 쓰지 않습니다. 엄격한 설정 분리가 필요하면
`--isolate`를 사용하세요.

```bash
claude-switch run --isolate office -- -p "안녕"
```

`--isolate`를 주면 그 실행에만 `CLAUDE_CONFIG_DIR=~/.claude-switch/isolated/<profile>`을
씁니다. 프로필별로 설정·세션·MCP 상태가 완전히 분리되지만:

- 기존 세션 기록(`--continue`, `--resume`)이 보이지 않습니다.
- 프로필별로 처음 한 번 신뢰 프롬프트·온보딩을 다시 거칩니다.
- 프로필을 섞어 쓰면 `--continue`가 어느 쪽 세션을 잇는지 예측하기 어렵습니다.

공유 기본값에서 `--continue`/`--resume`은 **계정과 무관하게** 디렉터리 기준으로 최근
세션을 잇습니다. 계정 A로 만든 세션을 계정 B로 이어받을 수 있으니, 계정 경계가
중요한 작업에는 `--isolate`를 쓰거나 `--continue`를 피하세요.

## 보안

토큰은 **평문 파일**로 저장됩니다(0600). 이 선택은 의도적입니다: Keychain 방식은
백그라운드·SSH·자동화에서 GUI 권한 프롬프트로 hang되는 문제가 v1의 근본 원인이었습니다.

권장 조치:

- FileVault를 켜세요. 디스크 도난 시 유일한 보호막입니다.
- `~/.claude-switch`를 백업·동기화 대상에서 제외하세요(Time Machine 제외, Dropbox/iCloud 밖).
- 지문(`fp:xxxxxxxx`)은 SHA-256 앞 8자로 원문을 복원할 수 없습니다. 토큰 비교에만 쓰세요.
- `claude-switch doctor`로 권한·심볼릭 링크·잔재를 정기 점검하세요.

### 토큰 유출 시

1. Anthropic 콘솔(또는 `claude auth`)에서 해당 토큰을 즉시 **revoke**합니다.
2. `claude-switch remove <profile>`로 로컬 파일을 지웁니다.
3. `claude setup-token`으로 새로 발급해 `claude-switch add <profile>`로 재등록합니다.

`remove`는 로컬 파일만 지웁니다. **revoke는 자동으로 되지 않습니다.**

### `--bare` 비호환

`claude --bare`는 OAuth와 Keychain을 아예 읽지 않고 `ANTHROPIC_API_KEY` 또는
`apiKeyHelper`만 씁니다. 따라서 `CLAUDE_CODE_OAUTH_TOKEN` 주입이 무시됩니다.
`claude-switch`는 `--bare`가 인자에 있으면 실행 전에 exit 2로 막습니다.

### 인증 우선순위와 환경변수 충돌

Claude Code의 공식 인증 우선순위는 Gateway 세션 → Bedrock/Vertex/Foundry →
`ANTHROPIC_AUTH_TOKEN` → `ANTHROPIC_API_KEY` → `apiKeyHelper` →
`CLAUDE_CODE_OAUTH_TOKEN` → 일반 `/login` 순서입니다.

`run`과 `verify`는 환경변수로 통제 가능한 상위 인증과 라우팅 충돌을 경고한 뒤 자식
`claude`에서 제거합니다:

- `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`
- `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`
- `ANTHROPIC_BASE_URL` — OAuth 토큰이 커스텀 엔드포인트로 전송되는 것을 방지

부모 셸의 환경변수는 변경하지 않습니다. `doctor`는 현재 셸에 이 변수가 있으면 경고합니다.

`apiKeyHelper`와 이미 활성화된 Claude apps Gateway 세션은 환경변수가 아니어서
`claude-switch`가 안전하게 제거할 수 없습니다. 둘 다 OAuth 토큰보다 우선할 수 있으므로
`claude-switch verify <profile>`에서 인증원이 OAuth token인지, 실제 모델 호출이 성공하는지
확인하고 예상과 다르면 해당 설정이나 Gateway 세션을 먼저 해제해야 합니다.

## v1에서 옮기기

v2는 `~/.claude-accounts`가 있으면 **존재만 감지**하고 명령을 막습니다. 내용을 읽거나
지우지 않습니다.

```bash
claude-switch migrate-check                 # 왜 자동 변환이 불가능한지 확인
claude-switch migrate-check --acknowledge   # 수동 재등록 원칙 승인, v2 명령 잠금 해제
claude setup-token                          # 계정마다 새 토큰 발급
claude-switch add <profile>
claude-switch verify <profile>
```

자동 변환을 하지 않는 이유: v1은 access/refresh token 쌍이고 v2는 `setup-token`의 1년
OAuth 토큰입니다. 수명과 발급 경로가 달라 안전한 변환이 불가능합니다.

`~/.claude-accounts` 삭제는 직접 결정하세요. v2는 지우지 않습니다.
v1 전용 `v1` 브랜치나 `v1.0.0` 태그는 없습니다. v1 코드가 필요하면 일반 Git 히스토리에서
v2 재작성 이전 커밋을 직접 찾아 꺼내야 합니다(`git log -- claude-switch`). 단 **v1 토큰이
이미 만료됐을 수 있어 v1 인증 상태까지 복구된다고 보장하지 않습니다.**

## 종료 코드

| 코드 | 의미 |
|---|---|
| 0 | 성공 |
| 1 | 프로필 없음, 권한·심볼릭 링크·빈 토큰, 인증 확인 실패, `doctor` 실패 |
| 2 | 사용법 오류, 잘못된 프로필 이름, `--bare` 차단, v1 잔재 미승인, v1 명령 |
| 127 | `claude`를 찾을 수 없음 |
| 그 외 | `claude`의 종료 코드를 그대로 전달 |

## 개발

```bash
bash -n claude-switch install.sh uninstall.sh
shellcheck -S warning claude-switch install.sh uninstall.sh
bats tests/
```

테스트는 임시 `$HOME`, 합성 토큰, 가짜 `claude` 스텁만 사용합니다. 실제 계정 자격증명이나
`claude setup-token`을 쓰지 않습니다. 수동 E2E 절차는 `tests/e2e.md`를 보세요.

같은 검사를 macOS에서 자동 실행하는 CI는 `.github/workflows/ci.yml`에 있습니다.
`claude-switch`의 shebang이 `#!/bin/bash`라 macOS 기본 bash 3.2에서 검증됩니다.
버전별 변경 내역은 `CHANGELOG.md`를 보세요.

## 후속 과제 (이번 릴리스 미포함)

- **macOS Keychain 백엔드** — 명시적 opt-in. headless 프롬프트 위험을 고지해야 함.
- **1Password CLI 백엔드** — `op read` 참조만 저장. 로그인·오프라인 실패 처리 필요.
- **`shell-init`** — 셸 통합(프롬프트 표시, 자동완성).
- **프로필 메모(`add --note`)** — 등록 시 사용자가 적은 계정 힌트를 저장해 `list`·`verify`에
  표시. 위 "알려진 제약"의 실질적 보완책이지만, 평문 저장 대상이 늘어나므로 별도 설계 필요.
- 보안 백엔드 실패 시 평문 파일로 조용히 강등하는 자동 fallback은 **넣지 않습니다.**

## 라이선스

MIT
