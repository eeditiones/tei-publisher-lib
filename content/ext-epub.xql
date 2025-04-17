xquery version "3.1";

(:~
 : Extension functions for epub generation.
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/epub";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace epub="http://www.idpf.org/2007/ops";

import module namespace html="http://www.tei-c.org/tei-simple/xquery/functions";
import module namespace counters="http://www.tei-c.org/tei-simple/xquery/counters";

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <div class="{$class}">
    {
        if ($node/@xml:id) then
            ()
        else
            attribute id { translate(if ($node/@exist:id) then "N" || $node/@exist:id else generate-id($node), ".", "_") },
        html:apply-children($config, $node, $content)
    }
    </div>
};

declare function pmf:break($config as map(*), $node as node(), $class as xs:string+, $content, $type, $label) {
    switch($type)
        case "page" return
            if ($label) then
                <span class="pagebreak {$class}" id="page{$label}" epub:type="pagebreak">{$label}</span>
            else
                <span id="page{translate(generate-id($node), ".", "_")}" epub:type="pagebreak" class="pagebreak {$class}">[{$config?apply-children($config, $node, $content)}]</span>
        default return
            <br/>
};

declare function pmf:cells($config as map(*), $node as node(), $class as xs:string+, $content) {
    <tr>
    {
        for $cell in $content/node() | $content/@*
        return
            <td class="{$class}">{$config?apply-children($config, $node, $cell)}</td>
    }
    </tr>
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    let $id := translate(generate-id($node), ".", "_")
    return (
        <a epub:type="noteref" href="#fn{$id}" class="noteref">
        { counters:increment($html:NOTE_COUNTER_ID) }
        </a>,
        <aside epub:type="footnote" id="fn{$id}" class="note {$class}">
        { $config?apply($config, $content/node()) }
        </aside>
    )
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default,
    $alternate) {
    let $id := translate(generate-id($node), ".", "_")
    return (
        <a epub:type="noteref" href="#fn{$id}" class="alternate {$class}">
        { html:apply-children($config, $node, $default) }
        </a>,
        <aside epub:type="footnote" id="fn{$id}" class="altcontent {$class}">
        { html:apply-children($config, $node, $alternate) }
        </aside>
    )
};
