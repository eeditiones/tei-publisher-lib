(:
 :
 :  Copyright (C) 2015 Wolfgang Meier
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
 : Function module to produce HTML output. The functions defined here are called
 : from the generated XQuery transformation module. Function names must match
 : those of the corresponding TEI Processing Model functions.
 :
 : @author Wolfgang Meier
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/fo";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace fo="http://www.w3.org/1999/XSL/Format";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace counters="http://www.tei-c.org/tei-simple/xquery/counters";
import module namespace css="http://www.tei-c.org/tei-simple/xquery/css";

declare variable $pmf:CSS_PROPERTIES := (
    "font-family",
    "font-weight",
    "font-style",
    "font-size",
    "font-variant",
    "text-align",
    "text-indent",
    "text-decoration",
    "text-transform",
    "line-height",
    "color",
    "background-color",
    "border",
    "border-left",
    "border-right",
    "border-bottom",
    "border-top",
    "margin",
    "padding",
    "margin-top",
    "margin-bottom",
    "margin-left",
    "margin-right",
    "wrap-option",
    "linefeed-treatment",
    "white-space-collapse",
    "white-space-treatment"
);

declare variable $pmf:NOTE_COUNTER_ID := "notes-" || util:uuid();

declare function pmf:init($config as map(*), $node as node()*) {
    let $renditionStyles := string-join(css:rendition-styles-html($config, $node))
    let $styles := if ($renditionStyles) then css:parse-css($renditionStyles) else map {}
    return
        map:merge(($config, map:entry("rendition-styles", $styles)))
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "paragraph" || " (" || string-join($class, ", ") || ")"},
    <fo:block>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content)
    }
    </fo:block>
};

declare function pmf:heading($config as map(*), $node as node(), $class as xs:string+, $content, $level) {
    let $level :=
        if ($level) then
            $level
        else if ($content instance of node()) then
            max((count($content/ancestor::tei:div), 1))
        else 1
    let $class := $class[not(starts-with(., "tei-head"))]
    let $defaultStyle := $config?default-styles("tei-head" || $level)
    return
        if ($node/parent::tei:table) then
            let $cols := sum(
                for $cell in $node/following-sibling::tei:row[1]/tei:cell
                return
                    ($cell/@cols/number(), 1)[1]
            )
            return
                <fo:table-row>
                    <fo:table-cell number-columns-spanned="{$cols}">
                        <fo:block>
                        {
                            pmf:check-styles($config, $node, $class, $defaultStyle),
                            $config?apply-children($config, $node, $content)
                        }
                        </fo:block>
                    </fo:table-cell>
                </fo:table-row>
        else (
            comment { "heading level " || $level || " (" || string-join(("tei-head" || $level, $class), ", ") || ")"},
            <fo:block>
            {
                pmf:check-styles($config, $node, $class, $defaultStyle),
                if ($level = 1 and $content instance of node() and exists($content/ancestor::tei:body)) then
                    let $content := string-join($content)
                    return
                        if (string-length($content) > 60) then
                            ()
                        else
                            <fo:marker marker-class-name="heading">
                            { $content }
                            </fo:marker>
                else
                    (),
                $config?apply-children($config, $node, $content)
            }
            </fo:block>
        )
};

declare function pmf:list($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    comment { "list" || " (" || string-join($class, ", ") || ")"},
    let $label-length :=
        if ($node/tei:label) then
            max($node/tei:label ! string-length(.))
        else
            1
    return
        <fo:list-block provisional-distance-between-starts="{$label-length}em">
        {
            pmf:check-styles($config, $node, $class, ()),
            $config?apply(map:merge(($config, map:entry("listType", $type))), $content)
        }
        </fo:list-block>
};

declare function pmf:listItem($config as map(*), $node as node(), $class as xs:string+, $content, $n) {
    comment { "listItem" || " (" || string-join($class, ", ") || ")"},
    let $label :=
        if ($node/../tei:label) then
            $node/preceding-sibling::*[1][self::tei:label]
        else if ($n) then
            $n
        else if ($config?listType = 'ordered') then
            count($node/preceding-sibling::*) + 1 || "."
        else
            "&#8226;"
    return
        <fo:list-item>
            { pmf:check-styles($config, $node, $class, ()) }
            <fo:list-item-label>
            {
                pmf:check-styles($config, $node, "tei-listItem-label", (), false()),
                <fo:block>{$label}</fo:block>
            }
            </fo:list-item-label>
            <fo:list-item-body start-indent="body-start()">
                <fo:block>
                {
                    $config?apply-children($config, $node, $content)
                }
                </fo:block>
            </fo:list-item-body>
        </fo:list-item>
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "block" || " (" || string-join($class, ", ") || ")"},
    <fo:block>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content)
    }
    </fo:block>
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content as item()*, $place as xs:string?, $label) {
(:    let $number := count($node/preceding::tei:note):)
    let $number := counters:increment($pmf:NOTE_COUNTER_ID)
    return
        <fo:footnote>
            <fo:inline>
            {pmf:check-styles($config, $node, "tei-note", ())}
            {$number}
            </fo:inline>
            <fo:footnote-body start-indent="0mm" end-indent="0mm" text-indent="0mm" white-space-treatment="ignore-if-surrounding-linefeed">
                <fo:list-block>
                    <fo:list-item>
                        <fo:list-item-label end-indent="label-end()" >
                            <fo:block>
                            {pmf:check-styles($config, (), "tei-note-body", ())}
                            { $number }
                            </fo:block>
                        </fo:list-item-label>
                        <fo:list-item-body start-indent="body-start()">
                            {pmf:check-styles($config, (), "tei-note-body", ())}
                            <fo:block>{$config?apply-children($config, $node, $content)}</fo:block>
                        </fo:list-item-body>
                    </fo:list-item>
                </fo:list-block>
            </fo:footnote-body>
        </fo:footnote>
};

declare function pmf:section($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "section" || " (" || string-join($class, ", ") || ")"},
    <fo:block>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content)
    }
    </fo:block>
};

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id as item()*) {
    <fo:inline id="{$id}"/>
};

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $link) {
    if (empty($link) or $link = "#") then
        (: Make sure not to produce an empty destination, which would cause an FO error :)
        $config?apply-children($config, $node, $content)
    else if (starts-with($link, "#")) then
        <fo:basic-link internal-destination="{substring-after($link, '#')}">
        {
            pmf:check-styles($config, $node, $class, ()),
            $config?apply-children($config, $node, $content)
        }
        </fo:basic-link>
    else
        <fo:basic-link external-destination="{$link}">
        {
            pmf:check-styles($config, $node, $class, ()),
            $config?apply-children($config, $node, $content)
        }
        </fo:basic-link>
};

declare function pmf:escapeChars($text as item()) {
    typeswitch($text)
        case attribute() return
            data($text)
        default return
            $text
};

declare function pmf:glyph($config as map(*), $node as node(), $class as xs:string+, $content as xs:anyURI?) {
    if ($content = "char:EOLhyphen") then
        "&#xAD;"
    else
        ()
};

declare function pmf:figure($config as map(*), $node as node(), $class as xs:string+, $content, $title) {
    <fo:block>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content),
        if ($title) then
            <fo:block>
            {
                pmf:check-styles($config, $node, "tei-caption", (), false()),
                $config?apply-children($config, $node, $title)
            }
            </fo:block>
        else
            ()
    }
    </fo:block>
};

declare function pmf:graphic($config as map(*), $node as node(), $class as xs:string+, $content, $url,
    $width, $height, $scale, $title) {
    let $src :=
        if (matches($url, "^\w+://")) then
            $url
        else
            request:get-scheme() || "://" || request:get-server-name() || ":" || request:get-server-port() ||
            request:get-context-path() || "/rest/" || util:collection-name($node) || "/" || $url
    let $width := if ($scale) then (100 * $scale) || "%" else $width
    let $height := if ($scale) then (100 * $scale) || "%" else $height
    return
        <fo:external-graphic src="url({$src})" scaling="uniform"
            content-width="{($width, 'scale-to-fit')[1]}"
            content-height="{($height, 'scale-to-fit')[1]}">
        {
             pmf:check-styles($config, $node, $class, ())
        }
        { comment { string-join($class, ", ") } }
        </fo:external-graphic>
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content as item()*) {
    <fo:inline>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content),
        pmf:get-after($config, $class)
    }
    </fo:inline>
};

declare function pmf:text($config as map(*), $node as node(), $class as xs:string+, $content as item()*) {
    string($content)
};

declare function pmf:cit($config as map(*), $node as node(), $class as xs:string+, $content, $source) {
    comment { "cit (" || string-join($class, ", ") || ")"},
    <fo:block>
    {
        pmf:check-styles($config, $node, ($class, "cit"), ()),
        $config?apply-children($config, $node, $content)
    }
    </fo:block>,
    if ($source) then
        <fo:block>
        {
            pmf:check-styles($config, $node, ($class, "cit-source"), ()),
            $config?apply-children($config, $node, $source)
        }
        </fo:block>
    else
        ()
};

declare function pmf:body($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "body" || " (" || string-join($class, ", ") || ")"},
    <fo:block>
    {
        pmf:check-styles($config, $node, $class, ()),
        $config?apply-children($config, $node, $content)
    }
    </fo:block>
};

declare function pmf:index($config as map(*), $node as node(), $class as xs:string+, $content, $type as xs:string) {
    ()
};

declare function pmf:break($config as map(*), $node as node(), $class as xs:string+, $content, $type as xs:string, $label as item()*) {
    switch($type)
        case "page" return
            ()
        default return
            <fo:block/>,
    comment { $type || " - " || $label || " (" || string-join($class, ", ") || ")" }
};

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    let $counter := counters:create($pmf:NOTE_COUNTER_ID)
    let $odd := doc($config?odd)
    let $config := pmf:load-styles(pmf:load-default-styles($config), $odd)
    let $root := $node/ancestor-or-self::tei:TEI
    let $language := ($root/@xml:lang, $root/tei:teiHeader/@xml:lang, "en")[1]
    return
        <fo:root xmlns:fo="http://www.w3.org/1999/XSL/Format">
        {
            pmf:load-xml($config, "master.fo.xml")
        }
        {
            comment { "document (" || string-join($class, ", ") || ")"},
            pmf:load-page-sequence($config, $node, $content, $language)
        }
        </fo:root>
};

declare function pmf:metadata($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:title($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:table($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "table" || " (" || string-join($class, ", ") || ")"},
    <fo:table>
        { pmf:check-styles($config, $node, $class, ()) }
        <fo:table-body>
        {
            pmf:check-styles($config, $node, "tei-table-body", (), false()),
            $config?apply-children($config, $node, $content)
        }
        </fo:table-body>
    </fo:table>
};

declare function pmf:row($config as map(*), $node as node(), $class as xs:string+, $content) {
    comment { "row" || " (" || string-join($class, ", ") || ")"},
    <fo:table-row>
    { $config?apply-children($config, $node, $content) }
    </fo:table-row>
};

declare function pmf:cell($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    comment { "cell" || " (" || string-join($class, ", ") || ")"},
    <fo:table-cell>
        {
            pmf:check-styles($config, $node, $class, ()),
            if ($node/@cols) then
                attribute number-columns-spanned { $node/@cols }
            else
                (),
            if ($node/@rows) then
                attribute number-rows-spanned { $node/@rows }
            else
                ()
        }
        <fo:block>
        {$config?apply-children($config, $node, $content)}
        </fo:block>
    </fo:table-cell>
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default,
    $alternate) {
    $config?apply-children($config, $node, $default),
    pmf:note($config, $node, $class, $alternate, "footnote", ())
};

declare function pmf:omit($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:load-page-sequence($config as map(*), $node as node(), $content as node()*, $language as xs:string?) {
    let $xml := pmf:load-xml($config, "page-sequence.fo.xml")//fo:page-sequence
    return
        pmf:parse-page-sequence($config, $xml, $node, $content, $language)
};

declare function pmf:parse-page-sequence($config as map(*), $nodes as node()*, $context as node(), $content as node()*, $language as xs:string?) {
    for $node in $nodes
    return
        typeswitch($node)
            case document-node() return
                pmf:parse-page-sequence($config, $node/*, $context, $content, $language)
            case element(fo:flow) return
                element { node-name($node) } {
                    $node/@* except ($node/@language, $node/@xml:lang),
                    attribute language { $language },
                    attribute xml:lang { $language },
                    $config?apply-children($config, $context, $content),
                    counters:destroy($pmf:NOTE_COUNTER_ID)[2]
                }
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    pmf:parse-page-sequence($config, $node/node(), $context, $content, $language)
                }
            default return
                $node
};



declare function pmf:get-before($config as map(*), $classes as xs:string*) {
    for $class in $classes
    let $before := $config?styles?($class || ":before")
    return
        if (exists($before)) then <fo:inline>{$before?content}</fo:inline> else ()
};

declare function pmf:get-after($config as map(*), $classes as xs:string*) {
    for $class in $classes
    let $after := $config?styles?($class || ":after")
    return
        if (exists($after)) then <fo:inline>{$after?content}</fo:inline> else ()
};

declare function pmf:check-styles($config as map(*), $node as node()?, $classes as xs:string*, $default as map(*)?) {
    pmf:check-styles($config, $node, $classes, $default, true())
};

declare function pmf:check-styles($config as map(*), $node as node()?, $classes as xs:string*, $default as map(*)?, $declareId as xs:boolean?) {
    if ($declareId and $node/@xml:id) then
        attribute id { $node/@xml:id }
    else
        (),
    let $defaultStyles :=
        if (exists($default)) then
            map:merge(($default, $classes ! $config?default-styles(.)))
        else
            map:merge($classes ! $config?default-styles(.))
    let $stylesForClass :=
        map:merge(
            for $class in $classes
            return (
                pmf:filter-styles($config?styles?($class)),
                pmf:filter-styles($config?rendition-styles?($class))
            )
        )
    let $styles :=
        if (exists($stylesForClass)) then
            pmf:merge-maps($stylesForClass, $defaultStyles)
        else
            $defaultStyles
    return
        if (exists($styles)) then
            for $style in map:keys($styles)
            return
                attribute { $style } { translate($styles($style), '"', "'") }
        else
            (),
    pmf:get-before($config, $classes)
};

declare %private function pmf:filter-styles($styles as map(*)?) {
    if (exists($styles)) then
        map:keys($styles)[. = $pmf:CSS_PROPERTIES] ! map:entry(., $styles(.))
    else
        ()
};

declare %private function pmf:merge-maps($map as map(*), $defaults as map(*)?) {
    if (empty($defaults)) then
        $map
    else if (empty($map)) then
        $defaults
    else
        map:merge(($defaults, $map))
};

declare %private function pmf:merge-styles($map as map(*)?, $defaults as map(*)?) {
    if (empty($defaults)) then
        $map
    else if (empty($map)) then
        $defaults
    else
        map:merge((
            map:for-each($map, function($key, $value) {
                map:entry($key, map:merge(($defaults($key), $map($key))))
            }),
            map:for-each($defaults, function($key, $value) {
                if (map:contains($map, $key)) then
                    ()
                else
                    map:entry($key, $value)
            })
        ))
};

declare function pmf:load-styles($config as map(*), $root as document-node()) {
    let $css := css:generate-css($root, "fo", $config?odd)
    let $styles := css:parse-css($css)
    let $styles :=
        map:merge(($config, map:entry("styles", $styles)))
    return
        $styles
};

declare function pmf:load-default-styles($config as map(*)) {
    let $oddName := replace($config?odd, "^.*/([^/\.]+)\.?.*$", "$1")
    let $path := $config?collection || "/" || $oddName || ".fo.css"
    let $userStyles := pmf:read-css($path)
    let $systemCss := repo:get-resource("http://existsolutions.com/apps/tei-publisher-lib", "content/styles.fo.css")
    let $systemStyles := pmf:read-css-string($systemCss)
    let $merged := pmf:merge-styles($userStyles, $systemStyles)
    return
        map:merge(($config, map:entry("default-styles", $merged)))
};

declare function pmf:load-xml($config as map(*), $file as xs:string) {
    let $path := $config?collection || "/" || $file
    let $doc :=
        if (doc-available($path)) then
            doc($path)
        else
            let $systemDoc := repo:get-resource("http://existsolutions.com/apps/tei-publisher-lib", "content/" || $file)
            return
                parse-xml(util:binary-to-string($systemDoc))
    return
        $doc
};

declare function pmf:read-css($path) {
	if (util:binary-doc-available($path)) then
        let $css := util:binary-to-string(util:binary-doc($path))
        return
            css:parse-css($css)
    else
        ()
};

declare function pmf:read-css-string($data as xs:base64Binary?) {
    let $css := util:binary-to-string($data)
    return
        css:parse-css($css)
};
