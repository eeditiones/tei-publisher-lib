(:
 :
 :  Copyright (C) 2025 e-editiones.org
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : Function module to produce Markdown output. The functions defined here are called
 : from the generated XQuery transformation module. Function names must match
 : those of the corresponding TEI Processing Model functions.
 :
 : @author Wolfgang Meier
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/markdown";

import module namespace css="http://www.tei-c.org/tei-simple/xquery/css";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $pmf:INDENT := "    ";

(:~
 : Initialize the configuration map. Read CSS styles from the ODD and add
 : them to the configuration map as "styles".
 :
 : @param config The configuration map.
 : @param node The node.
 : @return The initialized configuration map.
 :)
declare function pmf:init($config as map(*), $node as node()*) {
    let $css := css:generate-css(doc($config?odd), "md", $config?odd)
    let $styles := css:parse-css($css)
    return
        map:merge(($config, map:entry("styles", $styles), map:entry("indent", "")))
};

declare function pmf:prepare($config as map(*), $node as node()*) {
    ()
};

(:~
 : Process output by 1) combining consecutive text nodes, 2) removing leading spaces,
 : 3) adding back spaces where needed, 4) outputting footnotes below text.
 :
 : @param config The configuration map.
 : @param input The input nodes.
 : @return The processed nodes.
 :)
declare function pmf:finish($config as map(*), $input as node()*) {
    let $text := (
        <root>{pmf:remove-notes($input)}</root> => pmf:normalize-text() => pmf:leading-spaces() => pmf:readd-spaces(),
        (: Output footnotes below text :)
        for $note at $pos in $input/descendant-or-self::note
        let $content := pmf:normalize-text($note/node()) => pmf:leading-spaces() => pmf:readd-spaces()
        return
            string-join(("&#10;&#10;", $note/@n/string(), ": ",  $content), '')
    )
    return
        replace(string-join($text, ""), "\n{3,}", "&#10;&#10;")
};

declare %private function pmf:remove-notes($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(note) return
                ()
            case element() return
                element {node-name($node)} {
                    $node/@*,
                    pmf:remove-notes($node/node())
                }
            default return
                $node
};

(:~
 : Normalize by combining consecutive text nodes.
 :
 : @param nodes The nodes to normalize.
 : @return The normalized nodes.
 :)
declare %private function pmf:normalize-text($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(note) return
                ()
            case element() return
                element {node-name($node)} {
                    $node/@*,
                    pmf:normalize-text($node/node())
                }
            case text() return
                if ($node/preceding-sibling::node()[1] instance of text()) then
                    ()
                else
                    text {
                        $node,
                        pmf:consume-text($node/following-sibling::node())
                    }
            default return
                $node
};

declare %private function pmf:consume-text($nodes as node()*) {
    if (head($nodes) instance of text()) then
        (string(head($nodes)), pmf:consume-text(tail($nodes)))
    else
        ()
};

(:~
 : Remove leading spaces from the nodes. The nodes must have been normalized first.
 :
 : @param nodes The nodes to remove leading spaces from.
 : @return The nodes with leading spaces removed.
 :)
declare %private function pmf:leading-spaces($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
            case text() return
                text {
                    (: remove leading spaces :)
                    replace($node, "^\s+", "", "m")
                    (: replace remaining newlines with spaces :)
                    => replace("\n", " ", "m")
                    (: replace($node, "(\S)\n\s+", "$1 ") :)
                }
            case element(root) return
                pmf:leading-spaces($node/node())
            case element() return
                $node
            default return
                pmf:leading-spaces($node/node())
};

declare %private function pmf:readd-spaces($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch ($node)
            case element(indent) return
                string($node/@indent)
            case element(lb) return
                "&#10;"
            case element(lb2) return
                "&#10;&#10;"
            case text() return
                $node
            default return
                pmf:readd-spaces($node/node())
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    if (not($node/preceding-sibling::*)) then () else <indent indent="{$config?indent}"/>,
    $config?apply-children($config, $node, $content),
    <lb2/>
};

declare function pmf:heading($config as map(*), $node as node(), $class as xs:string+, $content, $level) {
    let $level :=
        if ($level) then
            $level
        else if ($content instance of element()) then
            if ($config?parameters?root and $content/@exist:id) then
                let $node := util:node-by-id($config?parameters?root, $content/@exist:id)
                return
                    max((count($node/ancestor::tei:div), 1))
            else
                max((count($content/ancestor::tei:div), 1))
        else
            4
    return (
        <lb/>,
        <indent indent="{$config?indent}"/>,
        text { string-join((for $i in 1 to $level return "#"), "") },
        text { " " },
        $config?apply-children($config, $node, $content),
        <lb2/>
    )
};

declare function pmf:list($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    if ($node/tei:label) then
        $config?apply-children($config, $node, $content)
    else (
        let $newConfig := map:merge((
            $config,
            map { "listType": $type }
        ))
        return
            $config?apply-children($newConfig, $node, $content),
        <lb/>
    )
};

declare function pmf:listItem($config as map(*), $node as node(), $class as xs:string+, $content, $n) {
    let $label :=
        if ($node/../tei:label) then
            $node/preceding-sibling::*[1][self::tei:label]
        else if ($n) then
            $n
        else
            ()
    let $newConfig := map:merge((
        $config,
        map { "indent": string-join(($config?indent, $pmf:INDENT), "") }
    ))
    return
        if ($label) then (
            <lb/>,
            text { "**" },
            $config?apply-children($config, $node, $label),
            text { "**" },
            <lb/>,
            <indent indent="{$config?indent}"/>,
            $config?apply-children($newConfig, $node, $content),
            <lb/>
        ) else (
            <lb/>,
            <indent indent="{$config?indent}"/>,
            text {
                if ($config?listType = "ordered") then count($node/preceding-sibling::*) + 1 || ". " else "+ "
            },
            $config?apply-children($newConfig, $node, $content)
        )
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <indent indent="{$config?indent}"/>,
    $config?apply-children($config, $node, $content),
    <lb2/>
};

declare function pmf:section($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:block($config, $node, $class, $content)
};

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id as item()*) {
    text { "<a id='" || $id || "'></a>" }
};

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $uri, $target, $optional as map(*)) {
    let $link := head(($uri, $optional?link))
    return (
        text { "[" },
        $config?apply-children($config, $node, $content),
        text { "](" },
        text { $link },
        text { ")" }
    )
};

declare function pmf:glyph($config as map(*), $node as node(), $class as xs:string+, $content) {
    if ($content = "char:EOLhyphen") then
        "&#xAD;"
    else
        ()
};

declare function pmf:figure($config as map(*), $node as node(), $class as xs:string+, $content, $title) {
    <lb/>,
    $config?apply-children($config, $node, $content),
    if ($title) then (
        <lb/>,
        text { "*" },
        $config?apply-children($config, $node, $title),
        text { "*" }
    ) else (),
    <lb/>
};

declare function pmf:graphic($config as map(*), $node as node(), $class as xs:string+, $content, $url,
    $width, $height, $scale, $title) {
    text { "![" },
    text { $title },
    text { "](" },
    text { $url },
    text { ")" }
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    let $nodeId :=
        if ($node/@xml:id) then
            $node/@xml:id
        else if ($node/@exist:id) then
            $node/@exist:id
        else
            util:node-id($node)
    let $id := translate($nodeId, "-.", "__")
    let $nr :=
        if ($label) then
            "[^" || $label || "]"
        else
            "[^" || $id || "]"
    return (
        text { $nr },
        <note n="{$nr}">
        {
            $config?apply-children($config, $node, $content)
        }
        </note>
    )
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:get-before($config, $class),
    let $styles := $config?styles?($class)
    return
        if (exists($styles)) then
            if ($styles("font-weight") = "bold") then
                (text { "**" }, $config?apply-children($config, $node, $content), text { "**" })
            else if ($styles("font-style") = "italic") then
                (text { "*" }, $config?apply-children($config, $node, $content), text { "*" })
            else if ($styles("text-decoration") = "line-through") then
                (text { "~~" }, $config?apply-children($config, $node, $content), text { "~~" })
            else
                $config?apply-children($config, $node, $content)
        else
            $config?apply-children($config, $node, $content),
    pmf:get-after($config, $class)
};

declare function pmf:text($config as map(*), $node as node(), $class as xs:string+, $content) {
    $content ! (
        typeswitch (.)
            case text() return
                .
            default return
                text { . }
    )
};

declare function pmf:escapeChars($text as item()*) {
    typeswitch($text)
        case attribute() return
            data($text)
        default return
            text { $text }            
};

declare function pmf:cit($config as map(*), $node as node(), $class as xs:string+, $content, $source) {
    <lb/>,
    text { "> " },
    $config?apply-children($config, $node, $content),
    if ($source) then (
        <lb/>,
        text { "> " },
        text { "— " },
        $config?apply-children($config, $node, $source)
    ) else ()
};

declare function pmf:body($config as map(*), $node as node(), $class as xs:string+, $content) {
    $config?apply-children($config, $node, $content)
};

declare function pmf:index($config as map(*), $node as node(), $class as xs:string+, $type, $content) {
    ()
};

declare function pmf:omit($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:break($config as map(*), $node as node(), $class as xs:string+, $content, $type as xs:string, $label as item()*) {
    switch($type)
        case "page" return
            text { "|", $label, "|" }
        default return
            ()
};

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    <root>{$config?apply-children($config, $node, $content)}</root>
};

declare function pmf:metadata($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:title($config as map(*), $node as node(), $class as xs:string+, $content) {
    $config?apply-children($config, $node, $content)
};

declare function pmf:table($config as map(*), $node as node(), $class as xs:string+, $content) {
    <lb/>,
    $config?apply-children($config, $node, $content),
    <lb/>
};

declare function pmf:row($config as map(*), $node as node(), $class as xs:string+, $content) {
    text { "|" },
    $config?apply-children($config, $node, $content),
    <lb/>,
    if (not($node/preceding-sibling::*)) then (
        text {
            "|",
            string-join(
                (1 to count($node/*)) ! "---",
                "|"
            ),
            "|"
        },
        <lb/>
    ) else
        ()
};

declare function pmf:cell($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    text { " " },
    $config?apply-children($config, $node, $content),
    text { " |" }
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default,
    $alternate, $optional as map(*)) {
    $config?apply-children($config, $node, $default)
};

declare function pmf:match($config as map(*), $node as node(), $content) {
    text { "==" },
    $config?apply-children($config, $node, $content),
    text { "==" }
};

declare %private function pmf:get-before($config as map(*), $classes as xs:string*) {
    for $class in $classes
    let $before := $config?styles?($class || ":before")
    return
        if (exists($before)) then text { $before?content } else ()
};

declare %private function pmf:get-after($config as map(*), $classes as xs:string*) {
    for $class in $classes
    let $after := $config?styles?($class || ":after")
    return
        if (exists($after)) then text { $after?content } else ()
};
