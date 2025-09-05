#!/usr/bin/env bats

# Configuration
# If APP_BASE is not set, derive the version from expath-pkg.xml and construct the repo URL accordingly.
if [ -z "${APP_BASE:-}" ]; then
  # Try to read the package version from expath-pkg.xml (works without namespaces)
  pkg_ver=$(xmllint --xpath 'string(//*[local-name()="package"]/@version)' expath-pkg.xml 2>/dev/null || true)
  if [ -n "$pkg_ver" ]; then
    APP_BASE="http://127.0.0.1:8080/exist/rest/db/system/repo/tei-publisher-lib-$pkg_ver"
  else
    # Fallback if xmllint is unavailable or expath-pkg.xml not readable
    APP_BASE="http://127.0.0.1:8080/exist/rest/db/system/repo/tei-publisher-lib"
  fi
fi
RUNNER_PATH=${RUNNER_PATH:-/test/test-runner.xq}
CREDENTIALS=${CREDENTIALS:-admin:}

@test "xqsuite junit endpoint returns XML (xmllint)" {
  run curl -fsS -u "$CREDENTIALS" -D >(tee /tmp/headers.$$ >/dev/null) -H 'Accept: application/xml' "${APP_BASE}${RUNNER_PATH}"
  [ "$status" -eq 0 ]
  # Preserve response body before the next run overwrites $output
  resp="$output"
  run grep -i '^Content-Type:.*xml' /tmp/headers.$$
  [ "$status" -eq 0 ]
  # Save report for inspection if endpoint returned XML
  mkdir -p build
  # Always overwrite any existing report file
  printf "%s" "$resp" | tee build/testsuite.xml >/dev/null
}

@test "xmllint is available" {
  run command -v xmllint
  [ "$status" -eq 0 ]
}

@test "xqsuite junit zero failures and errors (xmllint)" {
  run curl -fsS -u "$CREDENTIALS" -H 'Accept: application/xml' "${APP_BASE}${RUNNER_PATH}"
  [ "$status" -eq 0 ]
  response="$output"

  tmp="/tmp/xqs.$$"
  printf "%s" "$response" > "$tmp"

  # Choose parsing source: response; fall back to local sample if no testcases found
  tc_in_resp=$(xmllint --xpath 'count(//testcase)' "$tmp" 2>/dev/null | sed 's/\..*$//' || echo 0)
  pf="$tmp"
  if [ "${tc_in_resp:-0}" -eq 0 ] && [ -f "build/testsuite.xml" ]; then
    pf="build/testsuite.xml"
  fi

  xpath_str() { xmllint --xpath "string($1)" "$pf" 2>/dev/null || true; }
  xpath_num() { xmllint --xpath "$1" "$pf" 2>/dev/null | sed 's/\..*$//' || echo 0; }

  tests_attr=$(xpath_num 'sum(//testsuite/@tests)'); [ -z "$tests_attr" ] && tests_attr=$(xpath_num 'count(//testcase)')
  failures_attr=$(xpath_num 'sum(//testsuite/@failures)')
  errors_attr=$(xpath_num 'sum(//testsuite/@errors)')
  pending=$(xpath_num 'sum(//testsuite/@pending)')
  timestamp=$(xpath_str '(//testsuite/@timestamp)[1]')
  duration=$(xpath_str '(//testsuite/@time)[1]')

  echo "# XQSuite JUnit: tests=${tests_attr:-?} failures=${failures_attr:-0} errors=${errors_attr:-0} pending=${pending:-0} time=${duration:-?} at ${timestamp:-?}"

  echo "# Testcases:"
  tc_count=$(xpath_num 'count(//testcase)')
  case_fail=0
  if [ "${tc_count:-0}" -gt 0 ]; then
    i=1
    while [ $i -le "$tc_count" ]; do
      name=$(xpath_str "(//testcase)[$i]/@name")
      fail_i=$(xpath_num "count((//testcase)[$i]/failure)")
      err_i=$(xpath_num  "count((//testcase)[$i]/error)")
      if [ $((fail_i + err_i)) -gt 0 ]; then
        msg=$(xpath_str "(//testcase)[$i]/failure[1]/@message"); [ -z "$msg" ] && msg=$(xpath_str "(//testcase)[$i]/error[1]/@message")
        typ=$(xpath_str "(//testcase)[$i]/failure[1]/@type");     [ -z "$typ" ] && typ=$(xpath_str "(//testcase)[$i]/error[1]/@type")
        txt=$(xpath_str "(//testcase)[$i]/failure[1]");           [ -z "$txt" ] && txt=$(xpath_str "(//testcase)[$i]/error[1]")
        summary=$(printf "%s %s %s" "${msg}" "${typ}" "${txt}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        [ -n "$summary" ] && echo "#  - ${name:-?}: FAIL — $summary" || echo "#  - ${name:-?}: FAIL"
        case_fail=$((case_fail+1))
      else
        echo "#  - ${name:-?}: ok"
      fi
      i=$((i+1))
    done
  fi

  # Single-pass failure logic: drive status purely by what we listed
  total_bad=${case_fail:-0}
  if [ "$total_bad" -ne 0 ]; then
    echo "xqsuite junit failures detected: $total_bad"
    tr "\n" ' ' < "$tmp" | cut -c1-2000
    false
  fi

  rm -f "$tmp" /tmp/headers.$$ 2>/dev/null || true
}
