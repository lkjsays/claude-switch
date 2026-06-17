# claude-switch

> 결론: 이 실험은 **실효성이 낮아 중단**한다.

`claude-switch`는 Claude Code의 여러 OAuth 계정을 빠르게 전환해서 사용량 제한을 우회/분산할 수 있는지 확인하기 위한 macOS용 실험 CLI였다.

## 실험 결론

처음 가정은 다음과 같았다.

- 계정별 OAuth 토큰/설정을 파일로 보관한다.
- 필요할 때 활성 credentials와 `~/.claude.json`을 바꿔치기한다.
- 여러 계정을 번갈아 쓰면 Claude Code 사용 가능 시간이 늘어날 수 있다.

하지만 실제 사용 결과, **토큰/사용 가능 상태가 생각보다 빠르게 회복**되어 계정을 계속 바꿔가며 쓰는 운영 방식의 이득이 크지 않았다. 반대로 다음 비용이 생겼다.

- 계정별 토큰/설정 관리 부담
- Keychain, `~/.claude/.credentials.json`, `~/.claude.json` 간 상태 불일치 가능성
- Claude Code 쪽 인증 동작 변경에 취약함
- 잘못 전환했을 때 원인 파악이 번거로움

따라서 이 저장소는 더 이상 적극적으로 개선하지 않고, **Claude Code OAuth 전환 실험 기록**으로 남긴다.

## 현재 이 PC 정리 현황

점검일: 2026-06-17

### 저장소

- 위치: `/Users/kijeonglee/Projects/claude-switch`
- 브랜치: `main`
- 원격 저장소: `git@github-lkjsays:lkjsays/claude-switch.git`
- 현재 HEAD: `ca691ed`

### 제거 실행 결과

`./uninstall.sh --yes`로 제거를 실행했고, 아래 항목이 모두 정리되었음을 확인했다.

- `/Users/kijeonglee/.local/bin/claude-switch`: 없음
- `/opt/homebrew/bin/claude-switch`: 없음
- `/usr/local/bin/claude-switch`: 없음
- `claude-switch` 명령: PATH에서 찾을 수 없음
- `/Users/kijeonglee/.claude/.credentials.json`: 없음
- `/Users/kijeonglee/.claude-accounts`: 없음
- `/Users/kijeonglee/.claude-homes`: 없음
- Keychain `Claude Code-credentials`: 없음

다시 Claude Code를 사용하려면 `claude /login`으로 재로그인하면 된다.

## 정리 방법

간단히 정리하려면 저장소에서 제공하는 제거 스크립트를 실행한다.

```bash
./uninstall.sh
```

토큰/프로필 삭제 확인 질문 없이 전부 제거하려면:

```bash
./uninstall.sh --yes
```

프로필 백업은 남기고 실행 파일과 활성 credentials/Keychain 항목만 제거하려면:

```bash
./uninstall.sh --keep-accounts
```

수동으로 지우려면 아래 순서대로 실행한다.

```bash
rm -f ~/.local/bin/claude-switch
rm -f ~/.claude/.credentials.json
rm -rf ~/.claude-accounts
rm -rf ~/.claude-homes
security delete-generic-password -s "Claude Code-credentials"
```

다시 Claude Code를 사용하려면 재로그인한다.

```bash
claude /login
```

## 원래 동작 원리

```text
~/.claude-accounts/
  .current
  personal.json
  personal.config.json
  office.json
  office.config.json
  ...

~/.claude/.credentials.json ← copy of ~/.claude-accounts/<active>.json
~/.claude.json              ← copy of ~/.claude-accounts/<active>.config.json
```

Claude Code가 Keychain 대신 파일 기반 credentials를 읽는 동작을 이용해 계정 전환을 시도했다.

## 라이선스

MIT
