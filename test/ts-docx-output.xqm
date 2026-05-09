xquery version "3.1";

module namespace tdo="http://existsolutions.com/apps/tei-publisher-lib/ts-docx-output";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace docx="http://existsolutions.com/ns/docx";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/docx-output" at "../content/docx-functions.xql";

declare
  %test:assertTrue
function tdo:nested-list-different-type-gets-new-numId() as xs:boolean {
  let $base-cfg := map {
    "apply-children": function($c as map(*), $n as node(), $content) {
      for $i in $content
      return
        typeswitch($i)
          case node() return $i
          default return text { $i }
    }
  }
  let $_ := pmf:prepare($base-cfg, ())
  let $outer := pmf:list($base-cfg, <tei:list xmlns:tei="http://www.tei-c.org/ns/1.0" type="ordered"/>, ("tei-list"), (), "ordered")
  let $outer-instance := $outer[self::docx:list-instance][1]
  let $nested-cfg := map:merge((
      $base-cfg,
      map {
        "list-num-id": string($outer-instance/@numId),
        "list-abstract-id": string($outer-instance/@abstractNumId),
        "list-level": 1
      }
    ), map { "duplicates": "use-last" })
  let $nested := pmf:list($nested-cfg, <tei:list xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-list"), (), ())
  let $nested-instance := $nested[self::docx:list-instance][1]
  let $nested-item-cfg := map:merge((
      $nested-cfg,
      map {
        "list-num-id": string($nested-instance/@numId),
        "list-abstract-id": string($nested-instance/@abstractNumId),
        "list-level": 2
      }
    ), map { "duplicates": "use-last" })
  let $nested-item-content := <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:r><w:t>Nested bullet</w:t></w:r></w:p>
  let $nested-item := pmf:listItem($nested-item-cfg, <tei:item xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-item"), $nested-item-content, ())
  let $_ := pmf:finish($base-cfg, <docx:root xmlns:docx="http://existsolutions.com/ns/docx"/>)
  return
    exists($outer-instance)
    and exists($nested-instance)
    and $nested-instance/@abstractNumId = "10"
    and $nested-instance/@numId != $outer-instance/@numId
    and $nested-item//w:numId/@w:val = $nested-instance/@numId
    and $nested-item//w:ilvl/@w:val = "1"
};

declare
  %test:assertTrue
function tdo:page-break-emits-run-not-paragraph() as xs:boolean {
  let $br := pmf:break(
    map {},
    <tei:pb xmlns:tei="http://www.tei-c.org/ns/1.0"/>,
    ("tei-pb"),
    (),
    "page",
    ()
  )
  return
    $br instance of element(w:r)
    and exists($br/w:br[@w:type = "page"])
    and empty($br[self::w:p])
};

declare
  %test:assertTrue
function tdo:line-break-emits-simple-br-run() as xs:boolean {
  let $br := pmf:break(
    map {},
    <tei:lb xmlns:tei="http://www.tei-c.org/ns/1.0"/>,
    ("tei-lb"),
    (),
    "line",
    ()
  )
  return
    $br instance of element(w:r)
    and exists($br/w:br)
    and empty($br/w:br/@w:type)
    and empty($br[self::w:p])
};

declare
  %test:assertTrue
function tdo:pass-through-section-body-keep-inline-runs() as xs:boolean {
  let $cfg := map {
    "apply-children": function($c as map(*), $n as node(), $content) { $content }
  }
  let $pt := pmf:pass-through($cfg, <tei:hi xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-hi"), text { "A" })
  let $sec := pmf:section($cfg, <tei:div xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-div"), text { "B" })
  let $body := pmf:body($cfg, <tei:body xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-body"), text { "C" })
  return
    every $out in ($pt, $sec, $body) satisfies ($out instance of element(w:r))
    and empty(($pt, $sec, $body)[self::w:p])
};

declare
  %test:assertTrue
function tdo:inline-applies-before-content() as xs:boolean {
  let $cfg := map {
    "styles": map {
      "tei-gap4:before": map { "content": "[...]" }
    },
    "apply-children": function($c as map(*), $n as node(), $content) { $content }
  }
  let $out := pmf:inline($cfg, <tei:gap xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-gap4"), text { "X" })
  let $text := string-join($out//w:t/string(), "")
  return
    starts-with($text, "[...]")
    and contains($text, "X")
};

declare
  %test:assertTrue
function tdo:inline-applies-bold-from-styles() as xs:boolean {
  let $cfg := map {
    "styles": map {
      "tei-hi": map { "font-weight": "bold" }
    },
    "apply-children": function($c as map(*), $n as node(), $content) { $content }
  }
  let $out := pmf:inline($cfg, <tei:hi xmlns:tei="http://www.tei-c.org/ns/1.0"/>, ("tei-hi"), text { "X" })
  return
    exists($out/self::w:r/w:rPr/w:b)
    and $out/self::w:r/w:t = "X"
};
