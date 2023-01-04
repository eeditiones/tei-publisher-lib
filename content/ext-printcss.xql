xquery version "3.1";

(:~
 : Extension functions for HTML with CSS for Print.
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/printcss";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace html="http://www.tei-c.org/tei-simple/xquery/functions";

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    <span class="{$class} footnote">
    { html:apply-children($config, $node, $content) }
    </span>
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default, $alternate) {
    <span class="{$class}">
        <span class="default">
        { html:apply-children($config, $node, $default) }
        </span>
        <span class="alternate">
        { html:apply-children($config, $node, $alternate) }
        </span>
    </span>
};