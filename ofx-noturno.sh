#!/usr/bin/env bash
# Módulo waybar dos jobs noturnos do OFX-Facil (executor: ~/.local/bin/ofx-noturno.sh):
#   e-mails     23:59  /process-emails em loop até zerar o inbox de e-mail
#   força-tarefa 03:00  pull da main + make fetch-inboxes + /forca-tarefa-inbox
# Uma chave liga/desliga os DOIS agendamentos; um motor/modelo vale para os dois.
#   (sem args) -> JSON de status
#   toggle     -> liga/desliga os dois timers
#   model      -> menu wofi de motor/modelo (~/.config/ofx-noturno/models)
#   run        -> menu wofi: rodar um job agora / parar o que estiver rodando
#   log        -> abre o log mais recente

set -u

CFG_DIR="$HOME/.config/ofx-noturno"
STATE="$HOME/.local/state/ofx-noturno"
JOBS="emails inbox"
SIGNAL=9

refresh() { pkill -RTMIN+$SIGNAL waybar 2>/dev/null; }
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//'; }
label() { [ "$1" = emails ] && echo "E-mails (23:59)" || echo "Força-tarefa (03:00)"; }
enabled() { systemctl --user is-enabled --quiet "ofx-$1.timer"; }
running() { systemctl --user is-active --quiet "ofx-$1.service"; }

current_model() {
    local ENGINE=claude MODEL=opus
    [ -f "$CFG_DIR/engine" ] && . "$CFG_DIR/engine"
    printf '%s %s' "$ENGINE" "$MODEL"
}

status() {
    local engine model j on=0 run=0 err=0 icon class tip
    read -r engine model <<<"$(current_model)"
    [ "$model" = "-" ] && model="default"
    for j in $JOBS; do
        enabled $j && on=1
        running $j && run=1
        [ -f "$STATE/$j/last" ] && [ "$(cut -f2 "$STATE/$j/last")" != 0 ] && err=1
    done

    if [ $run = 1 ]; then icon="󰑮"; class="running"
    elif [ $err = 1 ]; then icon="󰃰"; class="error"
    elif [ $on = 1 ]; then icon="󰃰"; class="on"
    else icon="󰃰"; class="off"; fi

    tip=$(
        printf 'Jobs noturnos OFX-Facil\n'
        printf 'Agendamento: %s\n' "$([ $on = 1 ] && echo LIGADO || echo desligado)"
        printf 'Motor: %s / %s' "$engine" "$model"
        printf '\n'
        for j in $JOBS; do
            printf '\n%s\n' "$(label $j)"
            if running $j; then
                if grep -q 'esperando ele acabar' "$STATE/$j/latest.log" 2>/dev/null &&
                   ! grep -q '^== ' "$STATE/$j/latest.log" 2>/dev/null; then
                    printf '  NA FILA (esperando o outro job)\n'
                else
                    printf '  RODANDO agora\n'
                fi
            fi
            if enabled $j; then
                printf '  próxima: %s\n' "$(systemctl --user show "ofx-$j.timer" -p NextElapseUSecRealtime --value)"
            fi
            if [ -f "$STATE/$j/last" ]; then
                IFS=$'\t' read -r when rc e m msg <"$STATE/$j/last"
                printf '  última: %s — %s (%s %s)\n' "$when" "$msg" "$e" "$m"
            else
                printf '  última: nunca rodou\n'
            fi
        done
        printf '\nClique: liga/desliga\nDireito: motor/modelo\nMeio: rodar agora / parar\nScroll: último log'
    )
    printf '{"text":"%s %s","class":"%s","tooltip":"%s"}\n' \
        "$icon" "$engine" "$class" "$(printf '%s' "$tip" | esc)"
}

case "${1:-}" in
    toggle)
        if enabled emails || enabled inbox; then
            for j in $JOBS; do systemctl --user disable --now "ofx-$j.timer"; done
            notify-send -a ofx-noturno "Jobs noturnos: DESLIGADOS"
        else
            for j in $JOBS; do systemctl --user enable --now "ofx-$j.timer"; done
            notify-send -a ofx-noturno "Jobs noturnos: LIGADOS" "E-mails 23:59 · Força-tarefa 03:00 — $(current_model)"
        fi
        refresh ;;
    model)
        pkill -x wofi && exit 0
        read -r cur_e cur_m <<<"$(current_model)"
        choice=$(grep -vE '^\s*(#|$)' "$CFG_DIR/models" |
            awk -v e="$cur_e" -v m="$cur_m" '{mark = ($1==e && $2==m) ? "● " : "   "; print mark $1 " " $2}' |
            wofi --dmenu --insensitive --prompt "Motor / modelo" --lines 8 --width 360) || exit 0
        read -r engine model <<<"$(sed 's/^[● ]*//' <<<"$choice")"
        [ -n "${engine:-}" ] || exit 0
        printf 'ENGINE=%s\nMODEL=%s\n' "$engine" "${model:--}" >"$CFG_DIR/engine"
        notify-send -a ofx-noturno "Jobs noturnos: motor $engine / ${model:--}"
        refresh ;;
    run)
        pkill -x wofi && exit 0
        opts=""
        for j in $JOBS; do
            if running $j; then opts+="Parar $(label $j)"$'\n'
            else opts+="Rodar agora: $(label $j)"$'\n'; fi
        done
        choice=$(printf '%s' "$opts" | wofi --dmenu --prompt "Jobs noturnos" --lines 3 --width 380) || exit 0
        for j in $JOBS; do
            case "$choice" in
                "Parar $(label $j)")
                    ans=$(printf 'Não\nSim, parar' | wofi --dmenu --prompt "Parar $(label $j)?" --lines 2 --width 360) || exit 0
                    [ "$ans" = "Sim, parar" ] || exit 0
                    systemctl --user stop "ofx-$j.service"
                    notify-send -a ofx-noturno "$(label $j): parado" ;;
                "Rodar agora: $(label $j)")
                    # systemctl start num serviço que já está rodando não abre um segundo;
                    # o executor ainda tem trava própria por job.
                    systemctl --user start --no-block "ofx-$j.service"
                    notify-send -a ofx-noturno "$(label $j): iniciado" "$(current_model)" ;;
            esac
        done
        sleep 1; refresh ;;
    log)
        latest=$(ls -t "$STATE"/*/latest.log 2>/dev/null | head -1)
        [ -n "$latest" ] && xdg-open "$latest" >/dev/null 2>&1 & ;;
    *) status ;;
esac
