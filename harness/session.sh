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
tool wf-recorder -y -f "$OUT/session.mkv" -r "${GW_FPS:-30}" -c libx264 -x yuv420p \
	-p preset=veryfast -p crf=24 > "$OUT/recorder.log" 2>&1 &
RECORDER=$!

phase client
bash -c "$GW_CLIENT" > "$OUT/client.log" 2>&1 &
CLIENT=$!

phase running
mkdir -p "$OUT/shots"
while [ ! -e "$OUT/stop" ] && kill -0 "$CLIENT" 2>/dev/null; do
	touch "$OUT/alive" # heartbeat: lets sandboxed callers tell the session is up without signalling it
	# Screenshot requests from `gw play shot`: the file holds the name to save under.
	if [ -e "$OUT/shot.req" ]; then
		name=$(tr -cd 'A-Za-z0-9_-' < "$OUT/shot.req")
		rm -f "$OUT/shot.req"
		tool grim -t jpeg -q 88 "$OUT/shots/$name.jpg" 2>> "$OUT/recorder.log" || echo failed > "$OUT/shots/$name.err"
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
