xquery version "3.1";

module namespace tpmc="http://existsolutions.com/apps/tei-publisher-lib/ts-pmc";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmc="http://www.tei-c.org/tei-simple/xquery/config" at "../content/generate-pmc.xql";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

declare variable $tpmc:ROOT := "/db/tmp/ts-pmc";

declare
  %test:setUp
function tpmc:_setup() {
  xmldb:create-collection("/db", substring-after($tpmc:ROOT, "/db/")),
  xmldb:store($tpmc:ROOT, "A.odd", document { processing-instruction teipublisher { 'output="web latex"' }, <dummy/> }),
  xmldb:store($tpmc:ROOT, "B.odd", document { processing-instruction teipublisher { 'output="fo"' }, <dummy/> })
};

declare
  %test:tearDown
function tpmc:_teardown() {
  if (xmldb:collection-available($tpmc:ROOT)) then xmldb:remove($tpmc:ROOT) else ()
};

declare
  %test:assertTrue
function tpmc:generate-pm-config-contains-imports-and-vars() as xs:boolean {
  let $code := pmc:generate-pm-config(("A.odd","B.odd"), "A.odd", $tpmc:ROOT)
  return contains($code, 'import module namespace pm-A-web') and contains($code, 'import module namespace pm-A-latex') and contains($code, 'import module namespace pm-B-fo') and contains($code, '$pm-config:web-transform') and contains($code, '$pm-config:fo-transform')
};
