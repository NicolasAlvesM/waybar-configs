#!/usr/bin/env bash
# Módulo waybar para o hyprsunset.
#   (sem args) -> imprime JSON de status
#   toggle     -> liga/desliga o filtro, preservando temperatura/gamma
#   warmer     -> -200K   cooler -> +200K

set -u

STATE="${XDG_RUNTIME_DIR:-/tmp}/waybar-hyprsunset.state"
FALLBACK_TEMP=3200
FALLBACK_GAMMA=85
MIN_TEMP=1500
MAX_TEMP=6500
STEP=200

hs() { hyprctl hyprsunset "$@" 2>/dev/null; }

# Só "true"/"false" indicam que o daemon respondeu.
identity_state() {
    local v
    v=$(hs identity get)
    case "$v" in
        true | false) printf '%s' "$v" ;;
        *) return 1 ;;
    esac
}

status() {
    local identity temp gamma
    if ! identity=$(identity_state); then
        printf '{"text":"󰖙","class":"error","tooltip":"hyprsunset não está rodando"}\n'
        return
    fi

    if [ "$identity" = "true" ]; then
        printf '{"text":"󰖙","class":"off","tooltip":"Filtro desligado\\nClique: ligar"}\n'
        return
    fi

    temp=$(hs temperature)
    gamma=$(hs gamma)
    printf '{"text":"󰖔 %sK","class":"on","tooltip":"Filtro ativo — %sK, brilho %s%%\\nClique: desligar · Scroll: ±%sK"}\n' \
        "$temp" "$temp" "$gamma" "$STEP"
}

toggle() {
    local identity temp gamma
    identity=$(identity_state) || return 1

    if [ "$identity" = "true" ]; then
        # Religa restaurando o que estava valendo antes de desligar.
        if [ -r "$STATE" ]; then
            read -r temp gamma <"$STATE"
        fi
        : "${temp:=$FALLBACK_TEMP}" "${gamma:=$FALLBACK_GAMMA}"
        hs identity false >/dev/null
        hs temperature "$temp" >/dev/null
        hs gamma "$gamma" >/dev/null
    else
        printf '%s %s\n' "$(hs temperature)" "$(hs gamma)" >"$STATE"
        hs identity >/dev/null
    fi
}

# Passos relativos são unclamped no daemon, então o limite é aplicado aqui.
step() {
    local delta=$1 temp
    identity_state >/dev/null || return 1
    hs identity false >/dev/null
    temp=$(hs temperature)
    temp=$((temp + delta))
    [ "$temp" -lt "$MIN_TEMP" ] && temp=$MIN_TEMP
    [ "$temp" -gt "$MAX_TEMP" ] && temp=$MAX_TEMP
    hs temperature "$temp" >/dev/null
}

case "${1:-status}" in
    toggle) toggle ;;
    warmer) step -$STEP ;;
    cooler) step $STEP ;;
    *) status ;;
esac
