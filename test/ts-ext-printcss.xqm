xquery version "3.1";

module namespace tpc="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-printcss";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/printcss" at "../content/ext-printcss.xql";

declare variable $tpc:CFG := map { 'apply-children': function($c as map(*), $n as node(), $content) { $content } };

declare
  %test:assertTrue
function tpc:note-margin-place() as xs:boolean {
  let $res := pmf:note($tpc:CFG, <n/>, ("c"), 'X', 'margin', ())
  return name($res)='span' and contains($res/@class, 'margin-note') and string($res)='X'
};

declare
  %test:assertTrue
function tpc:note-footnote-place() as xs:boolean {
  let $res := pmf:note($tpc:CFG, <n/>, ("c"), 'X', 'footnote', ())
  return name($res)='span' and contains($res/@class, 'footnote')
};

declare
  %test:assertTrue
function tpc:alternate-nested-spans() as xs:boolean {
  let $res := pmf:alternate($tpc:CFG, <n/>, ("c"), (), 'D', 'A')
  return name($res[1])='span' and $res[2]/contains(@class, 'footnote')
};

