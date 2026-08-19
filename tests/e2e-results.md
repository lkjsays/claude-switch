# v2.0.0 릴리스 게이트 — 수동 E2E 실행 기록

**실행일:** 2026-08-19
**대상:** `claude-switch` v2.0.0 (HEAD `1497ca9`, 설치본과 저장소 동일)
**목적:** `CHANGELOG.md`의 `[Unreleased]`를 `[2.0.0]`으로 확정하고 `v2.0.0` 태그를 끊기 위한 마지막 게이트.

`tests/e2e.md`의 절차를 **이미 등록된 실제 프로필**로 수행하는 버전입니다.
새 토큰 발급·revoke가 필요한 단계는 §B6 하나로 몰아뒀고, **릴리스를 막고 있는 관측(§B2)은
새 토큰 없이 명령 하나로 끝납니다.**

> **에이전트 대행 금지 (`tests/e2e.md:4-6`)**
> Part B는 실제 자격증명 접근·브라우저 승인·TTY·터미널 2개가 필요해 사람이 직접 해야 합니다.
> Part A/C는 자격증명을 읽지 않는 단계라 Claude가 수행했습니다.

## 계정 매핑

| 역할 | 프로필 | 지문 |
|---|---|---|
| 계정 A | `personal` (기본) | `fp:4c72268e` |
| 계정 B | `office` | `fp:ec596f37` |
| 예비 계정 | `team` | `fp:bd69c541` |
| 신규 등록 검증용 | `e2e-a` (§B6에서 생성 → §C1에서 삭제) | — |

> 지문이 다른 것은 **토큰이 다르다**는 뜻일 뿐 **계정이 다르다**는 보장이 아닙니다.
> 같은 계정에서 두 번 발급한 setup-token도 지문이 다릅니다. 실제 계정 분리는 §B3에서 확인합니다.

---

## Part A — Claude 수행 완료 (자격증명 미접촉)

### A1. 사전 스냅샷 (`e2e.md` §1)

```
/Users/kjlee/.claude-accounts                 → 없음
/Users/kjlee/.claude/.credentials.json        mode=600 mtime=1786717940 size=322
/Users/kjlee/.claude-homes                    → 없음
/Users/kjlee/.claude-switch/isolated          → 없음
```

위 값이 §C2 비교의 기준입니다(세션 임시 파일은 사라지므로 이 문서에 직접 기록).
Keychain 조회 명령은 실행하지 않았습니다.

`isolated`가 없다는 것은 **이 스냅샷 시점까지 `--isolate`가 한 번도 쓰이지 않았다**는
뜻입니다(과거 E2E 수행 여부의 약한 근거). §B5 이후에는 존재하는 것이 정상이며,
`.credentials.json`과 달리 §C2의 불변 비교 대상이 아닙니다.

참고: 계획서 §1 시점에는 `~/.claude/.credentials.json`이 없었지만 현재는 존재합니다
(공식 CLI가 만든 것). v2가 건드리지 않는지 §C2에서 mtime·size로 검증합니다.

### A2. `--bare` 차단 (`e2e.md` §7) — ✅ 통과

소스 확인: `--bare` 가드(`claude-switch:542-548`)가 `read_token_checked`(`:551`)와
`exec`(`:594`)보다 앞에 있어 토큰을 읽지 않고 종료합니다.

| 실행 | 종료코드 | 판정 |
|---|---|---|
| `claude-switch run personal -- --bare -p hi` | 2 | ✅ |
| `claude-switch personal -- --bare -p hi` (축약형) | 2 | ✅ |
| `claude-switch run personal -- -p hi --bare` (후위) | 2 | ✅ |

`claude`는 실행되지 않았습니다.

### A3. 토큰 누출 검사 (`e2e.md` §8) — ✅ 통과

| 검사 | 결과 |
|---|---|
| `ps -eo args` 내 `sk-ant` | 없음 |
| 부모 셸 `CLAUDE_CODE_OAUTH_TOKEN` 잔류 | 없음 |
| `~/.claude-switch` 내 `tokens/` 밖 토큰 원문 | 없음 |
| 로그 파일 | 존재 자체가 없음 |
| `git status --short` | 비어 있음 |
| 추적 파일 내 실토큰 (`git grep sk-ant`) | 없음 |
| `~/.zsh_history` / `~/.bash_history` 내 `sk-ant` | 0회 / 0회 |

저장소 권한 전수 확인:

```
drwx------ ~/.claude-switch
-rw------- ~/.claude-switch/config
drwx------ ~/.claude-switch/tokens
-rw------- ~/.claude-switch/tokens/{personal,office,team}.token
```

예상 밖 파일 없음. (`tokens/*.token`은 토큰 원문을 담는 정상 보관처이므로 누출이 아닙니다.)

### A4. 자동 검사 (참고)

`bats tests/` 166/166 통과 · `shellcheck -S warning` 경고 0 · `doctor` 전 항목 OK ·
CI success. 단 bats는 `tests/stubs/claude` 스텁으로 돌기 때문에 **실제 CLI 출력 형식은
검증하지 못합니다.** 그게 §B2의 존재 이유입니다.

---

## Part B — 사람이 수행 (오빠)

### B1. 사전 확인

```bash
claude --version          # 2.1.233 확인됨
claude-switch doctor      # ✅ doctor OK 확인됨
```

- [ ] 위 두 개 여전히 정상

### B2. ⭐ `verify` 출력 형식 관측 — ✅ 수행 완료 (2026-08-19)

실제 출력:

```
프로필    : personal
토큰 파일 : /Users/kjlee/.claude-switch/tokens/personal.token (권한 600)
지문      : fp:4c72268e
인증 상태 :
  Auth token: CLAUDE_CODE_OAUTH_TOKEN
실제 호출 :
  ✅ OAuth 모델 요청 성공
```

**판정: `Email`/`Organization` 줄이 나오지 않습니다.**
setup-token 주입 상태에서 `claude auth status --text`는 인증원 한 줄만 출력합니다.
전역 Pro 인증에서는 `Login method:` / `Organization:` / `Email:` 3줄이 나오므로,
**인증 방식에 따라 출력이 다릅니다.**

- [x] 토큰 파일 권한 `600` 표시
- [x] 실제 모델 요청 성공
- [x] 토큰 원문 없음

| 문서 | 판정 |
|---|---|
| `README.md:148-149`, `:180-183` (이메일·조직 표시 안 함) | ✅ **정확함** |
| `CHANGELOG.md:42-43` (`auth status --text`로 계정·조직 확인) | ❌ **틀림** |
| `tests/e2e.md:55` (`계정 확인` 아래 이메일·조직) | ❌ **틀림** (라벨도 `인증 상태 :`가 맞음) |
| `tests/e2e.md:87` (`verify`가 계정 B의 이메일·조직 표시) | ❌ **틀림** |

### B2-a. 파급: 계정 정체성은 CLI로 확인 불가 — ✅ 결론 확정

`--json`도 계정 정보를 담지 않습니다. setup-token 주입 시 실제 출력:

```json
{ "loggedIn": true, "authMethod": "oauth_token", "apiProvider": "firstParty" }
```

전역 Pro 인증과 비교:

| 키 | 전역 `/login` | setup-token |
|---|---|---|
| `email` | 있음 (본인 계정) | **없음** |
| `orgId` / `orgName` | 있음 | **없음** |
| `subscriptionType` | `pro` | **없음** |
| `authMethod` | `claude.ai` | `oauth_token` |

`claude --help`의 전체 서브커맨드(`agents`/`auth`/`doctor`/`gateway`/`import`/`install`/
`mcp`/`plugin`/`project`/`setup-token`/`ultrareview`/`update`)에도 계정을 조회하는 표면이
없습니다.

**결론: `CLAUDE_CODE_OAUTH_TOKEN` 인증에서 도구가 계정 정체성을 확인할 방법은 없습니다.**
`probe_auth`를 `--json`으로 바꿔도 얻는 정보가 없어 소스는 수정하지 않습니다.
계정 확인 지점은 `setup-token`의 브라우저 승인 화면뿐입니다.

**조치 (문서만, 소스 무변경):**

| 파일 | 수정 |
|---|---|
| `CHANGELOG.md:42-43` | 계정·조직 확인 주장 삭제, 인증원+실제 요청으로 정정 |
| `tests/e2e.md` §3 | `계정 확인` → `인증 상태 :`, 이메일·조직 대조 삭제, 제약 명시 |
| `tests/e2e.md` §5 | 이메일·조직 비교 → 지문 상이 + 각각 요청 성공 |
| `tests/e2e.md` 합격 기준 | 검증 불가 항목을 검증 가능한 속성으로 재정의 |
| `README.md` | "알려진 제약" 절 추가, 후속 과제에 `add --note` 등재 |

### B3. 두 계정 교차 — `e2e.md` §5

```bash
claude-switch verify personal
claude-switch verify office
claude-switch verify personal     # 다시 A — 섞이지 않았는지
```

**먼저 계정 분리 자체를 확인해야 합니다.**

- [x] ~~`personal`과 `office`가 서로 다른 이메일·조직으로 표시됨~~ → **확인 불가**
      (둘 다 `Auth token: CLAUDE_CODE_OAUTH_TOKEN` 한 줄. §B2-a 참조)
- [x] 두 프로필 모두 실제 OAuth 모델 요청 성공 → 토큰 2개 다 유효하고 살아 있음

> 같게 나오면 `office`를 `team`으로 바꿔 다시 확인하세요.
> **세 프로필이 모두 같은 계정이면 §B3는 기존 프로필로 충족할 수 없고, 실제 두 번째
> 계정이 필요합니다.** 이 경우 여기서 멈추고 알려주세요.

- [ ] 재실행한 `personal`이 여전히 personal (오염 없음)

```bash
claude-switch run personal -- -p "계정 이메일만 한 줄로 출력"
claude-switch run office   -- -p "계정 이메일만 한 줄로 출력"
```

- [ ] 두 출력이 서로 다름

터미널 2개를 동시에 열고 각각 다른 프로필로:

- [ ] 동시 실행이 서로 영향 없음 (v1에서 불가능했던 지점)

### B4. 실행 — `e2e.md` §4

```bash
claude-switch run personal -- -p "다른 설명 없이 OK만 출력"
echo "종료코드: $?"

echo "질문: 1+1" | claude-switch personal -- -p    # stdin 파이프
```

- [ ] `-p` 실행 성공, 종료코드 0
- [ ] stdin 파이프 정상

인터랙티브:

```bash
claude-switch personal
```

- [x] TTY 정상 — 인터랙티브 화면이 실제로 떴음을 사용자가 확인 (2026-08-19)
- [x] 종료 후 셸로 정상 복귀 (대체 화면 버퍼를 쓰므로 스크롤백에 TUI가 남지 않는 것이 정상)
- [ ] `Ctrl-C`가 claude에 전달돼 claude가 종료됨 (래퍼만 죽고 claude가 남지 않음)
- [ ] 종료 후 셸로 정상 복귀

### B5. `--isolate` — `e2e.md` §6

```bash
claude-switch run --isolate office -- -p "OK"
ls -ld ~/.claude-switch/isolated/office
```

- [ ] 격리 실행 성공 (첫 실행은 신뢰 프롬프트·온보딩 있을 수 있음)
- [ ] `isolated/office` 권한이 `0700`
- [ ] 격리 실행 후에도 `~/.claude` 쪽 설정·세션 기록 그대로

> **`~/.claude-switch/isolated/office`는 이후 계속 남습니다.** `remove`도 격리 설정을
> 일부러 보존합니다(`claude-switch:429-432`). 삭제는 선택이며, 지우려면
> `rm -rf ~/.claude-switch/isolated/office`. A1 스냅샷에 `isolated`가 없다고 적힌 것과
> 달라지는 게 정상입니다.

### B6. 신규 등록 경로 검증 (새 토큰 1회) — `e2e.md` §2

이 단계만 새 토큰이 필요합니다. §B2와 달리 **릴리스를 막지 않으므로 나중에 해도 됩니다.**
검증하는 것은 (a) 비표시 입력 붙여넣기 경로와 (b) 합격 기준의 "브라우저 승인 화면에서
이메일·조직 직접 확인" 항목입니다.

```bash
claude setup-token            # 브라우저에서 계정 승인 → 토큰 출력
claude-switch add e2e-a       # 비표시 입력에 붙여넣기
claude-switch verify e2e-a
```

- [ ] 붙여넣는 동안 화면에 아무것도 표시되지 않음
- [ ] 성공 출력에 토큰 원문 없이 `fp:xxxxxxxx` 지문만 나옴
- [ ] **브라우저 승인 화면에서 이메일·조직을 직접 확인**했음
- [ ] `verify e2e-a`가 승인 화면에서 본 계정과 일치

승인 화면에서 본 계정: `________________`

### B7. 스크롤백 정리 (§B6를 했다면)

- [ ] `setup-token` 출력이 남은 스크롤백 삭제 (`Cmd-K` 또는 `clear && printf '\e[3J'`)
- [ ] 클립보드 비움

---

## Part C — 마무리 (Claude 수행 예정)

### C1. 정리 (§B6를 했다면)

```bash
claude-switch remove e2e-a
```

- [ ] **§B6에서 발급한 e2e-a 토큰을 Anthropic 콘솔에서 revoke** ← 사람만 가능,
      안 하면 유효한 1년 토큰이 남습니다

`isolated/e2e-a`는 Part B에서 `--isolate`를 `e2e-a`로 돌리지 않으므로 생기지 않습니다.

### C2. 사후 스냅샷 — ✅ 통과 (기준 정정 후)

| 대상 | A1 | C2 | 판정 |
|---|---|---|---|
| `~/.claude-accounts` | 없음 | 없음 | ✅ 불변 |
| `~/.claude-homes` | 없음 | 없음 | ✅ 불변 |
| 전역 `email` | (기록됨) | 동일 | ✅ 동일 |
| 전역 `orgId` | (기록됨) | 동일 | ✅ 동일 |
| 전역 `subscriptionType` | `pro` | `pro` | ✅ 동일 |
| `.credentials.json` mtime | `2026-08-14 23:32:20` | `2026-08-19 14:40:46` | ⚠️ 변경 — 아래 참조 |

**`.credentials.json` mtime 변화는 `claude-switch`가 원인이 아닙니다.**

원인 규명:

- 소스에 `credential` 문자열 **0회**, `~/.claude/` 경로 **0회**
- 순수성 테스트 7~13 전부 통과 (소스 정적 검사)
- size 322 · mode 600 동일 → 구조 그대로, 값만 갱신된 형태
- 전역 `email`·`orgId`·`orgName`·`subscriptionType` 모두 동일 → **같은 계정**
  (공개 저장소이므로 실제 값은 기록하지 않음. 대조는 실행 시점에 수행함)
- 공식 CLI가 전역 `claude.ai` 인증의 OAuth 토큰을 주기적으로 갱신하며 이 파일을
  재작성합니다. 이 세션에서 실행한 `claude auth status`·`claude --help`, 그리고 동시에
  돌고 있던 다른 Claude Code 세션이 트리거입니다.

**→ `e2e.md` §10의 판정 기준 자체가 잘못 설계돼 있었습니다.** `.credentials.json`을 mtime
불변 대상으로 둔 것은 `~/.claude.json`을 이미 제외한 것과 같은 이유로 성립하지 않습니다
(§3·§5와 동일 유형의 문서 결함). 기준을 다음으로 교체했습니다:

- mtime 비교 대상 → v1 저장소(`~/.claude-accounts`·`~/.claude-homes`)만
- 전역 인증 검증 → `auth status --json`의 계정 필드 값 비교
- `claude-switch`의 미접근 → 순수성 테스트가 정적 보장 (mtime으로 판정하지 않음)

### C3. 릴리스

1. §B2 판정에 따라 문서 모순 수정
2. `e2e.md:55`의 `계정 확인` → `인증 상태` 라벨 수정
3. 이 파일의 체크박스 채우기
4. `CHANGELOG.md` `[Unreleased] — 2.0.0 준비 중` → `[2.0.0] — 2026-08-19`
5. `git tag -a v2.0.0` + `git push --tags`

---

## 합격 기준 (`e2e.md:163-171`)

| 기준 | 상태 |
|---|---|
| 브라우저 승인 화면에서 이메일·조직 직접 확인 | ⬜ B6 (선택) |
| 프로필마다 OAuth 인증원 + 실제 모델 요청 성공 | ✅ B2/B3 (personal·office) |
| 프로필별 지문 상이 (토큰 분리) | ✅ B3 `fp:4c72268e` vs `fp:ec596f37` |
| 번갈아 실행 시 상호 간섭 없음 | ✅ B3 |
| ~~계정 정체성 CLI 확인~~ | ➖ **불가 — 문서화된 제약으로 전환** (B2-a) |
| 인터랙티브 TTY 정상 | ✅ B4 |
| `-p`·stdin·종료코드·`Ctrl-C` | ⬜ B4 잔여 |
| `--bare`가 exit 2로 차단 | ✅ A2 |
| `ps`·로그·히스토리·Git에 토큰 원문 없음 | ✅ A3 |
| v1 저장소 불변 + 전역 계정 동일 | ✅ C2 |
| 순수성 테스트에 Keychain·`.claude.json` 접근 없음 | ✅ A4 (bats 138-144) |
| 테스트 토큰 revoke | ➖ B6를 수행한 경우에만 필요 |
