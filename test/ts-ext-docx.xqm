xquery version "3.1";

module namespace ted="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-docx";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace tf="http://existsolutions.com/xquery/functions/tei";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/docx" at "../content/ext-docx.xql";

declare variable $ted:CFG := map { };

declare
  %test:assertTrue
function ted:finish-wraps-headings-into-divs() as xs:boolean {
  let $tei := <TEI xmlns="http://www.tei-c.org/ns/1.0">
                <text><body>
                  <head xmlns:tf="http://existsolutions.com/xquery/functions/tei" tf:level="1">H1</head>
                  <p>Para</p>
                  <head xmlns:tf="http://existsolutions.com/xquery/functions/tei" tf:level="1">H2</head>
                  <p>Q</p>
                </body></text>
              </TEI>
  let $res := pmf:finish($ted:CFG, $tei)
  return count($res//tei:div) = 2
};

declare
  %test:assertTrue
function ted:finish-heads-stripped-level() as xs:boolean {
  let $tei := <TEI xmlns="http://www.tei-c.org/ns/1.0">
                <text><body>
                  <head xmlns:tf="http://existsolutions.com/xquery/functions/tei" tf:level="1">H1</head>
                  <p>Para</p>
                  <head xmlns:tf="http://existsolutions.com/xquery/functions/tei" tf:level="1">H2</head>
                  <p>Q</p>
                </body></text>
              </TEI>
  let $res := pmf:finish($ted:CFG, $tei)
  return every $h in $res//tei:div/tei:head satisfies empty($h/@tf:level)
};

declare
  %test:assertTrue
function ted:finish-returns-unchanged-without-head() as xs:boolean {
  let $tei := <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><p>x</p></body></text></TEI>
  let $res := pmf:finish($ted:CFG, $tei)
  return deep-equal($res, $tei)
};
