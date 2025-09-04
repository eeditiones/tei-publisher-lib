xquery version "3.1";

module namespace tu="http://existsolutions.com/apps/tei-publisher-lib/ts-util";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmu="http://www.tei-c.org/tei-simple/xquery/util" at "../content/util.xql";

declare
  %test:assertTrue
function tu:properties-renders-selected-config() as xs:boolean {
  let $cfg := <modules>
    <output mode="web">
      <property name="foo">true</property>
      <property name="bar">"abc"</property>
    </output>
    <output mode="other">
      <property name="baz">123</property>
    </output>
  </modules>
  let $s := pmu:properties("odd.odd", "web", $cfg)
  return contains($s, '"foo": true') and contains($s, '"bar": "abc"') and not(contains($s, '"baz":'))
};

declare
  %test:assertTrue
function tu:parse-config-properties-filters-by-mode-and-odd() as xs:boolean {
  let $cfg := <modules>
    <output mode="web" odd="a.odd">
      <property name="x">1</property>
    </output>
    <output mode="web" odd="b.odd">
      <property name="y">2</property>
    </output>
  </modules>
  let $res := pmu:parse-config-properties("b.odd", "web", $cfg, map {})
  return map:contains($res, "properties") and count($res?properties) = 1 and $res?properties/@name = 'y'
};

