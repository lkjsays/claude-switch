#!/bin/bash
# claude-switch 를 기본적으로 ~/.local/bin 에 설치한다.
# PREFIX=/path 또는 BIN_DIR=/path/to/bin 으로 위치를 바꿀 수 있다.
# FORCE=1 은 v1 설치본 덮어쓰기 확인을 생략한다(비대화형 설치용).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/claude-switch"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
DEST="$BIN_DIR/claude-switch"
FORCE="${FORCE:-0}"

if [ ! -f "$SRC" ]; then
	echo "❌ claude-switch 소스를 찾을 수 없음: $SRC" >&2
	exit 1
fi

if ! /bin/bash -n "$SRC"; then
	echo "❌ 문법 검사 실패: $SRC" >&2
	exit 1
fi

if [ -L "$DEST" ]; then
	echo "❌ 설치 대상이 심볼릭 링크입니다: $DEST" >&2
	echo "   실제 대상을 덮어쓰지 않도록 설치를 중단합니다." >&2
	exit 1
fi

# 기존 설치본이 v2 가 아니면 v1(또는 알 수 없는 스크립트)로 본다. v1 은 전역
# 자격증명을 직접 교체하던 방식이라 v2 로 올리면 동작 의미가 바뀐다(breaking change).
if [ -f "$DEST" ] && ! grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$DEST" 2>/dev/null; then
	echo "⚠️  v2 가 아닌 기존 설치본(v1으로 추정)을 발견했습니다: $DEST"
	echo "   v2 는 전역 Claude 인증을 바꾸지 않고, 프로필 토큰으로 claude 를 실행하는 래퍼입니다."
	echo "   - v1 의 'claude-switch <profile>' = 전역 전환"
	echo "   - v2 의 'claude-switch <profile>' = 그 프로필로 claude 즉시 실행"
	echo "   v1 프로필은 자동 변환되지 않습니다. 계정마다 'claude setup-token' 으로 재등록해야 합니다."
	if [ "$FORCE" = "1" ]; then
		echo "   FORCE=1 이므로 확인 없이 덮어씁니다."
	elif [ -t 0 ]; then
		printf '   v2 로 덮어쓸까요? [y/N] '
		read -r reply
		case "$reply" in
			y | Y | yes | YES) ;;
			*)
				echo "중단했습니다. 기존 설치본은 그대로 둡니다." >&2
				exit 2
				;;
		esac
	else
		echo "❌ 비대화형 환경입니다. 덮어쓰려면 FORCE=1 을 지정하세요." >&2
		echo "   예: FORCE=1 ./install.sh" >&2
		exit 2
	fi
fi

mkdir -p "$BIN_DIR"
cp "$SRC" "$DEST"
chmod 755 "$DEST"

echo "✅ 설치됨: $DEST"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "⚠️  $BIN_DIR 이(가) PATH 에 없습니다."
	echo "   셸 설정에 다음을 추가하세요:"
	echo "   export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac

if command -v claude >/dev/null 2>&1; then
	echo "claude 실행 파일: $(command -v claude)"
else
	echo "⚠️  claude 를 찾을 수 없습니다. Claude Code 를 먼저 설치하세요."
	echo "   claude-switch 는 claude CLI 없이는 동작하지 않습니다."
fi

echo
echo "다음 단계:"
echo "  1) claude setup-token            원하는 계정·조직으로 승인"
echo "  2) claude-switch add <profile>   비표시 입력에 토큰 붙여넣기"
echo "  3) claude-switch verify <profile>"
echo "  4) claude-switch run <profile> -- -p '안녕'"
