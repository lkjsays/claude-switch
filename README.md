# claude-switch

macOS에서 Claude Code의 여러 OAuth 계정을 빠르게 전환하는 CLI.

## 왜?

기존 도구(`aisw`, `claude-account` 등)는 macOS Keychain을 갈아끼우는 방식이라:

- **백그라운드/원격 호출에서 hang** — Keychain 권한 프롬프트가 GUI로 떠야 하는데 응답할 수 없음
- **토큰 refresh마다 ACL 재요청** — "항상 허용"이 안정적으로 동작 안 함
- **계정 정보 캐시 불일치** — `~/.claude.json`의 `oauthAccount` 객체가 따로 캐시돼서 헤더 표시/청구 추적이 꼬임

`claude-switch`는:
- Keychain을 **완전히 우회** — 토큰을 파일로 저장하고 symlink만 갈아끼움
- 계정별 `~/.claude.json` 스냅샷도 함께 관리
- 매 전환마다 토큰의 실제 계정 정보를 API에서 fresh fetch → 절대 안 꼬임
- 0.5초 내 전환, Hermes/스크립트/SSH에서도 동일하게 동작

## 동작 원리

```
~/.claude-accounts/
  .current                    # 활성 프로필 이름
  personal.json               # OAuth credentials (토큰)
  personal.config.json        # ~/.claude.json 스냅샷 (oauthAccount 포함)
  office.json
  office.config.json
  ...

~/.claude/.credentials.json → ~/.claude-accounts/<active>.json   (symlink)
~/.claude.json              ← copy of ~/.claude-accounts/<active>.config.json
```

Claude Code는 Keychain 항목이 없으면 `~/.claude/.credentials.json` 파일을 fallback으로 읽는 동작이 있음. 이 도구는 Keychain 항목을 처음 한 번 삭제한 뒤로는 파일만으로 동작.

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/lkjsays/claude-switch/main/claude-switch \
  -o ~/.local/bin/claude-switch
chmod +x ~/.local/bin/claude-switch
```

`~/.local/bin`이 `$PATH`에 있어야 함.

## 사용법

### 계정 추가

```bash
claude /login                  # 브라우저에서 로그인
# Ctrl+C 또는 /exit
claude-switch add personal     # Keychain 값 → 파일로 추출 + Keychain 삭제
```

여러 계정 등록할 때는 반복:

```bash
claude /login
claude-switch add office

claude /login
claude-switch add team-enterprise
```

### 전환

```bash
claude-switch                  # 현재 활성 프로필 표시
claude-switch --list           # 전체 목록
claude-switch personal         # 즉시 전환 (다음 claude 호출부터 새 계정 사용)
```

### 기타

```bash
claude-switch add <name> <path>   # 외부 credentials.json 파일에서 등록
claude-switch remove <name>       # 프로필 삭제 (활성 프로필은 불가)
```

## 주의사항

- **현재 실행 중인 `claude` 세션엔 영향 없음**. 다음 호출부터 새 계정 사용.
- `claude /login` 직후 `claude-switch add <name>` 호출 전에 또 `claude /login`을 하면 Keychain이 덮어써짐. 항상 **login 1번 → add 1번** 순서.
- `oauthAccount` fresh fetch는 `https://api.anthropic.com/api/oauth/profile` 호출이 필요. 네트워크 실패 시 silent fail (로컬 데이터는 그대로).

## 요구사항

- macOS
- bash
- python3 (oauthAccount fresh fetch에만 사용)
- `claude` CLI

## 라이선스

MIT
