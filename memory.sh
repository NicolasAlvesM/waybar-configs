#!/usr/bin/env bash
# Waybar memory indicator.
# Shows used RAM (total - available, like the built-in module) and a tooltip
# with the processes using the most memory, grouped by name (sum of RSS).

TOP=10
ICON=""

read -r total avail < <(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t, a}' /proc/meminfo)
used_kb=$((total - avail))

text=$(awk -v u="$used_kb" -v i="$ICON" 'BEGIN {printf "%s  %.1fG", i, u / 1048576}')
pct=$((used_kb * 100 / total))

procs=$(ps -eo rss=,comm= --no-headers |
    awk '{ rss = $1; $1 = ""; sub(/^ /, ""); mem[$0] += rss }
         END { for (p in mem) printf "%d\t%s\n", mem[p], p }' |
    sort -rn | head -n "$TOP" |
    awk -F'\t' '{
        kb = $1
        if (kb >= 1048576) size = sprintf("%.2f GiB", kb / 1048576)
        else size = sprintf("%.0f MiB", kb / 1024)
        printf "%-18s %10s\n", $2, size
    }' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

tooltip=$(printf 'RAM: %.1f / %.1f GiB (%d%%)\n\n%s' \
    "$(awk -v k="$used_kb" 'BEGIN {print k / 1048576}')" \
    "$(awk -v k="$total" 'BEGIN {print k / 1048576}')" \
    "$pct" "$procs")

jq -cn --arg text "$text" --arg tooltip "<tt>$tooltip</tt>" --arg pct "$pct" \
    '{text: $text, tooltip: $tooltip, percentage: ($pct | tonumber)}'
