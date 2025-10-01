xquery version "3.1";

module namespace tmd="http://existsolutions.com/apps/tei-publisher-lib/ts-markdown";
declare namespace test="http://exist-db.org/xquery/xqsuite";

import module namespace pmf="http://www.tei-c.org/tei-simple/xquery/markdown" at "../content/markdown-functions.xql";

declare variable $tmd:CFG := 
    map { 
        "apply-children": function($config as map(*), $node as node(), $content) { $content },
        "indent": "",
        "styles": map {
            "bold": map { "font-weight": "bold" },
            "italic": map { "font-style": "italic" },
            "del": map { "text-decoration": "line-through" },
            "gap:before": map { "content": "[…]" }
        }
    };

declare
    %test:assertEquals("An indented paragraph with a line break in the middle and extra whitespace ")
function tmd:nl-and-leading-whitespace() as xs:string {
    let $content := 
        <root>
            An indented paragraph with a line
            break in the middle and extra whitespace
        </root>
    return
        pmf:finish($tmd:CFG, $content)
};

declare
    %test:assertEquals("* item 1&#10;* item 2&#10;    * item 2.1&#10;    * item 2.2 ")
function tmd:list-with-paragraphs-needs-indent() as xs:string {
    let $content := 
        <root>
            * item 1<lb/>
            * item 2<lb/>
            <indent indent="    "/>* item 2.1<lb/>
            <indent indent="    "/>* item 2.2
        </root>
    return
        pmf:finish($tmd:CFG, $content)
};

declare
    %test:assertEquals("**Hello**")
function tmd:inline-bold() as xs:string {
    pmf:inline($tmd:CFG, <n/>, ("bold"), "Hello")
    => string-join("")
};

declare
    %test:assertEquals("**Hello world**")
function tmd:inline-bold-with-leading-space() as xs:string {
    pmf:finish($tmd:CFG, <root>{pmf:inline($tmd:CFG, <n/>, ("bold"), " Hello world")}</root>)
    => string-join("")
};

declare
    %test:assertEquals("_Hello world_")
function tmd:inline-emphasis-with-trailing-space() as xs:string {
    pmf:finish($tmd:CFG, <root>{pmf:inline($tmd:CFG, <n/>, ("italic"), "Hello world  ")}</root>)
    => string-join("")
};

declare
    %test:assertEquals("<del>Hello</del>")
function tmd:inline-erased() as xs:string {
    pmf:inline($tmd:CFG, <n/>, ("del"), "Hello")
    => string-join("")
};

declare
    %test:assertEquals("[…]")
function tmd:inline-css-content() as xs:string {
    pmf:inline($tmd:CFG, <n/>, ("gap"), <gap/>)
    => string-join("")
};

declare
    %test:assertEquals("[^1]&#10;&#10;[^1]: Hello")
function tmd:note() as xs:string {
    let $note := pmf:note($tmd:CFG, <n/>, ("note"), "Hello", "footnote", "1")
    return
        pmf:finish($tmd:CFG, $note)
};

declare
    %test:assertEquals("Hello[^1] World.&#10;&#10;[^1]: Hello")
function tmd:note-in-paragraph() as xs:string {
    let $note := pmf:note($tmd:CFG, <n/>, ("note"), "Hello", "footnote", "1")
    let $paragraph := pmf:paragraph($tmd:CFG, <n/>, ("paragraph"), 
        (text { "Hello" }, $note, text { " World." }))
    return
        pmf:finish($tmd:CFG, $paragraph)
};

declare
    %test:assertEquals("[^a]&#10;&#10;[^a]: Hello")
function tmd:note-custom-marker() as xs:string {
    let $note := pmf:note($tmd:CFG, <n/>, ("note"), "Hello", "footnote", "a")
    return
        pmf:finish($tmd:CFG, $note)
};

declare
    %test:assertEquals("```&#10;Hello&#10;```&#10;&#10;")
function tmd:code() as xs:string {
    pmf:finish($tmd:CFG, <root>{pmf:code($tmd:CFG, <n/>, ("code"), "Hello", ())}</root>)
    => string-join("")
};

declare
    %test:assertEquals("```text&#10;Hello&#10;```&#10;&#10;")
function tmd:code-with-language() as xs:string {
    pmf:finish($tmd:CFG, <root>{pmf:code($tmd:CFG, <n/>, ("code"), "Hello", "text")}</root>)
    => string-join("")
};

declare
    %test:assertEquals("`abc`")
function tmd:pass-through() as xs:string {
    pmf:finish($tmd:CFG, <root>{pmf:pass-through($tmd:CFG, <n/>, ("code"), "`abc`")}</root>)
    => string-join("")
};