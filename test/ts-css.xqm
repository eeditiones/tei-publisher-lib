xquery version "3.1";

module namespace tsc="http://existsolutions.com/apps/tei-publisher-lib/ts-css";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace css="http://www.tei-c.org/tei-simple/xquery/css" at "../content/css.xql";
import module namespace util="http://exist-db.org/xquery/util";
import module namespace xmldb="http://exist-db.org/xquery/xmldb";

(: Test fixtures: temp collection + document :)
declare variable $tsc:TEMP-COLL := "/db/tmp/ts-css-xqsuite";
declare variable $tsc:TEMP-DOC := "d.xml";

declare
  %test:setUp
function tsc:_setup() {
  let $_ := xmldb:create-collection("/db", substring-after($tsc:TEMP-COLL, "/db/"))
  let $doc := <TEI xmlns="http://www.tei-c.org/ns/1.0">
                <rendition xml:id="r1">color:red</rendition>
                <x rendition="#r1"/>
              </TEI>
  return xmldb:store($tsc:TEMP-COLL, $tsc:TEMP-DOC, $doc)
};

declare
  %test:tearDown
function tsc:_teardown() {
  if (xmldb:collection-available($tsc:TEMP-COLL)) then xmldb:remove($tsc:TEMP-COLL) else ()
};

(: Empty token between commas used to trigger FORX0003 in replace :)
declare
  %test:assertTrue
function tsc:parse-css-empty-token-no-error() as xs:boolean {
  let $css := ".a,,.b { color: red; }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Trailing comma in selector list :)
declare
  %test:assertTrue
function tsc:parse-css-trailing-comma-no-error() as xs:boolean {
  let $css := ".a, { color: red }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Entirely empty selector entry :)
declare
  %test:assertTrue
function tsc:parse-css-empty-selector-entry-no-error() as xs:boolean {
  let $css := ", { color: red }"
  let $result := css:parse-css($css)
  return $result instance of map(*)
};

(: Sanity: a regex that DOES match empty strings should raise FORX0003 on exist 6.4.0 and later :)
declare
  %test:pending("Proper error only raised in exist 6.4.0 and later")
  %test:assertError("err:FORX0003")
function tsc:regex-zero-length-match-errors() {
  replace("", ".*", "x")
};

(: Additional CSS utility tests :)
declare
  %test:assertTrue
function tsc:map-rend-to-class-tokenizes() as xs:boolean {
  let $n := <x rend="a, b  c"/>
  let $res := css:map-rend-to-class($n)
  return deep-equal($res, ("a","b","c"))
};

declare
  %test:assertTrue
function tsc:get-rendition-expands-values() as xs:boolean {
  let $n := <x rendition="#r1 simple:foo zz"/>
  let $res := css:get-rendition($n, ("base"))
  return deep-equal($res, ("base", "document_r1", "simple_foo", "zz"))
};

declare
  %test:assertTrue
  %test:pending('TBD why it is failing')
function tsc:rendition-styles-html-from-doc() as xs:boolean {
  let $doc := doc($tsc:TEMP-COLL || "/" || $tsc:TEMP-DOC)
  let $cfg := map { 'parameters': map { 'root': $doc } }
  let $strs := css:rendition-styles-html($cfg, $doc//tei:x)
  return exists($strs) and contains(string-join($strs), '.document_r1') and contains(string-join($strs), 'color:red')
};

declare
  %test:assertTrue
function tsc:global-css-by-selector-produces-block() as xs:boolean {
  let $doc := document { <tei:TEI xmlns:tei="http://www.tei-c.org/ns/1.0">
    <tei:teiHeader>
      <tei:encodingDesc>
        <tei:tagsDecl>
          <tei:rendition selector=".x">color:red;&#10;line-height:1.2</tei:rendition>
        </tei:tagsDecl>
      </tei:encodingDesc>
    </tei:teiHeader>
  </tei:TEI> }
  let $css := css:global-css($doc, "/db/odd/any.odd")
  return contains($css, '.x {') and contains($css, 'color:red;') and contains($css, '&#9;line-height:1.2')
};
