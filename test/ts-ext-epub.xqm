xquery version "3.1";

module namespace tep="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-epub";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace epub="http://www.idpf.org/2007/ops";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/epub" at "../content/ext-epub.xql";

declare variable $tep:CFG := map { 'apply-children': function($c as map(*), $n as node(), $content) { $content } };

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
