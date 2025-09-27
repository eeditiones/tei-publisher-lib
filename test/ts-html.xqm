xquery version "3.1";

module namespace th="http://existsolutions.com/apps/tei-publisher-lib/ts-html";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions" at "../content/html-functions.xql";

declare variable $th:CFG := map {
  "apply-children": function($config as map(*), $node as node(), $content) { $content }
};

declare
  %test:assertTrue
function th:paragraph-wraps-content() as xs:boolean {
  let $res := pmf:paragraph($th:CFG, <n/>, ("cls"), "Hello")
  return deep-equal($res, <p class="cls">Hello</p>)
};

declare
  %test:assertTrue
function th:heading-h2-with-level() as xs:boolean {
  let $res := pmf:heading($th:CFG, <n/>, ("cls"), "Head", 2)
  return local-name($res) = 'h2' and $res/@class = 'cls' and string($res) = 'Head'
};

declare
  %test:assertTrue
function th:anchor-span-id() as xs:boolean {
  deep-equal(pmf:anchor($th:CFG, <n/>, ("c"), (), "id42"), <span id="id42"/>)
};

declare
  %test:assertTrue
function th:link-attributes-and-text() as xs:boolean {
  let $res := pmf:link($th:CFG, <n/>, ("c"), "txt", "http://x", "_blank", map {})
  return
    name($res) = 'a' and
    $res/@href = 'http://x' and $res/@class = 'c' and $res/@target = '_blank' and string($res) = 'txt'
};

declare
  %test:assertTrue
function th:glyph-eolhyphen-soft-hyphen() as xs:boolean {
  pmf:glyph(map {}, <n/>, ("c"), "char:EOLhyphen") = codepoints-to-string(173)
};

declare
  %test:assertTrue
function th:break-line-produces-br() as xs:boolean {
  deep-equal(pmf:break($th:CFG, <n/>, ("c"), (), "line", ()), <br class="c"/>)
};

declare
  %test:assertTrue
function th:break-page-wraps-label() as xs:boolean {
  deep-equal(pmf:break($th:CFG, <n/>, ("c"), (), "page", "12"), <span class="c">12</span>)
};

declare
  %test:assertTrue
function th:graphic-sets-src-style-id() as xs:boolean {
  let $node := <n xml:id="img1"/>
  let $res := pmf:graphic($th:CFG, $node, ("c"), (), "pic.png", "100px", "50px", (), "T")
  return name($res)='img' and $res/@src='pic.png' and $res/@class='c' and $res/@title='T' and $res/@id='img1' and contains($res/@style, 'width: 100px;') and contains($res/@style, 'height: 50px;')
};

declare
  %test:assertTrue
function th:cell-colspan-rowspan() as xs:boolean {
  let $res := pmf:cell($th:CFG, <n cols="2" rows="3"/>, ("c"), 'X', 'body')
  return name($res) = 'td' and $res/@colspan = '2' and $res/@rowspan = '3'
};

declare
  %test:assertTrue
function th:match-wraps-and-copies-exist-id() as xs:boolean {
  let $parent := <p exist:id="PID"><x/></p>
  let $res := pmf:match($th:CFG, $parent/x, "Z")
  return deep-equal($res, <mark id="PID">Z</mark>)
};

declare
  %test:assertTrue
function th:prepare-returns-empty-when-no-styles() as xs:boolean {
  empty(pmf:prepare(map {}, <n/>))
};

declare
  %test:assertTrue
function th:finish-returns-input() as xs:boolean {
  let $in := (<a/>, <b/>)
  return deep-equal(pmf:finish(map {}, $in), $in)
};

declare
  %test:assertTrue
function th:add-language-attributes-returns-rtl-and-lang() as xs:boolean {
  let $in := <a xml:lang="ar"/>
  let $out := <a>{pmf:add-language-attributes($in)}</a>
  return deep-equal(<a dir="rtl" lang="ar"></a>, $out)
};

declare
  %test:assertTrue
function th:add-language-attributes-returns-ltr-and-lang() as xs:boolean {
  let $in := <a xml:lang="cs-CZ"/>
  let $out := <a>{pmf:add-language-attributes($in)}</a>
  return deep-equal(<a dir="ltr" lang="cs-CZ"></a>, $out)
};

declare
  %test:assertTrue
function th:add-language-attributes-returns-nothing() as xs:boolean {
  let $in := <a lang="ar"/>
  let $out := <a>{pmf:add-language-attributes($in)}</a>
  return deep-equal(<a></a>, $out)
};
