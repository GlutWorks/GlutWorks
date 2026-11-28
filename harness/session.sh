#!/bin/bash
# Runs INSIDE the sandbox (started by `harness/gw play start`). Brings up a private headless
# Wayland session, the game server, the screen recorder and the game client, then waits
# for /gw/out/stop. Nothing here is reachable from, or can reach, the host desktop session,
# except with GW_NET=direct, where the sandbox shares the host's network: no relays, and the
# stream server binds $GW_STREAM_BIND:$GW_STREAM_PORT itself.
set -u

OUT=/gw/out
TOOLS=/gw/tools/usr
export XDG_RUNTIME_DIR=/run/gw
export XDG_SESSION_TYPE=wayland
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 LIBSEAT_BACKEND=noop
mkdir -p -m 700 "$XDG_RUNTIME_DIR"

tool() { local name=$1; shift; LD_LIBRARY_PATH=$TOOLS/lib "$TOOLS/bin/$name" "$@"; }
phase() { echo "$1" > "$OUT/phase"; echo "[session] $1"; }
wait_for() { # wait_for <seconds> <glob>
	for _ in $(seq $(($1 * 10))); do compgen -G "$2" > /dev/null && return 0; sleep 0.1; done
	return 1
}

cat > /tmp/sway.conf <<EOF
output HEADLESS-1 resolution ${GW_RES:-1280x720} position 0 0
xwayland force
default_border none
default_floating_border none
focus_follows_mouse no
for_window [class=".*"] fullscreen enable
for_window [app_id=".*"] fullscreen enable
EOF

phase compositor
# A Selkies stream captures the compositor's buffers on the GPU and encodes them there, so both
# use the first render node.
DRI=$(compgen -G "/dev/dri/renderD*" | head -1)
case "${GW_STREAM:-vnc}" in vnc) DRI= ;; esac
[ -n "$DRI" ] && export WLR_RENDER_DRM_DEVICE=$DRI
tool sway -c /tmp/sway.conf > "$OUT/sway.log" 2>&1 &
SWAY=$!
unset WLR_RENDER_DRM_DEVICE
wait_for 15 "$XDG_RUNTIME_DIR/wayland-[0-9]" || { phase "failed: compositor did not start"; exit 1; }
export WAYLAND_DISPLAY=$(basename "$(compgen -G "$XDG_RUNTIME_DIR/wayland-[0-9]" | head -1)")
wait_for 15 "/tmp/.X11-unix/X*" || { phase "failed: Xwayland did not start"; exit 1; }
export DISPLAY=:$(basename "$(compgen -G '/tmp/.X11-unix/X*' | head -1)" | tr -d X)

STREAM=
DIRECT=
[ "${GW_NET:-isolated}" = direct ] && DIRECT=1
STREAM_SOCK=/gw/ipc/selkies.sock
[ "${GW_STREAM:-}" = vnc ] && STREAM_SOCK=/gw/ipc/vnc.sock
# Selkies leaves loopback addresses out of its WebRTC host candidates. Relayed, the sandbox has
# no other: it is given 127.0.0.1, offered to viewers as $GW_STREAM_OFFER (--webrtc-public-ip).
# Direct, its one host address is $GW_STREAM_OFFER, where it binds the media port as well.
SELKIES_MAIN='import os, sys, selkies.ice.ice as ice, selkies.webrtc_engine as engine
from selkies.ice import mdns

host = os.environ.get("GW_STREAM_HOST", "127.0.0.1")
ice.get_host_addresses = engine.get_host_addresses = lambda use_ipv4=True, use_ipv6=False: [host] if use_ipv4 else []
add_remote_candidate = ice.Connection.add_remote_candidate

async def add_relay_candidate(connection, candidate):
    # The sandbox cannot join mDNS multicast. ICE-lite learns the browser
    # address from incoming relay packets, including for mDNS-only browsers.
    if connection.ice_lite and candidate is not None and mdns.is_mdns_hostname(candidate.host):
        return
    await add_remote_candidate(connection, candidate)

ice.Connection.add_remote_candidate = add_relay_candidate
from selkies.__main__ import main
sys.argv[0] = "selkies"
main()'
start_stream() { # The stream server on this compositor: on a Unix socket `gw` relays out (see portproxy.py), or direct on its port.
	rm -f "$STREAM_SOCK"
	if [ "$GW_STREAM" = vnc ]; then
		local where=(-u "$STREAM_SOCK")
		[ -n "$DIRECT" ] && where=("$GW_STREAM_BIND" "$GW_STREAM_PORT")
		tool wayvnc -C /gw/ipc/wayvnc.conf -f "${GW_STREAM_FPS:-60}" -g -n "GlutWorks session" \
			"${where[@]}" >> "$OUT/stream.log" 2>&1 &
	else
		local rtc=() where=(--unix-socket="$STREAM_SOCK")
		[ -n "$DIRECT" ] && where=(--addr="$GW_STREAM_BIND" --port="$GW_STREAM_PORT")
		[ "$GW_STREAM" = webrtc ] && rtc=(--webrtc-udp-mux-port="$GW_STREAM_PORT" --webrtc-ice-lite=true
			--rtc-config-json=/gw/ipc/rtc.json)
		[ "$GW_STREAM" = webrtc ] && [ -z "$DIRECT" ] && rtc+=(--webrtc-public-ip="$GW_STREAM_OFFER")
		# Under a path prefix, so a caller can reverse-proxy every route of it from its own origin.
		local web=(--subfolder="${GW_STREAM_PATH:-/}")
		[ -n "${GW_STREAM_TLS:-}" ] && web+=(--enable-https=true --https-cert=/gw/ipc/tls.pem --https-key=/gw/ipc/tls.key)
		# The picture keeps the session's size whatever the browser's; the browser scales it.
		(set -a; . /gw/ipc/selkies.env; set +a; [ -n "$DIRECT" ] && export GW_STREAM_HOST="$GW_STREAM_OFFER"
			cd /tmp && exec "$GW_SELKIES/bin/python3" -I -c "$SELKIES_MAIN" \
			--mode="$GW_STREAM" --wayland=true --wayland-host-display="$WAYLAND_DISPLAY" "${where[@]}" \
			--enable-resize=false --manual-width="${GW_RES%x*}" --manual-height="${GW_RES#*x}" \
			--framerate="${GW_STREAM_FPS:-60}" ${DRI:+--render-dri=$DRI --encode-dri=$DRI} "${rtc[@]}" "${web[@]}" \
			--audio-enabled=false --gamepad-enabled=false --file-transfers= --printing-enabled=false \
			--enable-sharing=false) >> "$OUT/stream.log" 2>&1 &
	fi
	STREAM=$!
}
if [ -n "${GW_STREAM:-}" ]; then
	phase stream
	if [ "$GW_STREAM" = webrtc ]; then
		# No STUN or TURN server: viewers reach the offered address directly, and nothing calls out.
		echo '{"iceServers": []}' > /gw/ipc/rtc.json
		[ -z "$DIRECT" ] && python3 /gw/portproxy.py udp-sandbox /gw/ipc "$GW_STREAM_PORT" >> "$OUT/stream.log" 2>&1 &
	fi
	start_stream
	# Direct, `gw` waits for the port itself once the session runs.
	[ -n "$DIRECT" ] || wait_for 30 "$STREAM_SOCK" || { phase "failed: the stream server did not start; see stream.log"; exit 1; }
fi

if [ -n "${GW_SERVER:-}" ]; then
	phase server
	(cd /gw/ds && LD_LIBRARY_PATH=.:bin/linux64:linux64 exec $GW_SERVER) > "$OUT/server.log" 2>&1 &
	SERVER=$!
	for _ in $(seq 900); do
		grep -qs "gw_harness ready" "$OUT/server.log" /gw/ds/garrysmod/console.log && break
		kill -0 "$SERVER" 2>/dev/null || { phase "failed: server exited during startup"; exit 1; }
		sleep 0.1
	done
fi

RECORDER=
if [ -n "${GW_RECORD:-}" ]; then
	phase recorder
	# Recording time is wall time minus this: the recorder captures from its first moment, and
	# `gw mark` places marks with it. (The file's first bytes are no clock: the muxer holds
	# its first five seconds back.)
	date +%s.%N > "$OUT/recording.start"
	tool wf-recorder -y -f "$OUT/session.mkv" -r "${GW_FPS:-30}" -c libx264 -x yuv420p \
		-p preset=veryfast -p crf=24 > "$OUT/recorder.log" 2>&1 &
	RECORDER=$!
fi

if [ -n "${GW_STEAM_PORT:-}" ]; then
	wait_for 5 /gw/ipc/steam.sock || { phase "failed: the Steam relay did not start"; exit 1; }
	python3 /gw/portproxy.py sandbox /gw/ipc/steam.sock "$GW_STEAM_PORT" &
fi

phase client
bash -c "$GW_CLIENT" > "$OUT/client.log" 2>&1 &
CLIENT=$!

# The 32-bit client opens a "SetLocale failed" warning box on current glibc and waits for
# OK before it goes on. The box is an X window titled "Warning" at the top left; click OK.
(
	for _ in $(seq 240); do
		if xdotool search --name '^Warning$' > /dev/null 2>&1; then
			xdotool mousemove 142 102 click 1
			sleep 1
			xdotool search --name '^Warning$' > /dev/null 2>&1 || break
		fi
		sleep 0.25
	done
) &

phase running
mkdir -p "$OUT/shots"
# Heartbeat: lets sandboxed callers tell the session is up without signalling it. It beats on
# its own because the loop below is busy for as long as an xdotool command holds a key.
(
	while [ ! -e "$OUT/stop" ] && kill -0 "$CLIENT" 2>/dev/null; do
		touch "$OUT/alive"
		sleep 1
	done
) &

while [ ! -e "$OUT/stop" ] && kill -0 "$CLIENT" 2>/dev/null; do
	# Screenshot requests from `gw play shot` and `gw mark --shot`: shots/<name>.req asks
	# for shots/<name>.jpg, which appears whole.
	for req in "$OUT"/shots/*.req; do
		[ -e "$req" ] || continue
		name=$(basename "$req" .req | tr -cd 'A-Za-z0-9_-')
		if tool grim -t jpeg -q 88 "$OUT/shots/.$name.jpg" 2>> "$OUT/recorder.log"; then
			mv "$OUT/shots/.$name.jpg" "$OUT/shots/$name.jpg"
		else
			echo failed > "$OUT/shots/$name.err"
		fi
		rm -f "$req"
	done
	# Real keyboard and mouse input from `gw play xdo`: the file holds NUL-separated
	# xdotool arguments.
	if [ -e "$OUT/xdo.req" ]; then
		mapfile -d '' -t xdo_args < "$OUT/xdo.req"
		rm -f "$OUT/xdo.req"
		xdotool "${xdo_args[@]}" > "$OUT/xdo.out.tmp" 2>&1
		mv "$OUT/xdo.out.tmp" "$OUT/xdo.out"
	fi
	# A viewer can make the stream server exit; the person reconnects to a new one.
	if [ -n "$STREAM" ] && ! kill -0 "$STREAM" 2>/dev/null; then
		echo "[session] stream server exited; restarting it" | tee -a "$OUT/stream.log"
		start_stream
	fi
	sleep 0.1
done
kill -0 "$CLIENT" 2>/dev/null || echo "[session] client exited on its own"

phase stopping
if [ -n "$RECORDER" ]; then
	kill -INT "$RECORDER" 2>/dev/null
	for _ in $(seq 100); do kill -0 "$RECORDER" 2>/dev/null || break; sleep 0.1; done
fi
kill "$CLIENT" 2>/dev/null
kill $(jobs -p) 2>/dev/null
kill "$SWAY" 2>/dev/null
phase stopped
