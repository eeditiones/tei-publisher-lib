xquery version "3.1";

module namespace tfo="http://existsolutions.com/apps/tei-publisher-lib/ts-fo";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace fo="http://www.w3.org/1999/XSL/Format";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/fo" at "../content/fo-functions.xql";

declare variable $tfo:CFG := map {
  "apply-children": function($config as map(*), $node as node(), $content) { $content },
  "default-styles": map {},
  "styles": map {}
};

declare
  %test:assertTrue
function tfo:anchor-inline-id() as xs:boolean {
  deep-equal(pmf:anchor($tfo:CFG, <n/>, ("c"), (), "id42"), <fo:inline id="id42"/>)
};

declare
  %test:assertTrue
function tfo:link-internal-basic-link() as xs:boolean {
  let $res := pmf:link($tfo:CFG, <n/>, ("c"), "X", "#sec1", map {})
  return name($res)='fo:basic-link' and $res/@internal-destination='sec1' and string($res)='X'
};

declare
  %test:assertTrue
function tfo:link-external-basic-link() as xs:boolean {
  let $res := pmf:link($tfo:CFG, <n/>, ("c"), "X", "http://x", map {})
  return name($res)='fo:basic-link' and $res/@external-destination='http://x' and string($res)='X'
};

declare
  %test:assertTrue
function tfo:link-empty-returns-content() as xs:boolean {
  pmf:link($tfo:CFG, <n/>, ("c"), "X", "#", map {}) = 'X'
};

declare
  %test:assertTrue
function tfo:glyph-eolhyphen-soft-hyphen() as xs:boolean {
  pmf:glyph(map {}, <n/>, ("c"), xs:anyURI("char:EOLhyphen")) = codepoints-to-string(173)
};

declare
  %test:assertTrue
function tfo:text-returns-string-value() as xs:boolean {
  pmf:text($tfo:CFG, <n/>, ("c"), <a>abc</a>) = 'abc'
};

declare
  %test:assertTrue
function tfo:cell-adds-span-attributes() as xs:boolean {
  let $seq := pmf:cell($tfo:CFG, <n cols="2" rows="3"/>, ("c"), "x", ())
  let $res := ($seq[self::element()])[1]
  return name($res)='fo:table-cell' and $res/@number-columns-spanned='2' and $res/@number-rows-spanned='3'
};

declare
  %test:assertTrue
function tfo:paragraph-applies-styles() as xs:boolean {
  let $cfg := map:merge(($tfo:CFG, map { 'styles': map { 'c': map { 'color': 'red', 'text-align': 'center' } } }))
  let $seq := pmf:paragraph($cfg, <n/>, ("c"), "x")
  let $blk := ($seq[self::element()])[1]
  return name($blk)='fo:block' and $blk/@color='red' and $blk/@text-align='center'
};

declare
  %test:assertEquals("x")
function tfo:escape-attribute-returns-data() as xs:string {
  pmf:escapeChars(attribute a { 'x' })
};
