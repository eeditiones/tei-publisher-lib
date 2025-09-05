xquery version "3.1";

module namespace tscn="http://existsolutions.com/apps/tei-publisher-lib/ts-counters";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace counters="http://www.tei-c.org/tei-simple/xquery/counters" at "../content/counters.xql";
import module namespace util="http://exist-db.org/xquery/util";

declare function tscn:random-id() as xs:string {
  concat("xqsuite-", substring(util:uuid(), 1, 8))
};

declare
  %test:assertTrue
function tscn:counters-increment-sequence() as xs:boolean {
  let $id := tscn:random-id()
  let $_ := counters:create($id)
  let $v1 := counters:increment($id)
  let $v2 := counters:increment($id)
  let $_ := counters:destroy($id)
  return $v1 = 1 and $v2 = 2
};

declare
  %test:assertTrue
function tscn:counters-destroy-and-recreate-resets() as xs:boolean {
  let $id := tscn:random-id()
  let $_ := counters:create($id)
  let $_ := counters:increment($id)
  let $_ := counters:destroy($id)
  let $_ := counters:create($id)
  let $v := counters:increment($id)
  let $_ := counters:destroy($id)
  return $v = 1
};

