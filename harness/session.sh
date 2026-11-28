#!/bin/bash
# Runs INSIDE the sandbox (started by `harness/gw play start`). Brings up a private headless
# Wayland session, the game server, the screen recorder and the game client, then waits
# for /gw/out/stop. Nothing here is reachable from, or can reach, the host desktop session.
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
tool sway -c /tmp/sway.conf > "$OUT/sway.log" 2>&1 &
SWAY=$!
wait_for 15 "$XDG_RUNTIME_DIR/wayland-[0-9]" || { phase "failed: compositor did not start"; exit 1; }
export WAYLAND_DISPLAY=$(basename "$(compgen -G "$XDG_RUNTIME_DIR/wayland-[0-9]" | head -1)")
wait_for 15 "/tmp/.X11-unix/X*" || { phase "failed: Xwayland did not start"; exit 1; }
export DISPLAY=:$(basename "$(compgen -G '/tmp/.X11-unix/X*' | head -1)" | tr -d X)

STREAM=
start_stream() { # A VNC server on this compositor, on a Unix socket `gw` relays out to one TCP address.
	rm -f /gw/ipc/vnc.sock
	tool wayvnc -C /gw/ipc/wayvnc.conf -f "${GW_STREAM_FPS:-60}" -g -n "GlutWorks session" \
		-u /gw/ipc/vnc.sock >> "$OUT/stream.log" 2>&1 &
	STREAM=$!
}
if [ -n "${GW_STREAM:-}" ]; then
	phase stream
	start_stream
	wait_for 10 /gw/ipc/vnc.sock || { phase "failed: the stream server did not start; see stream.log"; exit 1; }
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

phase recorder
# Recording time is wall time minus this: the recorder captures from its first moment, and
# `gw mark` places marks with it. (The file's first bytes are no clock: the muxer holds
# its first five seconds back.)
date +%s.%N > "$OUT/recording.start"
tool wf-recorder -y -f "$OUT/session.mkv" -r "${GW_FPS:-30}" -c libx264 -x yuv420p \
	-p preset=veryfast -p crf=24 > "$OUT/recorder.log" 2>&1 &
RECORDER=$!

if [ -n "${GW_STEAM_PORT:-}" ]; then
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
	# A viewer can make the VNC server exit; the person reconnects to a new one.
	if [ -n "$STREAM" ] && ! kill -0 "$STREAM" 2>/dev/null; then
		echo "[session] stream server exited; restarting it" | tee -a "$OUT/stream.log"
		start_stream
	fi
	sleep 0.1
done
kill -0 "$CLIENT" 2>/dev/null || echo "[session] client exited on its own"

phase stopping
kill -INT "$RECORDER" 2>/dev/null
for _ in $(seq 100); do kill -0 "$RECORDER" 2>/dev/null || break; sleep 0.1; done
kill "$CLIENT" 2>/dev/null
kill $(jobs -p) 2>/dev/null
kill "$SWAY" 2>/dev/null
phase stopped
