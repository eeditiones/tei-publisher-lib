xquery version "3.1";

module namespace txq="http://existsolutions.com/apps/tei-publisher-lib/ts-xqgen";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace xqgen="http://www.tei-c.org/tei-simple/xquery/xqgen" at "../content/xqgen.xql";

declare
  %test:assertTrue
function txq:generate-simple-module() as xs:boolean {
  let $xml := <xquery>
    <module prefix="m" uri="urn:test">
      <function name="m:f">
        <param>$x</param>
        <body>
          <code>1</code>
        </body>
      </function>
    </module>
  </xquery>
  let $code := xqgen:generate($xml, 0)
  return contains($code, 'module namespace m="urn:test";') and contains($code, 'declare function m:f($x) {') and contains($code, '1')
};

