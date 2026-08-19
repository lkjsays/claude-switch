# 수동 E2E 절차

자동 테스트(`bats tests/`)는 임시 `$HOME`, 합성 토큰, 가짜 `claude` 스텁만 씁니다.
실제 계정·실제 토큰으로 동작을 확인하는 이 절차는 **사람이 직접** 실행합니다.
자동화·에이전트가 대신 실행하면 안 됩니다(`claude setup-token`은 브라우저 승인이 필요하고,
실제 자격증명 파일에 접근하게 됩니다).

소요 시간 약 10분. 계정 두 개(예: 개인, 업무)와 브라우저 로그인이 필요합니다.

## 0. 사전 조건

```bash
claude --version                 # 2.1.219+ (setup-token 지원 버전)
command -v claude-switch
claude-switch doctor             # 저장소 진단이 OK 인지 먼저 확인
```

`doctor`가 v1 잔재를 지적하면 먼저 `claude-switch migrate-check --acknowledge`로 확인합니다.

## 1. 사전 스냅샷 (불변 확인용)

v2 래퍼가 v1 저장소를 건드리지 않고 전역 계정이 바뀌지 않는지 전후 상태를 기록합니다.

**mtime 비교 대상은 v1 저장소뿐입니다.** 공식 `claude`가 관리하는 두 파일은 제외합니다:

- `~/.claude.json` — 기본 공유 모드에서 자식 `claude`가 메타데이터를 갱신합니다.
- `~/.claude/.credentials.json` — 공식 CLI가 **OAuth 토큰을 주기적으로 갱신하며 재작성**합니다.
  `claude auth status` 실행이나 다른 Claude Code 세션만으로도 mtime이 바뀌므로, mtime을
  불변 기준으로 쓰면 `claude-switch`와 무관하게 실패합니다.

이 두 파일에 대해 검증할 속성은 mtime이 아니라 **계정 정체성이 그대로인지**입니다.
`claude-switch`가 두 파일에 아예 접근하지 않는다는 사실은 자동 순수성 테스트가 소스를
정적으로 검사해 보장합니다.

```bash
# v1 저장소: mtime 비교 대상
stat -f '%N mode=%Lp mtime=%m size=%z' \
  ~/.claude-accounts ~/.claude-homes 2>&1 | tee /tmp/cs-before.txt

# 전역 계정 정체성: 값 비교 대상
claude auth status --json | tee /tmp/cs-auth-before.json
```

Keychain 값이나 항목을 조회하는 명령은 실행하지 않습니다. v2 실행 코드에 Keychain 접근
명령이 없다는 사실은 자동 순수성 테스트로 검증합니다.

## 2. 토큰 발급과 등록 (계정 A)

```bash
claude setup-token               # 브라우저에서 계정 A·조직 승인 → 토큰 출력
claude-switch add e2e-a          # 비표시 입력에 붙여넣기 (화면에 표시되지 않음)
```

확인 사항:

- 붙여넣는 동안 화면에 아무것도 표시되지 않는다.
- 성공 출력에 토큰 원문이 아니라 `fp:xxxxxxxx` 지문만 나온다.

## 3. 계정 확인

```bash
claude-switch verify e2e-a
```

확인 사항:

- 토큰 파일 권한이 `600`으로 표시된다.
- `인증 상태 :` 아래에 `Auth token: CLAUDE_CODE_OAUTH_TOKEN`이 나온다(인증원이 OAuth 토큰).
- `실제 호출 :` 아래에 모델 요청 성공이 표시된다.
- 어디에도 토큰 원문이 없다.

> **이메일·조직은 여기서 확인할 수 없습니다.** `CLAUDE_CODE_OAUTH_TOKEN` 인증에서
> `claude auth status`는 계정 정체성을 해석하지 않습니다(`--text`는 인증원 한 줄,
> `--json`은 `loggedIn`·`authMethod`·`apiProvider`만). 계정 확인 지점은 §2의 브라우저
> 승인 화면뿐입니다.

## 4. 실행

```bash
claude-switch run e2e-a -- -p "다른 설명 없이 OK만 출력"
echo "종료코드: $?"
```

인터랙티브도 확인합니다.

```bash
claude-switch e2e-a              # 축약형, 인터랙티브
```

확인 사항:

- 인터랙티브 UI가 정상적으로 뜨고 TTY가 살아 있다(방향키·색상).
- `Ctrl-C`가 claude에게 전달되어 claude가 종료된다(래퍼만 죽고 claude가 남지 않는다).
- 종료 후 셸로 정상 복귀한다.

## 5. 두 번째 계정 교차 실행

```bash
claude setup-token               # 이번에는 계정 B 로 승인
claude-switch add e2e-b
claude-switch verify e2e-b
```

확인 사항:

- `verify e2e-b`의 지문이 `e2e-a`와 **다르다**(토큰이 분리돼 있다).
- `e2e-b`도 실제 모델 요청이 성공한다(토큰이 유효하다).
- 다시 `claude-switch verify e2e-a`를 실행해도 지문이 그대로다(덮어써지지 않았다).

`verify` 출력만으로는 두 프로필이 서로 다른 계정인지 **판별할 수 없습니다**(위 §3의 제약).
계정 정체성은 §2의 브라우저 승인 화면에서 프로필마다 한 번 확인하는 것이 유일한 방법입니다.

같은 터미널에서 번갈아 실행합니다.

```bash
claude-switch run e2e-a -- -p "계정 이메일만 한 줄로 출력"
claude-switch run e2e-b -- -p "계정 이메일만 한 줄로 출력"
```

두 터미널을 동시에 열어 각각 다른 프로필로 실행해도 서로 영향을 주지 않는지 확인합니다.

## 6. `--isolate`

```bash
claude-switch run --isolate e2e-b -- -p "OK"
ls -ld ~/.claude-switch/isolated/e2e-b     # 0700 인지 확인
```

확인 사항:

- 격리 실행이 성공한다(첫 실행에서 신뢰 프롬프트·온보딩을 다시 거칠 수 있음).
- 격리 실행 후에도 `~/.claude` 쪽 설정과 세션 기록이 그대로다.

## 7. `--bare` 차단

```bash
claude-switch run e2e-a -- --bare -p hi
echo "종료코드: $?"                        # 2 여야 하고, claude 가 실행되지 않아야 함
```

## 8. 토큰 누출 검사

실행 중인 터미널을 하나 열어 둔 상태에서 다른 터미널로 확인합니다.

```bash
ps -eo args | grep -i 'sk-ant' | grep -v grep      # 아무것도 나오면 안 됨
grep -r 'sk-ant' ~/.claude-switch/*.log 2>/dev/null || true
git -C /path/to/claude-switch status --short       # 토큰 파일이 잡히면 안 됨
```

셸 히스토리와 스크롤백도 확인합니다.

```bash
grep -c 'sk-ant' ~/.zsh_history 2>/dev/null || true
```

`setup-token` 출력이 스크롤백에 남아 있으면 지웁니다(`Cmd-K` 또는 `clear && printf '\e[3J'`).

## 9. 정리

```bash
claude-switch remove e2e-a
claude-switch remove e2e-b
rm -rf ~/.claude-switch/isolated/e2e-a ~/.claude-switch/isolated/e2e-b
```

`remove`는 로컬 파일만 지웁니다. **테스트용으로 발급한 토큰은 Anthropic 쪽에서 직접
revoke하세요.** 그대로 두면 유효한 1년 토큰이 남습니다.

## 10. 사후 스냅샷 (불변 확인)

```bash
stat -f '%N mode=%Lp mtime=%m size=%z' \
  ~/.claude-accounts ~/.claude-homes 2>&1 | tee /tmp/cs-after.txt
diff /tmp/cs-before.txt /tmp/cs-after.txt && echo "✅ v1 저장소 불변"

claude auth status --json | tee /tmp/cs-auth-after.json
diff /tmp/cs-auth-before.json /tmp/cs-auth-after.json && echo "✅ 전역 계정 동일"
```

확인 사항:

- v1 `diff`가 비어 있다.
- 전역 `auth status`의 `email`·`orgId`·`orgName`·`subscriptionType`이 그대로다
  (= v2 사용 전에 쓰던 계정으로 그냥 `claude`를 실행하면 여전히 그 계정이다).
- `~/.claude/.credentials.json`과 `~/.claude.json`의 **mtime 변화는 실패가 아닙니다.**
  공식 CLI의 토큰 갱신·메타데이터 갱신으로 바뀝니다. `claude-switch`가 접근하지 않는다는
  것은 순수성 테스트(`tests/unit.bats`)가 보장합니다.

## 합격 기준

- [ ] 브라우저 승인 화면에서 프로필별 이메일·조직을 직접 확인 (**계정 정체성의 유일한 확인 지점**)
- [ ] 프로필마다 `verify`의 OAuth 인증원 확인과 실제 모델 요청 성공
- [ ] 프로필별 지문이 서로 다름 (토큰 분리)
- [ ] 두 프로필을 번갈아·동시에 실행해도 각각 배너와 요청 성공이 정상 (상호 간섭 없음)
- [ ] 인터랙티브·`-p`·stdin 파이프·종료코드·`Ctrl-C` 정상
- [ ] `--bare`가 exit 2로 차단됨
- [ ] `ps`·로그·히스토리·Git 어디에도 토큰 원문 없음
- [ ] `~/.claude-accounts`·`~/.claude-homes` 불변, 전역 `auth status`의 계정 정보 동일
- [ ] 자동 순수성 테스트에서 `~/.claude.json`·Keychain 직접 접근 코드 없음
- [ ] 테스트 토큰 revoke 완료
