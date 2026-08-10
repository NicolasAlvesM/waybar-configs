#!/usr/bin/env bash
# Waybar VPN indicator.
# Detects NetworkManager VPN/WireGuard connections and raw tun/wg interfaces
# (Pritunl, OpenVPN, WireGuard) and emits JSON for a custom module.

ICON_ON="󰦝"

name=""
dev=""

# 1) Name from NetworkManager (vpn / wireguard connections).
#    The DEVICE column of a NM vpn connection points at the underlying link,
#    not at the tunnel, so only the name is taken from here.
while IFS=$'\t' read -r conn ctype cdev; do
    case "$ctype" in
        vpn | wireguard | tun | *openvpn* | *wireguard*)
            name="$conn"
            case "$cdev" in
                tun* | tap* | wg* | utun*) dev="$cdev" ;;
            esac
            break
            ;;
    esac
done < <(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null |
    sed 's/\\:/\x01/g' | tr ':' '\t' | tr '\x01' ':')

# 2) Tunnel interface (also catches VPNs that NM does not manage).
if [ -z "$dev" ]; then
    for t in tun wireguard; do
        while read -r iface state _; do
            [ -z "$iface" ] && continue
            iface="${iface%%@*}"
            case "$state" in
                UP | UNKNOWN)
                    dev="$iface"
                    break 2
                    ;;
            esac
        done < <(ip -br link show type "$t" 2>/dev/null)
    done
fi

# sem VPN: texto vazio faz o waybar esconder o modulo por completo
if [ -z "$dev" ] && [ -z "$name" ]; then
    printf '{"text":"","class":"off","tooltip":""}\n'
    exit 0
fi

label="${name:-$dev}"

ipaddr=""
mode="?"
if [ -n "$dev" ]; then
    ipaddr=$(ip -4 -br addr show dev "$dev" 2>/dev/null | awk '{print $3}' | head -n1)
    [ -z "$ipaddr" ] && ipaddr=$(ip -6 -br addr show dev "$dev" 2>/dev/null | awk '{print $3}' | head -n1)
    # a default route through the tunnel means all traffic goes through it
    if ip route show default 2>/dev/null | grep -q "dev $dev"; then
        mode="full tunnel"
    else
        mode="split tunnel"
    fi
fi

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tooltip="VPN ativa: $(esc "$label")\ninterface: ${dev:-n/a}\nIP: ${ipaddr:-n/a}\nmodo: $mode"

printf '{"text":"%s %s","class":"on","tooltip":"%s"}\n' \
    "$ICON_ON" "$(esc "$label")" "$tooltip"
