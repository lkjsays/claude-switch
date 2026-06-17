#!/bin/bash
# Uninstall claude-switch from this Mac.
# Default: interactive confirmation before deleting stored profiles/tokens.
# Usage:
#   ./uninstall.sh              # ask before deleting ~/.claude-accounts
#   ./uninstall.sh --yes        # delete everything without prompts
#   ./uninstall.sh --keep-accounts

set -euo pipefail

ASSUME_YES=0
KEEP_ACCOUNTS=0

for arg in "$@"; do
	case "$arg" in
	-y | --yes) ASSUME_YES=1 ;;
	--keep-accounts) KEEP_ACCOUNTS=1 ;;
	-h | --help)
		cat <<'EOF'
Uninstall claude-switch from this Mac.

Usage:
  ./uninstall.sh              # ask before deleting ~/.claude-accounts
  ./uninstall.sh --yes        # delete everything without prompts
  ./uninstall.sh --keep-accounts
EOF
		exit 0
		;;
	*)
		echo "Unknown option: $arg" >&2
		exit 2
		;;
	esac
done

say() { printf '%s\n' "$*"; }
remove_file() {
	local path="$1"
	if [ -e "$path" ] || [ -L "$path" ]; then
		rm -f "$path"
		say "removed: $path"
	else
		say "already absent: $path"
	fi
}
confirm_delete_accounts() {
	if [ "$ASSUME_YES" -eq 1 ]; then
		return 0
	fi
	say ""
	say "This will delete stored claude-switch profiles/tokens: $HOME/.claude-accounts"
	printf 'Delete them? [y/N] '
	read -r answer
	case "$answer" in
	y | Y | yes | YES) return 0 ;;
	*) return 1 ;;
	esac
}

say "Uninstalling claude-switch..."

# Remove installed command from common install locations.
remove_file "$HOME/.local/bin/claude-switch"
remove_file "/opt/homebrew/bin/claude-switch"
remove_file "/usr/local/bin/claude-switch"

# Remove live file credentials managed by claude-switch.
remove_file "$HOME/.claude/.credentials.json"

# Remove stored profiles/tokens unless kept or declined.
if [ "$KEEP_ACCOUNTS" -eq 1 ]; then
	say "kept: $HOME/.claude-accounts"
	say "kept: $HOME/.claude-homes"
elif [ -d "$HOME/.claude-accounts" ]; then
	if confirm_delete_accounts; then
		rm -rf "$HOME/.claude-accounts"
		say "removed: $HOME/.claude-accounts"
		if [ -d "$HOME/.claude-homes" ]; then
			rm -rf "$HOME/.claude-homes"
			say "removed: $HOME/.claude-homes"
		else
			say "already absent: $HOME/.claude-homes"
		fi
	else
		say "kept: $HOME/.claude-accounts"
		say "kept: $HOME/.claude-homes"
	fi
else
	say "already absent: $HOME/.claude-accounts"
	if [ -d "$HOME/.claude-homes" ]; then
		rm -rf "$HOME/.claude-homes"
		say "removed: $HOME/.claude-homes"
	else
		say "already absent: $HOME/.claude-homes"
	fi
fi

# Remove Claude Code Keychain credential if present.
if command -v security >/dev/null 2>&1; then
	if security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
		security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || true
		say "removed: Keychain item 'Claude Code-credentials'"
	else
		say "already absent: Keychain item 'Claude Code-credentials'"
	fi
else
	say "skipped: macOS security command not found"
fi

say ""
say "Done. To authenticate Claude Code again, run:"
say "  claude /login"
