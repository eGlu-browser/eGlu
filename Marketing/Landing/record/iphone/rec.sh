#!/bin/zsh
# rec.sh start NAME | stop : the simulator's screen to NAME.mp4 in this folder.
cd "$(dirname "$0")"
if [[ $1 == start ]]; then
  xcrun simctl io "${DEVICE:-booted}" recordVideo --codec h264 --force "$2.mp4" > "$2.log" 2>&1 &
  echo $! > rec.pid
  sleep 1.2
  echo recording
else
  sleep 0.6
  kill -INT $(cat rec.pid); sleep 1.5
  ls -la *.mp4 | tail -3
fi
