xquery version "3.1";

module namespace tdts="http://existsolutions.com/apps/tei-publisher-lib/ts-dts";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace dts="https://w3id.org/dts/api#" at "../content/dts-api.xql";

declare
  %test:assertTrue
function tdts:collection-by-id-recurses() as xs:boolean {
  let $c3 := map { 'id': 'c3', 'title': 'C3' }
  let $c2 := map { 'id': 'c2', 'title': 'C2', 'memberCollections': ( $c3 ) }
  let $c1 := map { 'id': 'c1', 'title': 'C1', 'memberCollections': ( $c2 ) }
  let $found := dts:collection-by-id($c1, 'c3')
  return $found?title = 'C3'
};

declare
  %test:assertTrue
function tdts:get-members-handles-collection-maps() as xs:boolean {
  let $cfg := map { 'dts-page-size': 10 }
  let $collInfo := map { 'path': '/db/data', 'metadata': function($doc) { map {} } }
  let $members := dts:get-members($cfg, $collInfo, ( map { 'id': 'sub', 'title': 'Sub' } ))
  let $first := $members[1]
  return count($members) = 1 and map:get($first, '@type') = 'Collection' and $first?title = 'Sub'
};
