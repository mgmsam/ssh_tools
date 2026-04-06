#!/bin/sh

# include.sh. SSH config include manager.
#
# Copyright (c) 2026 Semyon A Mironov
#
# Authors: Semyon A Mironov <s.mironov@mgmsam.pro>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -eu

LOG_PREFIX="${0##*/}: "
PKG_DIR=$(2>&1 cd -- "${0%/*}" && 2>&1 pwd -P) || {
    echo "$LOG_PREFIX: $PKG_DIR"
    exit 1
} >&2

SAM_BASE="$PKG_DIR/lib/shell_library/sam_base.sh"

test -f "$SAM_BASE" || {
    echo "$LOG_PREFIX: lib not found: '$SAM_BASE'"
    exit 1
} >&2

test -r "$SAM_BASE" || {
    echo "$LOG_PREFIX: no read permissions: '$SAM_BASE'"
    exit 1
} >&2

ERROR=$(2>&1 . "$SAM_BASE") || {
    echo "$LOG_PREFIX: $ERROR"
    exit 1
} >&2

. "$SAM_BASE"

create_backup ()
{
    BACKUP_FILE="${1}_$(date +%Y%M%d_%H%M%S).backup"
    copy "$1" "$BACKUP_FILE" || die
    say "backup created: $STATUS"
}

create_link ()
{
    case "$SOURCE_SSH_CONFIG_DIR" in
        "$TARGET_SSH_CONFIG_DIR" | /)
        ;;
        *)
            LINK=$TARGET_SSH_CONFIG_DIR/${SOURCE_SSH_CONFIG_DIR##*/}
            test -e "$LINK" && {
                test -d "$LINK" && {
                    CURRENT_LINK=$(resolve_path "$LINK") || die "$CURRENT_LINK"
                    is_equal "$CURRENT_LINK" "$SOURCE_SSH_CONFIG_DIR" &&
                        say "link already exists: '$CURRENT_LINK' > '$SOURCE_SSH_CONFIG_DIR'"
                } || {
                    create_backup "$LINK"
                    remove "$LINK" || die
                    false
                }
            } || {
                symlink "$SOURCE_SSH_CONFIG_DIR" "$LINK" || die
                say "link created: $STATUS"
            }
            SOURCE_SSH_CONFIG=$LINK/${SOURCE_SSH_CONFIG##*/}
    esac
}

enable_ssh_include ()
{
    RE_INCLUDE="[[:blank:]]*Include[[:blank:]]\+\($SOURCE_SSH_CONFIG\|~${SOURCE_SSH_CONFIG#"$HOME"}\)"
    RE_COMMENT="[[:blank:]]*#\+.*$RE_INCLUDE"

    if STATUS=$(2>&1 grep -nm1 "^$RE_INCLUDE" "$TARGET_SSH_CONFIG")
    then
        say "configuration already included: $TARGET_SSH_CONFIG: line ${STATUS%%:*}: '${STATUS#*:}'"
    else
        STATUS=$(2>&1 grep -nm1 "^$RE_COMMENT" "$TARGET_SSH_CONFIG") && {
            LINE_NUM="${STATUS%%:*}"
            create_backup "$TARGET_SSH_CONFIG"
            STATUS=$(
                2>&1 sed "${LINE_NUM}s/^[[:blank:]#]\+\(Include\)/\1/" -i "$TARGET_SSH_CONFIG"
            ) || die "$STATUS"
            INCLUDED=$(sed -n "$LINE_NUM"p "$TARGET_SSH_CONFIG")
            say "configuration uncommented: $TARGET_SSH_CONFIG: line $LINE_NUM: '$INCLUDED'"
        }
    fi
}

include_config ()
{
    case "$SOURCE_SSH_CONFIG" in
        "$HOME"/*)
            SOURCE_SSH_CONFIG="~${SOURCE_SSH_CONFIG#"$HOME"}"
        ;;
    esac
    INCLUDED="Include $SOURCE_SSH_CONFIG"
    STATUS=$(2>&1 echo "$INCLUDED" > "$TARGET_SSH_CONFIG") || die "$STATUS"
}

main ()
{
    SOURCE_SSH_CONFIG="${1:-$PKG_DIR/../ssh_config}"
    is_file "$SOURCE_SSH_CONFIG" ||
        die "source SSH config not found: '$SOURCE_SSH_CONFIG'"
    full_path "$SOURCE_SSH_CONFIG"
                SOURCE_SSH_CONFIG="$TARGET"

    SOURCE_SSH_CONFIG_DIR="${SOURCE_SSH_CONFIG%/*}"
    is_not_empty "$SOURCE_SSH_CONFIG_DIR" || SOURCE_SSH_CONFIG_DIR=/

    TARGET_SSH_CONFIG="$HOME/.ssh/config"
    full_path "$TARGET_SSH_CONFIG"
                TARGET_SSH_CONFIG="$TARGET"

    TARGET_SSH_CONFIG_DIR="${TARGET_SSH_CONFIG%/*}"
    is_not_empty "$TARGET_SSH_CONFIG_DIR" || TARGET_SSH_CONFIG_DIR=/

    create_link

    if is_file "$TARGET_SSH_CONFIG"
    then
        enable_ssh_include || {
            create_backup "$TARGET_SSH_CONFIG"
            include_config
            STATUS=$(2>&1 cat "$BACKUP_FILE" >> "$TARGET_SSH_CONFIG") ||
                die "$STATUS"
            say "configuration included: $TARGET_SSH_CONFIG: line 1: '$INCLUDED'"
        }
    else
        STATUS=$(
            2>&1 mkdir -pv    "$TARGET_SSH_CONFIG_DIR" &&
            2>&1 touch        "$TARGET_SSH_CONFIG"     &&
            2>&1 chmod -v 700 "$TARGET_SSH_CONFIG_DIR" &&
            2>&1 chmod -v 600 "$TARGET_SSH_CONFIG"
        ) && say -i "$STATUS" || die "$STATUS"
        include_config
        say "configuration included: $TARGET_SSH_CONFIG: line 1: '$INCLUDED'"
    fi
}

main "$@"
