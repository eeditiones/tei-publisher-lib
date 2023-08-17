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
module namespace pmf="http://existsolutions.com/xquery/functions/tei";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $pmf:INLINE_ELEMENTS := (
    "hi", "supplied", "add", "del", "persName", "placeName", "term", "foreign", "title", "ref", "unclear",
    "sic", "corr", "reg", "distinct", "quote" 
);

declare function pmf:finish($config as map(*), $input as node()*) {
    pmf:create-divisions(pmf:combine($input))
    (: $input :)
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
    <item xmlns="http://www.tei-c.org/ns/1.0" pmf:level="{$optional?level}">
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

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id as item()*, $optional as map(*)) {
    <anchor xmlns="http://www.tei-c.org/ns/1.0" xml:id="{$id}">
    { 
        pmf:apply-optional-attributes($optional)
    }
    </anchor>
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
    <graphic xmlns="http://www.tei-c.org/ns/1.0" url="{$url}">
    { if ($title) then <desc>{pmf:apply-children($config, $node, $title)}</desc> else () }
    </graphic>
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label, $optional as map(*)) {
    <note xmlns="http://www.tei-c.org/ns/1.0" place="{$place}">
    { if ($label) then attribute n { $label } else () }
    { 
        pmf:apply-optional-attributes($optional)
    }
    { pmf:apply-children($config, $node, $content) }
    </note>
};

declare %private function pmf:apply-optional-attributes($optional as map(*)) {
    map:for-each($optional, function($key, $value) {
        attribute { $key } { $value }
    })
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content, $optional as map(*)) {
    if (map:contains($optional, "tei_element")) then
        element { QName("http://www.tei-c.org/ns/1.0", $optional?tei_element) } {
            pmf:copy-attributes($optional?tei_attributes),
            pmf:apply-children($config, $node, $content)
        }
    else
        pmf:apply-children($config, $node, $content)
};

declare %private function pmf:copy-attributes($args as xs:string*) {
    if (exists($args)) then
        for $arg in $args
        let $ana := analyze-string($arg, '^(.*?)\s*=\s*(.*)\s*$')
        return
            try {
                attribute { $ana//fn:group[1]/string() } { $ana//fn:group[2]/string() }
            } catch * {
                ()
            }
    else
        ()
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
    if (local-name($content)='teiHeader') then 
        pmf:apply-children($config, $node, $content)
    else
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

declare %private function pmf:create-divisions($tei as element(tei:TEI)) {
    let $body := $tei/tei:text/tei:body
    let $firstHead := $body/tei:head[1]
    return
        if ($firstHead) then
            <TEI xmlns="http://www.tei-c.org/ns/1.0">
                { $tei/tei:teiHeader }
                <text>
                    <body>
                    {
                        $body/@*,
                        pmf:wrap-divisions($body/node())
                    }
                    </body>
                </text>
            </TEI>
        else
            $tei
};

(:~
 : Wrap headings and following text into a hierarchy of divisions using a "tumbling window" approach.
 :)
declare function pmf:wrap-divisions($body-nodes as node()*) {
    if ($body-nodes) then
        let $this := $body-nodes => head()
        let $rest := $body-nodes => tail()
        return
            if ($this instance of element(tei:head)) then
                let $level := number(head(($this/@pmf:level, 0)))
                let $next-window-start := $this/following-sibling::tei:head[@pmf:level <= $level] => head()
                let $next-window := $body-nodes[. is $next-window-start or . >> $next-window-start]
                let $this-window-rest :=
                    if ($next-window) then
                        $body-nodes[. >> $this and . << $next-window-start]
                    else
                        $body-nodes[. >> $this]
                return
                    (
                        <div xmlns="http://www.tei-c.org/ns/1.0">
                            <head>
                            {
                                $this/@* except $this/@pmf:level,
                                $this/node()
                            }
                            </head>
                            { $this-window-rest => pmf:wrap-divisions() }
                        </div>,
                        $next-window => pmf:wrap-divisions()
                    )

            else
                (
                    $this,
                    $rest => pmf:wrap-divisions()
                )
    else
        ()
};

declare %private function pmf:wrap-list($items as element()*) {
    if ($items) then
        let $item := head($items)
        return
            let $nested :=
                pmf:get-following-nested($item/following-sibling::*, (), $item/@pmf:level)
            return (
                <item xmlns="http://www.tei-c.org/ns/1.0">
                    <p>{ $item/node() }</p>
                    {
                        if ($nested) then
                            <list>
                            { if ($nested[1]/@pmf:type) then attribute type { $nested[1]/@pmf:type } else () }
                            { pmf:wrap-list($nested) }
                            </list>
                        else
                            ()
                    }
                </item>,
                pmf:wrap-list(tail($items) except $nested)
            )
    else
        ()
};

declare %private function pmf:get-following($nodes as node()*, $name as xs:string, $siblings as node()*,
    $level as item()?) {
    let $node := head($nodes)
    return
        if (local-name($node) = $name and (empty($level) or number($node/@pmf:level) >= number($level))) then
            pmf:get-following(tail($nodes), $name, ($siblings, $node), $level)
        else
            $siblings
};

declare %private function pmf:get-following-nested($nodes as node()*, $siblings as node()*,
    $level as item()?) {
    let $node := head($nodes)
    return
        if ($node instance of element(tei:item) and (empty($level) or number($node/@pmf:level) > number($level))) then
            pmf:get-following-nested(tail($nodes), ($siblings, $node), $level)
        else
            $siblings
};

declare %private function pmf:combine($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(tei:item) return
                if ($node/preceding-sibling::node()[1][self::tei:item]) then
                    ()
                else
                    let $sibs := pmf:get-following($node/following-sibling::*, "item", (), $node/@pmf:level)
                    return (
                        <list xmlns="http://www.tei-c.org/ns/1.0">
                        { if ($node/@pmf:type) then attribute type { $node/@pmf:type } else () }
                        { pmf:wrap-list(($node, $sibs)) }
                        </list>
                    )
            case element(tei:code) | element(tei:tag) return
                $node
            case element() return
                (: if the node being processed is a lb element preceded and followed by
                the same element (excluding thus text nodes), do not process it :)
                if ($node/local-name(.) eq 'lb' and 
                $node/preceding-sibling::node()[1][local-name(.) ne '']/local-name(.) = 
                        $node/following-sibling::node()[1]/local-name(.)) 
                        then () 
                        else 
                    if (local-name($node) = $pmf:INLINE_ELEMENTS) then
                        if ($node/preceding-sibling::node()[1][local-name(.) = local-name($node)] 
                            or
                             (: if the node we are processing is not a text node, and it’s preceded 
                             by an lb preceded by the same type of element as the current element, 
                             do not process it :)
                            $node[local-name(.) ne '']/preceding-sibling::node()[1][local-name(.) = 'lb']/
                            preceding-sibling::node()[1][local-name(.) = local-name($node)]) then
                            ()
                        else
                            (: if the  current node is not  text node, and it’s followed by and lb and then
                            a element of the same type than the current node, combine the elements :)
                            if ($node[local-name(.) ne '']/following-sibling::node()[1][local-name(.) = 'lb']/
                                following-sibling::node()[1][local-name(.) = local-name($node)])
                            then 
                                element { node-name($node) } {
                                            $node/@*,
                                            pmf:combine($node/node()),
                                            pmf:combine($node/following-sibling::node()[1]),
                                            pmf:combine($node/following-sibling::node()[1]/following-sibling::node()[1]/node())
                                        }
                            else                            
                                let $following := pmf:get-following($node/following-sibling::node(), local-name($node), (), ())
                                return
                                    if ($following) then
                                        element { node-name($node) } {
                                            $node/@*,
                                            pmf:combine($node/node()),
                                            pmf:combine($following/node())
                                        }
                                    else
                                        element { node-name($node) } {
                                            $node/@*,
                                            pmf:combine($node/node())
                                        }
                    else
                        element { node-name($node) } {
                            $node/@*,
                            pmf:combine($node/node())
                        }
            case text() return
                if (matches($node, '^(.*?)&#60;.*&#62;.*$')) then
                    replace($node, '^(.*?)&#60;.*&#62;(.*)$', '$1$2')
                else
                    $node
            default return $node
};
