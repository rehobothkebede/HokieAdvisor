#!/bin/bash
# Run from any directory on a Mac with Xcode and Deno installed.
# Real Swift transport/models + local PGlite course backend + synthetic chat.
# Never reads production credentials, contacts OpenAI, or changes hosted data.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
qa_output="$(mktemp -d /tmp/agora-client-qa.XXXXXX)"
echo "QA logs: $qa_output"
for qa_port in 8791 8792; do
  if lsof -nP -iTCP:"$qa_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Local QA port $qa_port is already in use. Stop that test server first."
    exit 1
  fi
done
courses_pid=""
stream_pid=""
cleanup() {
  if [ -n "$courses_pid" ]; then kill "$courses_pid" 2>/dev/null || true; fi
  if [ -n "$stream_pid" ]; then kill "$stream_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
PORT=8791 QA_NOW=2026-11-10T16:00:00Z deno run --no-lock --allow-read --allow-env --allow-net=127.0.0.1:8791 \
  backend/supabase/tests/courses_dev_server.ts >"$qa_output/courses.log" 2>&1 &
courses_pid=$!
deno run --no-lock --allow-net=127.0.0.1:8792 tests/qa/stream_server.ts >"$qa_output/stream.log" 2>&1 &
stream_pid=$!
for qa_port in 8791 8792; do
  ready=0
  for attempt in {1..40}; do
    if curl --silent --output /dev/null "http://127.0.0.1:$qa_port/"; then ready=1; break; fi
    sleep 0.25
  done
  if [ "$ready" -ne 1 ]; then cat "$qa_output/courses.log" "$qa_output/stream.log"; exit 1; fi
done
xcrun swiftc -D DEBUG -parse-as-library tests/qa/{ClientStubs,ClientSmoke}.swift \
  ios/HokieAdvisor/HokieAdvisor/{Models,APIService,ChatViewModel,CourseCompanionModels,CourseCompanionService,GraphModel,LaTeXText}.swift \
  -o "$qa_output/client-smoke"
"$qa_output/client-smoke" -AgoraCoursesEndpoint http://127.0.0.1:8791/functions/v1/courses \
  -AgoraCoursesToken qa-token-student | tee "$qa_output/results.log"
