xquery version "3.1";

module namespace ts="http://existsolutions.com/apps/tei-publisher-lib/tests";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace css="http://www.tei-c.org/tei-simple/xquery/css" at "../content/css.xql";

(: Empty token between commas used to trigger FORX0003 in replace :)
declare
  %test:assertTrue
function ts:parse-css-empty-token-no-error() as xs:boolean {
  let $css := ".a,,.b { color: red; }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Trailing comma in selector list :)
declare
  %test:assertTrue
function ts:parse-css-trailing-comma-no-error() as xs:boolean {
  let $css := ".a, { color: red }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Entirely empty selector entry :)
declare
  %test:assertTrue
function ts:parse-css-empty-selector-entry-no-error() as xs:boolean {
  let $css := ", { color: red }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Sanity: a regex that DOES match empty strings should raise FORX0003 :)
declare
  %test:assertError("err:FORX0003")
function ts:regex-zero-length-match-errors() {
  replace("", ".*", "x")
};

