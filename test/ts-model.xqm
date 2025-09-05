xquery version "3.1";

module namespace tmodel="http://existsolutions.com/apps/tei-publisher-lib/ts-model";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace pm="http://www.tei-c.org/tei-simple/xquery/model" at "../content/model.xql";

declare function tmodel:min-odd($name as xs:string) as element(tei:TEI) {
  <TEI xmlns="http://www.tei-c.org/ns/1.0" source="{$name}">
    <teiHeader/>
    <text><body/></text>
  </TEI>
};

declare function tmodel:mods-html() as array(*) {
  [ map { 'uri': 'http://www.tei-c.org/tei-simple/xquery/functions', 'prefix': 'html', 'at': '../content/html-functions.xql' } ]
};

declare function tmodel:mods-fo() as array(*) {
  [ map { 'uri': 'http://www.tei-c.org/tei-simple/xquery/functions/fo', 'prefix': 'fo', 'at': '../content/fo-functions.xql' } ]
};

declare
  %test:assertTrue
function tmodel:parse-generates-web-module() as xs:boolean {
  let $odd := tmodel:min-odd('MyOdd.odd')
  let $res := pm:parse($odd, tmodel:mods-html(), ('web'), false())
  let $code := $res?code
  return contains($code, 'module namespace model="http://www.tei-c.org/pm/models/MyOdd/web"') and
         contains($code, 'import module namespace css="http://www.tei-c.org/tei-simple/xquery/css"') and
         contains($code, 'import module namespace html="http://www.tei-c.org/tei-simple/xquery/functions"') and
         contains($code, 'declare function model:transform') and
         contains($code, '"odd": "MyOdd.odd"')
};

declare
  %test:assertTrue
function tmodel:parse-generates-fo-module() as xs:boolean {
  let $odd := tmodel:min-odd('Another.odd')
  let $res := pm:parse($odd, tmodel:mods-fo(), ('fo'), false())
  let $code := $res?code
  return contains($code, 'module namespace model="http://www.tei-c.org/pm/models/Another/fo"') and
         contains($code, 'import module namespace fo="http://www.tei-c.org/tei-simple/xquery/functions/fo"')
};

declare
  %test:assertTrue
function tmodel:generated-includes-annotation-processor() as xs:boolean {
  let $odd := tmodel:min-odd('Anno.odd')
  let $res := pm:parse($odd, tmodel:mods-html(), ('web'), false())
  let $code := $res?code
  return contains($code, 'analyze-string($html/@class') and contains($code, 'attribute data-type') and contains($code, 'data-annotation')
};
