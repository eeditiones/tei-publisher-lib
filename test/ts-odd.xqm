xquery version "3.1";

module namespace todd="http://existsolutions.com/apps/tei-publisher-lib/ts-odd";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace odd="http://www.tei-c.org/tei-simple/odd2odd" at "../content/odd2odd.xql";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

declare variable $todd:ROOT := "/db/tmp/ts-odd";

declare
  %test:setUp
function todd:_setup() {
  xmldb:create-collection('/db', substring-after($todd:ROOT, '/db/')),
  xmldb:store($todd:ROOT, 'parent.odd',
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader/>
      <text><body>
        <elementSpec ident="y"><model/></elementSpec>
        <elementSpec ident="p"><model><modelSequence/></model></elementSpec>
      </body></text>
    </TEI>
  ),
  xmldb:store($todd:ROOT, 'child.odd',
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <encodingDesc>
          <schemaSpec source="parent.odd"/>
        </encodingDesc>
      </teiHeader>
      <text><body>
        <elementSpec ident="x"><model/></elementSpec>
        <elementSpec ident="p" mode="change"/>
      </body></text>
    </TEI>
  )
};

declare
  %test:tearDown
function todd:_teardown() {
  if (xmldb:collection-available($todd:ROOT)) then xmldb:remove($todd:ROOT) else ()
};

declare
  %test:assertTrue
function todd:compile-merges-parent-and-child() as xs:boolean {
  let $doc := odd:get-compiled($todd:ROOT, 'child.odd')
  return exists($doc//tei:elementSpec[@ident='x']) and exists($doc//tei:elementSpec[@ident='y'])
};

declare
  %test:assertTrue
function todd:compile-copies-model-on-change() as xs:boolean {
  let $doc := odd:get-compiled($todd:ROOT, 'child.odd')
  let $p := $doc//tei:elementSpec[@ident='p']
  return exists($p/tei:model)
};

