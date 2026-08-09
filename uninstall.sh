#!/bin/bash
# claude-switch v2 제거 스크립트.
#
# 이 스크립트가 건드리는 것은 딱 두 가지다.
#   1) 이 도구가 설치한 claude-switch 실행 파일
#   2) --purge 를 명시했을 때에 한해 ~/.claude-switch 저장소
#
# 그 밖의 어떤 전역 인증 상태도 읽지 않고, 바꾸지 않고, 지우지 않는다.
# claude-switch v2 는 전역 인증을 건드리지 않으므로 제거 과정에서도 되돌릴 것이 없다.
# 기본 실행은 저장소를 보존한다. 프로필과 토큰은 사용자가 명시적으로 지워야 한다.
#
# 사용법:
#   ./uninstall.sh                 설치본만 제거, 저장소는 보존
#   ./uninstall.sh --purge         저장소까지 제거(삭제 전 확인)
#   ./uninstall.sh --purge --yes   확인 없이 저장소까지 제거

set -euo pipefail

PURGE=0
ASSUME_YES=0
STORE_DIR=""

# 소유권 판별 기준. claude-switch v2 소스에 있는 설치 서명 줄과 정확히(줄 전체가)
# 일치해야만 이 도구의 설치본으로 본다. 본문에 'claude-switch' 라는 낱말이 있다는
# 이유만으로는 절대 제거하지 않는다.
OWNED_SIGNATURE_LINE='CLAUDE_SWITCH_INSTALL_SIGNATURE="claude-switch-install-signature/v2/6f1a9c0b4d7e"'

# --------------------------------------------------------------------- 유틸

die() {
  local code="$1"
  shift
  printf '%s\n' "$@" >&2
  exit "$code"
}

say() {
  printf '%s\n' "$*"
}

usage() {
  cat <<'EOF'
claude-switch 제거

사용법:
  ./uninstall.sh                 설치된 claude-switch 명령만 제거(저장소 보존)
  ./uninstall.sh --purge         ~/.claude-switch 저장소까지 제거(확인 후)
  ./uninstall.sh --purge --yes   확인 없이 저장소까지 제거

옵션:
  --purge         프로필과 토큰이 든 ~/.claude-switch 를 삭제한다
  -y, --yes       --purge 의 삭제 확인을 생략한다
  -h, --help      이 도움말

기본 실행은 프로필과 토큰을 지우지 않는다. 삭제는 --purge 로만 일어난다.
전역 Claude 인증 상태는 어떤 경우에도 읽거나 바꾸지 않는다.

명령 검색 위치는 BIN_DIR, PREFIX 로 조정하거나 CLAUDE_SWITCH_BIN_DIRS
(콜론으로 구분한 목록)로 통째로 지정할 수 있다.
EOF
}

# 저장소 경로를 정하기 전에 HOME 이 쓸 만한 값인지 확인한다.
require_sane_home() {
  if [ -z "${HOME:-}" ]; then
    die 1 "❌ HOME 이 비어 있습니다." \
      "   저장소 경로를 안전하게 정할 수 없어 중단합니다."
  fi
  case "$HOME" in
    /)
      die 1 "❌ HOME 이 루트(/)입니다." \
        "   저장소 경로를 안전하게 정할 수 없어 중단합니다."
      ;;
    /*) ;;
    *)
      die 1 "❌ HOME 이 절대 경로가 아닙니다: $HOME" \
        "   저장소 경로를 안전하게 정할 수 없어 중단합니다."
      ;;
  esac
  STORE_DIR="$HOME/.claude-switch"
}

# ------------------------------------------------------------- 설치본 제거

# 콜론으로 구분한 검색 경로 목록을 만든다.
search_dirs() {
  if [ -n "${CLAUDE_SWITCH_BIN_DIRS:-}" ]; then
    printf '%s' "$CLAUDE_SWITCH_BIN_DIRS"
    return 0
  fi

  local list=""
  if [ -n "${BIN_DIR:-}" ]; then
    list="$list:$BIN_DIR"
  fi
  if [ -n "${PREFIX:-}" ]; then
    list="$list:$PREFIX/bin"
  fi
  list="$list:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
  printf '%s' "${list#:}"
}

# 이 도구가 설치한 파일인지 판별한다. 이름만 같은 남의 스크립트는 지우지 않는다.
# 판별 기준은 설치 서명 줄의 정확한 일치(-F -x)다. 낱말 포함 검사로는 부족하다.
is_owned_command() {
  local path="$1" first=""
  [ -f "$path" ] || return 1
  IFS= read -r first <"$path" || first=""
  case "$first" in
    '#!'*sh*) ;;
    *) return 1 ;;
  esac
  grep -q -I -F -x -e "$OWNED_SIGNATURE_LINE" "$path" 2>/dev/null || return 1
  return 0
}

# 검색 경로로 받아들일 수 있는 형태인지 본다. 상대 경로와 '..' 는 어디를 가리키는지
# 확정할 수 없으므로 해석하지 않고 거부한다.
is_safe_search_dir() {
  local dir="$1"
  case "$dir" in
    /*) ;;
    *) return 1 ;;
  esac
  case "/$dir/" in
    */../*) return 1 ;;
  esac
  return 0
}

# 경로 구성요소 중 심볼릭 링크가 있으면 그 구성요소를 출력하고 0 을 돌려준다.
# 링크를 따라가지 않으므로 대상 파일은 stat 조차 하지 않는다.
first_symlink_component() {
  local path="$1" prefix="" comp saved_ifs="$IFS"
  set -f
  IFS='/'
  for comp in $path; do
    IFS="$saved_ifs"
    set +f
    if [ -n "$comp" ]; then
      prefix="$prefix/$comp"
      if [ -L "$prefix" ]; then
        printf '%s' "$prefix"
        return 0
      fi
    fi
    set -f
    IFS='/'
  done
  IFS="$saved_ifs"
  set +f
  return 1
}

# 검색 경로 목록을 중복 없이 순회하며 경로마다 action 을 호출한다. 경로 목록은
# 콜론으로 구분되므로 줄바꿈이 든 경로도 그대로 넘어간다(임시 파일을 거치지 않는다).
for_each_search_dir() {
  local action="$1" raw dir saved_ifs seen=""
  raw="$(search_dirs)"

  saved_ifs="$IFS"
  set -f
  IFS=':'
  for dir in $raw; do
    IFS="$saved_ifs"
    set +f
    if [ -n "$dir" ]; then
      case ":$seen:" in
        *":$dir:"*) ;;
        *)
          seen="$seen:$dir"
          "$action" "$dir"
          ;;
      esac
    fi
    set -f
    IFS=':'
  done
  IFS="$saved_ifs"
  set +f
  return 0
}

# 검색 경로 하나를 판정한다. 안전하지 않으면 건너뛰지 않고 중단한다. 건너뛰고 exit 0
# 으로 끝내면 설치본이 그대로 남아 있는데도 제거에 성공한 것처럼 보이기 때문이다.
# 존재하지 않는 정상적인 절대 경로는 안전하다(설치본이 없을 뿐이다).
check_search_dir() {
  local dir="$1" link=""

  # 경로 판단이 먼저다. 안전하지 않은 경로는 존재 여부조차 확인하지 않는다.
  if ! is_safe_search_dir "$dir"; then
    die 1 "❌ 명령 검색 경로가 안전하지 않습니다: $dir" \
      "   절대 경로가 아니거나 '..' 가 섞여 있어 어디를 가리키는지 확정할 수 없습니다." \
      "   설치본을 하나도 건드리지 않고 중단합니다." \
      "   CLAUDE_SWITCH_BIN_DIRS 를 '..' 없는 절대 경로로 지정한 뒤 다시 실행하세요."
  fi

  # 검색 경로나 그 상위 구성요소가 심볼릭 링크면 따라가지 않는다. 링크 너머의
  # 파일은 이 도구가 설치한 것이라고 볼 수 없고, 지우면 남의 파일을 지우게 된다.
  if link="$(first_symlink_component "$dir")"; then
    die 1 "❌ 명령 검색 경로에 심볼릭 링크가 있습니다: $dir" \
      "   링크 구성요소: $link" \
      "   링크 너머는 따라가지 않으며, 설치본을 하나도 건드리지 않고 중단합니다." \
      "   CLAUDE_SWITCH_BIN_DIRS 로 링크 없는 실제 경로를 지정한 뒤 다시 실행하세요."
  fi
  return 0
}

# 어떤 것도 지우기 전에 모든 검색 경로를 먼저 검사한다. 앞선 경로를 지운 뒤 뒤에서
# 실패하면 명령이 일부만 남는 어중간한 상태가 되므로, 검사를 통째로 앞으로 당긴다.
preflight_search_dirs() {
  for_each_search_dir check_search_dir
}

remove_command() {
  local dir="$1" path="$1/claude-switch"

  # 경로 안전성은 preflight_search_dirs 가 이미 전부 확인했다. 삭제 직전에 한 번 더
  # 확인해 검사와 삭제 사이에 경로가 바뀐 경우에도 링크를 따라가지 않도록 한다.
  check_search_dir "$dir"

  # 명령 파일 자체가 심볼릭 링크인 경우도 따라가지 않는다.
  if [ -L "$path" ]; then
    say "건너뜀(심볼릭 링크): $path"
    return 0
  fi
  if [ ! -e "$path" ]; then
    say "이미 없음: $path"
    return 0
  fi
  if ! is_owned_command "$path"; then
    say "건너뜀(claude-switch 설치본이 아님): $path"
    return 0
  fi

  rm -f "$path"
  say "제거됨: $path"
  return 0
}

remove_installed_commands() {
  for_each_search_dir remove_command
}

# --------------------------------------------------------------- 저장소 처리

confirm_purge() {
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi

  local answer=""
  say ""
  say "저장소를 삭제하면 등록된 프로필과 토큰이 모두 사라집니다: $STORE_DIR"
  say "삭제한 토큰은 복구할 수 없고, 계정마다 'claude setup-token' 으로 다시 발급해야 합니다."
  printf '정말 삭제할까요? [y/N] '

  # 입력이 없으면(EOF) 삭제하지 않는다. 비대화형에서 조용히 지우는 일은 없다.
  read -r answer || answer=""
  case "$answer" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --purge 로 중단될 조건을 설치본에 손대기 전에 미리 확인한다. 나중에 실패하면
# 명령만 지워지고 저장소는 남는 어중간한 상태가 되므로, 검사를 앞으로 당긴다.
# 저장소가 아직 없는 것은 정상이므로 여기서 막지 않는다.
preflight_purge() {
  # 심볼릭 링크는 대상을 지울 위험이 있으므로 따라가지 않고 거부한다.
  if [ -L "$STORE_DIR" ]; then
    die 1 "❌ 저장소가 심볼릭 링크입니다: $STORE_DIR" \
      "   보안상 따라가지 않습니다. 링크 대상은 그대로 두었습니다." \
      "   설치본도 건드리지 않고 중단합니다." \
      "   필요하면 링크를 직접 확인한 뒤 지우세요."
  fi
  if [ -e "$STORE_DIR" ] && [ ! -d "$STORE_DIR" ]; then
    die 1 "❌ 저장소 경로가 디렉터리가 아닙니다: $STORE_DIR" \
      "   예상하지 못한 상태이므로 손대지 않고 중단합니다." \
      "   설치본도 건드리지 않았습니다."
  fi
}

purge_store() {
  # 여기 오기 전에 preflight_purge 가 링크·비디렉터리를 이미 걸렀다.
  if [ ! -e "$STORE_DIR" ]; then
    say "이미 없음: $STORE_DIR"
    return 0
  fi

  if ! confirm_purge; then
    say "보존됨: $STORE_DIR"
    say "삭제하지 않았습니다."
    return 0
  fi

  rm -rf "$STORE_DIR"
  say "삭제됨: $STORE_DIR"
}

keep_store() {
  if [ -L "$STORE_DIR" ]; then
    say "보존됨(심볼릭 링크): $STORE_DIR"
    return 0
  fi
  if [ ! -e "$STORE_DIR" ]; then
    say "이미 없음: $STORE_DIR"
    return 0
  fi

  say "보존됨: $STORE_DIR"
  say "프로필과 토큰은 그대로 둡니다. 함께 지우려면: ./uninstall.sh --purge"
}

# --------------------------------------------------------------------- main

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge) PURGE=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die 2 "❌ 알 수 없는 옵션: $1" \
        "   './uninstall.sh --help' 를 보세요."
      ;;
  esac
  shift
done

require_sane_home

# 설치본을 지우기 전에 --purge 가 중간에 실패할 조건을 먼저 걸러낸다.
if [ "$PURGE" -eq 1 ]; then
  preflight_purge
fi

# 검색 경로도 전부 먼저 검사한다. 하나라도 안전하지 않으면 아무것도 지우지 않는다.
preflight_search_dirs

say "claude-switch 제거"
remove_installed_commands

if [ "$PURGE" -eq 1 ]; then
  purge_store
else
  keep_store
fi

say ""
say "완료했습니다. 전역 Claude 인증 상태는 변경하지 않았습니다."
