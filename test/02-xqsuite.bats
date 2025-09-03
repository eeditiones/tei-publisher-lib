#!/usr/bin/env bats

# Configuration
APP_BASE=${APP_BASE:-http://127.0.0.1:8080/exist/rest/db/system/repo/tei-publisher-lib-4.0.3}
RUNNER_PATH=${RUNNER_PATH:-/test/test-runner.xq}
CREDENTIALS=${CREDENTIALS:-admin:}

@test "xqsuite junit endpoint returns XML" {
  run curl -fsS -u "$CREDENTIALS" -D >(tee /tmp/headers.$$ >/dev/null) -H 'Accept: application/xml' "${APP_BASE}${RUNNER_PATH}"
  [ "$status" -eq 0 ]
  # Verify content type is XML
  run grep -i '^Content-Type:.*xml' /tmp/headers.$$
  [ "$status" -eq 0 ]
}

@test "xqsuite junit reports zero failures and errors" {
  run curl -fsS -u "$CREDENTIALS" -H 'Accept: application/xml' "${APP_BASE}${RUNNER_PATH}"
  [ "$status" -eq 0 ]
  response="$output"

  # Best-effort XML parsing (JUnit)
  flat=$(printf "%s" "$response" | tr -d '\n')
  tests=$(printf "%s" "$flat" | grep -o 'tests="[0-9]\+"' | grep -o '[0-9]\+' | head -1)
  failures=$(printf "%s" "$flat" | grep -o 'failures="[0-9]\+"' | grep -o '[0-9]\+' | head -1)
  errors=$(printf "%s" "$flat" | grep -o 'errors="[0-9]\+"' | grep -o '[0-9]\+' | head -1)
  pending=$(printf "%s" "$flat" | grep -o 'pending="[0-9]\+"' | grep -o '[0-9]\+' | head -1)
  timestamp=$(printf "%s" "$flat" | grep -o 'timestamp="[^"]*"' | sed -E 's/.*="([^"]*)"/\1/' | head -1)
  duration=$(printf "%s" "$flat" | grep -o 'time="[^"]*"' | sed -E 's/.*="([^"]*)"/\1/' | head -1)
  echo "# XQSuite JUnit: tests=${tests:-?} failures=${failures:-0} errors=${errors:-0} pending=${pending:-0} time=${duration:-?} at ${timestamp:-?}"
  echo "# Testcases:"
  segments=$(printf "%s" "$flat" | sed 's/<testcase /\n<testcase /g' | grep -E '^<testcase ')
  case_fail=0
  while IFS= read -r seg; do
    name=$(printf "%s" "$seg" | sed -n -E 's/.*name="([^"]*)".*/\1/p')
    if printf "%s" "$seg" | grep -q '<failure\b\|<error\b'; then
      # Extract message/type/text for failure or error
      msg=$(printf "%s" "$seg" | sed -n -E 's/.*<(failure|error)[^>]*message="([^"]*)".*/\2/p' | head -1)
      typ=$(printf "%s" "$seg" | sed -n -E 's/.*<(failure|error)[^>]*type="([^"]*)".*/\2/p' | head -1)
      txt=$(printf "%s" "$seg" | sed -n -E 's/.*<(failure|error)[^>]*>([^<]*).*/\2/p' | head -1)
      summary=$(printf "%s %s %s" "${msg}" "${typ}" "${txt}" | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')
      if [ -n "$summary" ]; then
        echo "#  - $name: FAIL — $summary"
      else
        echo "#  - $name: FAIL"
      fi
      case_fail=$((case_fail+1))
    else
      echo "#  - $name: ok"
    fi
  done <<< "$segments"

  # Determine failure count without double-counting:
  # Prefer explicit <failure>/<error> elements; fall back to testsuite attributes.
  fail_elts=$(printf "%s" "$flat" | grep -c '<failure\b' | tr -d ' ')
  err_elts=$(printf "%s" "$flat" | grep -c '<error\b' | tr -d ' ')
  if [ $((fail_elts + err_elts)) -gt 0 ]; then
    total_bad=$(( fail_elts + err_elts ))
  else
    total_bad=$(( ${failures:-0} + ${errors:-0} ))
  fi

  if [ "$total_bad" -ne 0 ]; then
    echo "xqsuite junit failures detected: $total_bad"
    # Print a compact preview for diagnostics
    echo "$flat" | sed -E 's/[[:space:]]+/ /g' | cut -c1-2000
    false
  fi
}
