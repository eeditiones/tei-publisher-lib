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
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace css="http://www.tei-c.org/tei-simple/xquery/css";
import module namespace counter="http://exist-db.org/xquery/counter" at "java:org.exist.xquery.modules.counter.CounterModule";

declare variable $pmf:NOTE_COUNTER_ID := "notes-" || util:uuid();

declare function pmf:prepare($config as map(*), $node as node()*) {
    let $styles := css:rendition-styles-html($config, $node)
    let $counter := counter:create($pmf:NOTE_COUNTER_ID)
    return
        if ($styles != "") then
            <style type="text/css">{ $styles }</style>
        else
            ()
};

declare function pmf:finish($config as map(*), $input as node()*) {
    let $destroy := counter:destroy($pmf:NOTE_COUNTER_ID)
    return
        $input
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    <p class="{$class}">
    {
        pmf:apply-children($config, $node, $content)
    }
    </p>
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
    return
        element { "h" || $level } {
            attribute class { $class },
            pmf:apply-children($config, $node, $content)
        }
};

declare function pmf:list($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    if ($node/tei:label) then
        <dl class="{$class}">
        { pmf:apply-children($config, $node, $content) }
        </dl>
    else
        let $listType := ($type, $node/@type)[1]
        return
            switch($listType)
                case "ordered" return
                    <ol class="{$class}">{pmf:apply-children($config, $node, $content)}</ol>
                default return
                    <ul class="{$class}">{pmf:apply-children($config, $node, $content)}</ul>
};

declare function pmf:listItem($config as map(*), $node as node(), $class as xs:string+, $content,
    $n) {
    let $label :=
        if ($node/../tei:label) then
            $node/preceding-sibling::*[1][self::tei:label]
        else
            ()
    return
        if ($label) then (
            <dt>{pmf:apply-children($config, $node, $label)}</dt>,
            <dd>{pmf:apply-children($config, $node, $content)}</dd>
        ) else
            <li class="{$class}">
            { if ($n) then attribute value { $n } else () }
            { pmf:apply-children($config, $node, $content) }
            </li>
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <div class="{$class}">{pmf:apply-children($config, $node, $content)}</div>
};

declare function pmf:section($config as map(*), $node as node(), $class as xs:string+, $content) {
    <section class="{$class}">{pmf:apply-children($config, $node, $content)}</section>
};

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id as item()*) {
    <span id="{$id}"/>
};

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $link) {
    <a href="{$link}" class="{$class}">{pmf:apply-children($config, $node, $content)}</a>
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
    <figure class="{$class}">
    { pmf:apply-children($config, $node, $content) }
    {
        if ($title) then
            <figcaption>{ pmf:apply-children($config, $node, $title) }</figcaption>
        else
            ()
    }
    </figure>
};

declare function pmf:graphic($config as map(*), $node as node(), $class as xs:string+, $content, $url,
    $width, $height, $scale, $title) {
    let $style := if ($width) then "width: " || $width || "; " else ()
    let $style := if ($height) then $style || "height: " || $height || "; " else $style
    return
        <img src="{$url}" class="{$class}" title="{$title}">
        { if ($node/@xml:id) then attribute id { $node/@xml:id } else () }
        { if ($style) then attribute style { $style } else () }
        </img>
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    switch ($place)
        case "margin" return
            if ($label) then (
                <span class="margin-note-ref">{$label}</span>,
                <span class="margin-note">
                    <span class="n">{$label/string()}) </span>{ $config?apply-children($config, $node, $content) }
                </span>
            ) else
                <span class="margin-note">
                { $config?apply-children($config, $node, $content) }
                </span>
        default return
            let $nodeId :=
                if ($node/@exist:id) then
                    $node/@exist:id
                else
                    util:node-id($node)
            let $id := translate($nodeId, "-.", "__")
            let $nr :=
                if ($label and ($label castable as xs:integer)) then
                    xs:integer($label)
                else
                    counter:next-value($pmf:NOTE_COUNTER_ID)
            let $content := $config?apply-children($config, $node, $content)
            return (
                <span id="fnref_{$id}" style="display:inline-block">
                    <a class="note" rel="footnote" href="#fn_{$id}">
                    {
                        $nr
                    }
                    </a>
                    {
                        if ($config?parameters?webcomponents) then
                            <paper-tooltip position="top" fit-to-visible-bounds="fit-to-visible-bounds">
                                {$content}
                            </paper-tooltip>
                        else
                            ()
                    }
                </span>,
                <li class="footnote" id="fn_{$id}" value="{$nr}">
                    <span class="fn-content">
                        {$content}
                    </span>
                    <a class="fn-back" href="#fnref_{$id}">↩</a>
                </li>
            )
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content) {
    <span class="{$class}">
    {
        $config?apply-children($config, $node, $content)
    }
    </span>
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
    <blockquote class="{$class}">
    {
        $config?apply-children($config, $node, $content),
        if ($source) then
            <cite>{$config?apply-children($config, $node, $source)}</cite>
        else
            ()
    }
    </blockquote>
};

declare function pmf:body($config as map(*), $node as node(), $class as xs:string+, $content) {
    <body class="{$class}">{pmf:apply-children($config, $node, $content)}</body>
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
            <span class="{$class}">{pmf:apply-children($config, $node, $label)}</span>
        default return
            <br class="{$class}"/>
};

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    <html class="{$class}">{pmf:apply-children($config, $node, $content)}</html>
};

declare function pmf:metadata($config as map(*), $node as node(), $class as xs:string+, $content) {
    <head class="{$class}">
        <title>{ pmf:apply-children($config, $node, $node/tei:fileDesc/tei:titleStmt/tei:title//text()) }</title>
        <meta name="author" content="{ $node/tei:fileDesc/tei:titleStmt/tei:author//text() }"/>
        {
            if (exists($config?styles)) then
                $config?styles?* !
                    <link rel="StyleSheet" type="text/css" href="{.}"/>
            else
                ()
        }
    </head>
};

declare function pmf:title($config as map(*), $node as node(), $class as xs:string+, $content) {
    <title>{pmf:apply-children($config, $node, $content)}</title>
};

declare function pmf:table($config as map(*), $node as node(), $class as xs:string+, $content) {
    <table class="{$class}">{pmf:apply-children($config, $node, $content)}</table>
};

declare function pmf:row($config as map(*), $node as node(), $class as xs:string+, $content) {
    <tr class="{$class}">{pmf:apply-children($config, $node, $content)}</tr>
};

declare function pmf:cell($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    element {if($type='head') then 'th' else 'td'} {
    attribute class {$class},
        if ($node/@cols) then
            attribute colspan { $node/@cols }
        else
            (),
        if ($node/@rows) then
            attribute rowspan { $node/@rows }
        else
        (),
        pmf:apply-children($config, $node, $content)
    }
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content, $default,
    $alternate) {
    if ($config?parameters?webcomponents) then
        <span class="alternate {$class}">
            <span class="default">{pmf:apply-children($config, $node, $default)}</span>
            <paper-tooltip position="bottom" fit-to-visible-bounds="fit-to-visible-bounds">{pmf:apply-children($config, $node, $alternate)}</paper-tooltip>
        </span>
    else
        <span class="alternate {$class}">
            <span>{pmf:apply-children($config, $node, $default)}</span>
            <span class="altcontent">{pmf:apply-children($config, $node, $alternate)}</span>
        </span>
};

declare function pmf:match($config as map(*), $node as node(), $content) {
    <mark id="{$node/../@exist:id}">
    {
        pmf:apply-children($config, $node, $content)
    }</mark>
};

declare function pmf:webcomponent($config as map(*), $node as node()*, $class as xs:string+, $content,
    $name as xs:string, $optional as map(*)) {
    element { $name } {
        attribute class { $class },
        if ($node/@xml:id) then
            attribute id { $node/@xml:id }
        else
            (),
        map:for-each($optional, function($key, $value) {
            typeswitch($value)
                case xs:boolean return
                    if ($value) then attribute { $key } { $key } else ()
                default return
                    attribute { $key } { $value }
        }),
        $config?apply-children($config, $node, $content)
    }
};


declare function pmf:template($config as map(*), $node as node()*, $class as xs:string+, $content,
    $template as item(), $optional as map(*)) {
    let $optional := map:merge(($optional, map { "content": $content }))
    return
        pmf:process-templates($config, $node, $template, $optional, $class)
};

declare %private function pmf:process-templates($config as map(*), $context as node(),
    $nodes as node()*, $optional as map(*), $class as xs:string*) {
    for $node in $nodes
    return
        typeswitch($node)
            case element() return
                element { local-name($node) } {
                    let $attribs := if (exists($class)) then $node/@* except $node/@class else $node/@*
                    for $attr in $attribs
                    return
                        attribute { node-name($attr) } {
                            pmf:template-content($config, $context, $attr, $optional)
                        },
                    if (exists($class)) then
                        attribute class { $node/@class, $class }
                    else
                        (),
                    pmf:process-templates($config, $context, $node/node(), $optional, $class)
                }
            default return pmf:template-content($config, $context, $node, $optional)
};


declare %private function pmf:template-content($config as map(*), $context as node(), $content as xs:string, $optional as map(*)) {
    if (matches($content, "\$\[[^\]]+\]")) then
        let $parsed := analyze-string($content, "\$\[([^\]]+?)(?::([^\]]+))?\]")
        for $token in $parsed/node()
        return
            typeswitch($token)
                case element(fn:non-match) return $token/string()
                case element(fn:match) return
                    let $paramName := $token/fn:group[1]
                    let $default := $token/fn:group[2]
                    return
                        if (map:contains($optional, $paramName)) then
                            let $result := $optional($paramName)
                            return
                                if (exists($result)) then
                                    $config?apply-children($config, $context, $result)
                                else
                                    $default
                        else
                            $default
                default return $token
    else
        $content
};

declare %private function pmf:pass-optional-params($optional as map(*)) {
    map:for-each($optional, function($key, $value) {
        if ($key != "class") then
            attribute { $key } { $value }
        else
            ()
    })
};


declare function pmf:apply-children($config as map(*), $node as node(), $content) {
    if ($node/@xml:id) then
        attribute id { $node/@xml:id }
    else
        (),
    $config?apply-children($config, $node, $content)
};
