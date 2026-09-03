xquery version "3.1";

module namespace tep="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-epub";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace epub="http://www.idpf.org/2007/ops";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/epub" at "../content/ext-epub.xql";

declare variable $tep:CFG := map {
    'apply-children': function($c as map(*), $n as node(), $content) { $content },
    'apply': function($c as map(*), $content) { $content }
};

declare
  %test:assertTrue
function tep:block-sets-id-when-missing() as xs:boolean {
  let $res := pmf:block($tep:CFG, <n/>, ("c"), "X")
  return name($res)='div' and $res/@class='c' and exists($res/@id)
};

declare
  %test:assertTrue
function tep:break-page-with-label() as xs:boolean {
  let $res := pmf:break($tep:CFG, <n/>, ("c"), (), 'page', '12')
  return name($res)='span' and contains($res/@class, 'pagebreak') and $res/@id='page12' and $res/@epub:type='pagebreak' and string($res)='12'
};

declare
  %test:assertTrue
function tep:alternate-yields-linked-aside() as xs:boolean {
  let $seq := pmf:alternate($tep:CFG, <n/>, ("c"), (), 'D', 'A')
  let $a := $seq[1]
  let $aside := $seq[2]
  return name($a)='a' and contains($a/@class, 'alternate') and name($aside)='aside' and contains($aside/@class, 'altcontent') and substring-after($a/@href, '#') = $aside/@id
};

declare
  %test:assertTrue
function tep:alternate-wraps-content-in-fn-body() as xs:boolean {
  (: A plain class hook for the aside's content: several reading systems (Apple
     Books among them) drop or ignore aside[epub|type=…] rules inside the
     floating panel they render a footnote aside into. :)
  let $aside := pmf:alternate($tep:CFG, <n/>, ("c"), (), 'D', 'A')[2]
  return name($aside/*[1]) = 'div' and $aside/*[1]/@class = 'fn-body' and $aside/*[1]/text() = 'A'
};

declare
  %test:assertTrue
function tep:note-wraps-content-in-fn-body() as xs:boolean {
  let $aside := pmf:note($tep:CFG, <n/>, ("c"), <content><p>body</p></content>, (), ())[2]
  return name($aside/*[1]) = 'div' and $aside/*[1]/@class = 'fn-body' and name($aside/*[1]/*[1]) = 'p'
};
