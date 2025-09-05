xquery version "3.1";

module namespace ttei="http://existsolutions.com/apps/tei-publisher-lib/ts-tei";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmf="http://existsolutions.com/xquery/functions/tei" at "../content/tei-functions.xql";

declare variable $ttei:CFG := map {
  "apply-children": function($config as map(*), $node as node(), $content) { $content }
};

declare
  %test:assertTrue
function ttei:paragraph-tei-ns() as xs:boolean {
  let $res := pmf:paragraph($ttei:CFG, <n/>, ("c"), "Hello")
  return namespace-uri-from-QName(node-name($res)) = 'http://www.tei-c.org/ns/1.0' and local-name($res)='p' and string($res)='Hello'
};

declare
  %test:assertTrue
function ttei:break-page-pb() as xs:boolean {
  let $res := pmf:break($ttei:CFG, <n/>, ("c"), (), "page", "X")
  return namespace-uri-from-QName(node-name($res)) = 'http://www.tei-c.org/ns/1.0' and local-name($res)='pb' and string($res)='X'
};

declare
  %test:assertTrue
function ttei:break-line-lb() as xs:boolean {
  let $res := pmf:break($ttei:CFG, <n/>, ("c"), (), "line", ())
  return namespace-uri-from-QName(node-name($res)) = 'http://www.tei-c.org/ns/1.0' and local-name($res)='lb'
};

declare
  %test:assertTrue
function ttei:anchor-with-id-and-optional-attrs() as xs:boolean {
  let $res := pmf:anchor($ttei:CFG, <n/>, ("c"), (), "id1", map { 'when': 'now', 'resp': 'me' })
  return namespace-uri-from-QName(node-name($res)) = 'http://www.tei-c.org/ns/1.0' and local-name($res)='anchor' and $res/@xml:id='id1' and $res/@when='now' and $res/@resp='me'
};

declare
  %test:assertTrue
function ttei:list-and-item() as xs:boolean {
  let $li := pmf:listItem($ttei:CFG, <n/>, ("c"), "X", (), map { 'level': 1, 'type': 'head' })
  let $lst := pmf:list($ttei:CFG, <n/>, ("c"), $li, 'unordered')
  return namespace-uri-from-QName(node-name($lst))='http://www.tei-c.org/ns/1.0' and local-name($lst)='list' and contains(string-join($lst//text(), ''), 'X')
};

declare
  %test:assertTrue
function ttei:inline-creates-tei-element() as xs:boolean {
  let $res := pmf:inline($ttei:CFG, <n/>, ("c"), "T", map { 'tei_element': 'hi', 'tei_attributes': ('rend=bold', 'type=emph') })
  return namespace-uri-from-QName(node-name($res))='http://www.tei-c.org/ns/1.0' and local-name($res)='hi' and $res/@rend='bold' and $res/@type='emph' and string($res)='T'
};

declare
  %test:assertTrue
function ttei:apply-children-includes-xmlid() as xs:boolean {
  let $seq := pmf:apply-children($ttei:CFG, <n xml:id="x"/>, 'Z')
  let $attr := $seq[1]
  return
    $attr instance of attribute() and
    local-name-from-QName(node-name($attr)) = 'id' and
    namespace-uri-from-QName(node-name($attr)) = 'http://www.w3.org/XML/1998/namespace' and
    $attr = 'x' and $seq[2] = 'Z'
};

declare
  %test:assertTrue
function ttei:cell-adds-cols-attribute() as xs:boolean {
  let $res := pmf:cell($ttei:CFG, <n/>, ("c"), 'X', (), map { 'cols': 3 })
  return namespace-uri-from-QName(node-name($res)) = 'http://www.tei-c.org/ns/1.0' and local-name($res)='cell' and $res/@cols = '3'
};
