xquery version "3.1";

(:~
 : Extension functions for HTML with CSS for Print.
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/printcss";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace html="http://www.tei-c.org/tei-simple/xquery/functions";

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    let $fnClass := if ($place = 'margin') then 'margin-note' else 'footnote'
    return
        <span class="{$class} {$fnClass}">
        { html:apply-children($config, $node, $content) }
        </span>
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default, $alternate) {
    <span class="{$class}">{$config?apply-children($config, $node, $default)}</span>,
    pmf:note($config, $node, $class, $alternate, "footnote", ())
};