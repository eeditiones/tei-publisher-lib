(:
 :
 :  Copyright (C) 2019 Wolfgang Meier
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
module namespace pmf="http://existsolutions.com/xquery/functions/docx";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $pmf:INLINE_ELEMENTS := ("hi", "supplied");

declare function pmf:finish($config as map(*), $input as node()*) {
    pmf:fix-hierarchy($input)
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    <p xmlns="http://www.tei-c.org/ns/1.0">
    {
        pmf:apply-children($config, $node, $content)
    }
    </p>
};

declare function pmf:heading($config as map(*), $node as node(), $class as xs:string+, $content, $level) {
    <head xmlns="http://www.tei-c.org/ns/1.0" pmf:level="{$level}">
    {pmf:apply-children($config, $node, $content)}
    </head>
};

declare function pmf:list($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    <list xmlns="http://www.tei-c.org/ns/1.0" type="{$type}">
    {pmf:apply-children($config, $node, $content)}
    </list>
};

declare function pmf:listItem($config as map(*), $node as node(), $class as xs:string+, $content, $n,
    $optional as map(*)) {
    <item xmlns="http://www.tei-c.org/ns/1.0">
    {if ($optional?type) then attribute pmf:type { $optional?type } else ()}
    {if ($n) then attribute n { $n } else ()}
    {pmf:apply-children($config, $node, $content)}
    </item>
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <div xmlns="http://www.tei-c.org/ns/1.0">
    {pmf:apply-children($config, $node, $content)}
    </div>
};

declare function pmf:section($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:block($config, $node, $class, $content)
};

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id as item()*) {
    <anchor xmlns="http://www.tei-c.org/ns/1.0" xml:id="{$id}"/>
};

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $uri, $target) {
    <ref xmlns="http://www.tei-c.org/ns/1.0" target="{$uri}">
    {pmf:apply-children($config, $node, $content)}
    </ref>
};

declare function pmf:escapeChars($text as item()*) {
    typeswitch($text)
        case text() return
            $text
        default return
            text { $text }
};

declare function pmf:glyph($config as map(*), $node as node(), $class as xs:string+, $content) {
    if ($content = "char:EOLhyphen") then
        "&#xAD;"
    else
        ()
};

declare function pmf:figure($config as map(*), $node as node(), $class as xs:string+, $content, $title) {
    ()
};

declare function pmf:graphic($config as map(*), $node as node(), $class as xs:string+, $content, $url,
    $width, $height, $scale, $title) {
    ()
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    <note xmlns="http://www.tei-c.org/ns/1.0" place="{$place}">
    { pmf:apply-children($config, $node, $content) }
    </note>
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content, $optional as map(*)) {
    if ($optional?tei_element) then
        element { QName("http://www.tei-c.org/ns/1.0", $optional?tei_element) } {
            pmf:apply-children($config, $node, $content)
        }
    else
        pmf:apply-children($config, $node, $content)
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

declare function pmf:cit($config as map(*), $node as node(), $class as xs:string+, $content, $source) {
    <quote xmlns="http://www.tei-c.org/ns/1.0">
    { pmf:apply-children($config, $node, $content) }
    </quote>
};

declare function pmf:body($config as map(*), $node as node(), $class as xs:string+, $content) {
    <text xmlns="http://www.tei-c.org/ns/1.0">
        <body>
        { pmf:apply-children($config, $node, $content) }
        </body>
    </text>
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
            <pb xmlns="http://www.tei-c.org/ns/1.0">{pmf:apply-children($config, $node, $label)}</pb>
        default return
            <lb xmlns="http://www.tei-c.org/ns/1.0"/>
};

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    <TEI xmlns="http://www.tei-c.org/ns/1.0">{pmf:apply-children($config, $node, $content)}</TEI>
};

declare function pmf:metadata($config as map(*), $node as node(), $class as xs:string+, $content) {
    <teiHeader xmlns="http://www.tei-c.org/ns/1.0">{pmf:apply-children($config, $node, $content)}</teiHeader>
};

declare function pmf:title($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:table($config as map(*), $node as node(), $class as xs:string+, $content) {
    <table xmlns="http://www.tei-c.org/ns/1.0">
    {pmf:apply-children($config, $node, $content)}
    </table>
};

declare function pmf:row($config as map(*), $node as node(), $class as xs:string+, $content) {
    <row xmlns="http://www.tei-c.org/ns/1.0">
    {pmf:apply-children($config, $node, $content)}
    </row>
};

declare function pmf:cell($config as map(*), $node as node(), $class as xs:string+, $content, $type,
    $optional as map(*)) {
    <cell xmlns="http://www.tei-c.org/ns/1.0">
    {
        if ($optional?cols) then
            attribute cols { $optional?cols }
        else
            ()
    }
    {pmf:apply-children($config, $node, $content)}
    </cell>
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default,
    $alternate) {
    <choice xmlns="http://www.tei-c.org/ns/1.0">
    {pmf:apply-children($config, $node, $default)}
    {pmf:apply-children($config, $node, $alternate)}
    </choice>
};

declare function pmf:match($config as map(*), $node as node(), $content) {
    pmf:apply-children($config, $node, $content)
};

declare function pmf:apply-children($config as map(*), $node as node(), $content) {
    $node/@xml:id,
    $config?apply-children($config, $node, $content)
};

declare %private function pmf:fix-hierarchy($nodes as node()*) {
    if ($nodes) then
        let $node := head($nodes)
        return
            typeswitch($node)
                case element(tei:head) return
                    let $myLevel := number(head(($node/@pmf:level, 0)))
                    let $nextHeading := $node/following-sibling::tei:head[@pmf:level <= $myLevel]
                    let $children :=
                        if ($nextHeading) then
                            $node/following-sibling::node()[. << $nextHeading]
                        else
                            $node/following-sibling::node()
                    let $rest := tail($nodes) except $children
                    return (
                        <div xmlns="http://www.tei-c.org/ns/1.0">
                        { pmf:copy-element($node), pmf:fix-hierarchy($children) }
                        </div>,
                        pmf:fix-hierarchy($rest)
                    )
                case element(tei:item) return
                    if ($node/preceding-sibling::*[1][self::tei:item]) then (
                        pmf:copy-element($node),
                        pmf:fix-hierarchy(tail($nodes))
                    ) else
                        let $items := pmf:get-siblings($node/following-sibling::node(), (), "item")
                        return (
                            <list xmlns="http://www.tei-c.org/ns/1.0">
                            {
                                if ($node/@pmf:type) then
                                    attribute type { $node/@pmf:type }
                                else
                                    (),
                                pmf:copy-element($node),
                                pmf:fix-hierarchy($items)
                            }
                            </list>,
                            pmf:fix-hierarchy(tail($nodes) except $items)
                    )
                case element() return
                    if ($node/local-name() = $pmf:INLINE_ELEMENTS) then
                        if ($node/preceding-sibling::*[1][node-name(.) = node-name($node)]) then (
                            pmf:fix-hierarchy(($node/node(), tail($nodes)))
                        ) else
                            let $items := pmf:get-siblings($node/following-sibling::node(), (), local-name($node))
                            return (
                                element { node-name($node) } {
                                    $node/@*,
                                    pmf:fix-hierarchy(($node/node(), $items))
                                },
                                pmf:fix-hierarchy(tail($nodes) except $items)
                            )
                    else (
                        pmf:copy-element($node),
                        pmf:fix-hierarchy(tail($nodes))
                    )
                default return (
                    $node, pmf:fix-hierarchy(tail($nodes))
                )
    else
        ()
};

declare %private function pmf:copy-element($node as element()) {
    element { node-name($node)} {
        $node/@* except $node/@pmf:*,
        pmf:fix-hierarchy($node/node())
    }
};


declare %private function pmf:get-siblings($nodes as node()*, $siblings as node()*, $name as xs:string) {
    if ($nodes) then
        let $node := head($nodes)
        return
            if (local-name($node) = $name) then
                pmf:get-siblings(tail($nodes), ($siblings, $node), $name)
            else
                $siblings
    else
        $siblings
};
