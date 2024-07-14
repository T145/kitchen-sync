#!/usr/bin/env bash

#shopt -s extdebug     # or --debugging
set +H +o history     # disable history features (helps avoid errors from "!" in strings)
shopt -u cmdhist      # would be enabled and have no effect otherwise
shopt -s execfail     # ensure interactive and non-interactive runtime are similar
shopt -s extglob      # enable extended pattern matching (https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)
set -euET -o pipefail # put bash into strict mode & have it give descriptive errors
umask 055             # change all generated file perms from 755 to 700
export LC_ALL=C       # force byte-wise sorting and default langauge output
export GIT_TERMINAL_PROMPT=0  # https://stackoverflow.com/questions/65163081/how-do-i-stop-git-from-asking-credentials-when-i-try-to-clone-a-repository-that

CACHE=$(mktemp -d)
ADLISTS='dist/adlists.txt'
DOMAINS='dist/domains.txt'
readonly CACHE ADLISTS DOMAINS

trap 'rm -rf "$CACHE"' EXIT || exit 1

# params: "github api url"
github_query() {
    curl --proto '=https' --tlsv1.3 -H 'Accept: application/vnd.github.v3+json' -sSf "$1"
}

round_up() {
    echo "num = ${1};base = num / 1;if (((num - base) * 10) > 0) base += 1;print base;" | bc
}

manage_lists() {
    local dirname;
    local exit_code;
    local fname;

    while IFS= read -r repo_url; do
        set +e # Temporarily disable strict fail, in case web requests fail
        git clone "$repo_url"

        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            dirname="$(basename ${repo_url%.*})"

            set -e # Enable error checks to fail if something bad happens while processing lists

            fname="${dirname}/adlist.csv"

            if [ -f "$fname" ]; then
                mlr --csv --headerless-csv-output cut -f address "$fname" >>"$ADLISTS"
            fi

            fname="${dirname}/domainlist.csv"

            if [ -f "$fname" ]; then
                mlr --csv --headerless-csv-output cut -f address "$fname" >>"$DOMAINS"
            fi

            fname="${dirname}/adlists.txt"

            if [ -f "$fname" ]; then
                mawk '/^[^[:space:]|^#|^!|^;|^$|^:|^*]/{print $1}' "$fname" >>"$ADLISTS"
            fi

            fname="${dirname}/blacklist.txt"

            if [ -f "$fname" ]; then
                mawk '/^[^[:space:]|^#|^!|^;|^$|^:|^*]/{print $1}' "$fname" >>"$DOMAINS"
            fi

            rm -rf "$dirname"
        else
            set -e
        fi
    done
}

sorted() {
    mawk '{$1=$1};1' "$1" | parsort -bfiu -S 100% -T "$CACHE" | sponge "$1"
}

main() {
    local network_count
    local page_count

    network_count="$(github_query https://api.github.com/repos/stevejenkins/my-pihole-lists | jaq -r '.forks')"
    page_count="$(echo "${network_count}/30" | bc -l)"
    page_count="$(round_up "$page_count")"

    # 30 is the default page count when querying forks
    # trying to increase it up to 100 doesn't work well
    mkdir -p dist/

    seq "$page_count" | while IFS= read -r page; do
        github_query "https://api.github.com/repos/stevejenkins/my-pihole-lists/forks?page=${page}" |
            jaq -r '.[].clone_url' | manage_lists
    done

    sorted "$ADLISTS"
    sorted "$DOMAINS"
}

# https://github.com/koalaman/shellcheck/wiki/SC2218
main

# reset the locale after processing
unset LC_ALL
