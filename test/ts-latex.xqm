xquery version "3.1";

module namespace tsl="http://existsolutions.com/apps/tei-publisher-lib/ts-latex";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/latex" at "../content/latex-functions.xql";

(: Escaping tests :)
declare
  %test:assertEquals("\textunderscore ")
function tsl:escape-underscore() as xs:string {
  pmf:escapeChars(text { "_" })
};

declare
  %test:assertEquals("\textasciitilde ")
function tsl:escape-tilde() as xs:string {
  pmf:escapeChars(text { "~" })
};

declare
  %test:assertEquals("\textasciicircum ")
function tsl:escape-caret() as xs:string {
  pmf:escapeChars(text { "^" })
};

declare
  %test:assertEquals("\textbackslash ")
function tsl:escape-backslash() as xs:string {
  pmf:escapeChars(text { "\" })
};

declare
  %test:assertEquals("\&#38;")
function tsl:escape-ampersand() as xs:string {
  pmf:escapeChars(text { "&amp;" })
};


declare
  %test:assertEquals("a\{\}\%\$\#b")
function tsl:escape-braces-and-specials() as xs:string {
  pmf:escapeChars(text { "a{}%$#b" })
};

(: Label and glyph tests :)
declare
  %test:assertEquals("\label{id1}")
function tsl:get-label-with-xmlid() as xs:string {
  let $n := <d xml:id="id1"/>
  return pmf:get-label($n)
};

declare
  %test:assertTrue
function tsl:get-label-without-xmlid-empty() as xs:boolean {
  empty(pmf:get-label(<d/>))
};

declare
  %test:assertTrue
function tsl:glyph-eolhyphen() as xs:boolean {
  pmf:glyph(map {}, <n/>, ("x"), xs:anyURI("char:EOLhyphen")) = codepoints-to-string(173)
};

(: Utility tests :)
declare
  %test:assertEquals("ab")
function tsl:finish-joins-and-trims() as xs:string {
  pmf:finish(map {}, (" a", " b"))
};

declare
  %test:assertEquals("bar")
function tsl:get-property-default() as xs:string {
  pmf:get-property(map {}, "foo", "bar")
};

declare
  %test:assertEquals("\label{id42}")
function tsl:anchor-produces-label() as xs:string {
  pmf:anchor(map {}, <n/>, ("cls"), (), "id42")
};

(: Macro name conversion with digits and separators :)
declare
  %test:assertEquals("\TitleIIISubXII{X}")
function tsl:macroName-wrapping-via-check-styles() as xs:string {
  let $cfg := map {
    'apply-children': function($c as map(*), $n as node(), $content) { $content },
    'styles': map { 'title3-sub_12': map { 'font-weight': 'bold' } }
  }
  let $res := pmf:get-content($cfg, <n/>, ('title3-sub_12'), 'X')
  return string-join($res)
};
