#!/usr/bin/env bash

#shopt -s extdebug     # or --debugging
set +H +o history     # disable history features (helps avoid errors from "!" in strings)
shopt -u cmdhist      # would be enabled and have no effect otherwise
shopt -s execfail     # ensure interactive and non-interactive runtime are similar
shopt -s extglob      # enable extended pattern matching (https://www.gnu.org/software/bash/manual/html_node/Pattern-Matching.html)
set -euET -o pipefail # put bash into strict mode & have it give descriptive errors
umask 055             # change all generated file perms from 755 to 700
export LC_ALL=C       # force byte-wise sorting and default langauge output

CACHE=$(mktemp -d)
readonly CACHE

trap 'rm -rf "$CACHE"' EXIT || exit 1

# params: "github api url"
github_query() {
    curl --proto '=https' --tlsv1.3 -H 'Accept: application/vnd.github.v3+json' -sSf "$1"
}

round_up() {
    echo "num = ${1};base = num / 1;if (((num - base) * 10) > 0) base += 1;print base;" | bc
    #echo ''
}

manage_lists() {
    while IFS= read -r repo_url; do
        git clone "$repo_url"

        mlr --csv cut -f address 'my-pihole-lists/adlist.csv' >>adlists.txt
        mlr --csv cut -f domain 'my-pihole-lists/domainlist.csv' >>domains.txt

        rm -rf my-pihole-lists/
    done
}

sorted() {
    parsort -bfiu -S 100% --parallel=200000 -T "$CACHE" "$1" | sponge "$1"
}

main() {
    local network_count
    local page_count

    network_count="$(github_query https://api.github.com/repos/stevejenkins/my-pihole-lists | jq -r '.forks')"
    page_count="$(echo "${network_count}/30" | bc -l)"
    page_count="$(round_up "$page_count")"

    # 30 is the default page count when querying forks
    # trying to increase it up to 100 doesn't work well

    seq "$page_count" | while IFS= read -r page; do
        github_query "https://api.github.com/repos/stevejenkins/my-pihole-lists/forks?page=${page}" |
            jq -r '.[].clone_url' | manage_lists
    done

    sorted adlists.txt
    sorted domains.txt
}

# https://github.com/koalaman/shellcheck/wiki/SC2218
main

# reset the locale after processing
unset LC_ALL
