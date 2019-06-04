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
 : Utility functions for generating CSS from an ODD or parsing CSS into a map.
 :
 : @author Wolfgang Meier
 :)
module namespace css="http://www.tei-c.org/tei-simple/xquery/css";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare function css:parse-css($css as xs:string) {
    map:merge(
        let $analyzed := analyze-string($css, "(.*?)\s*\{\s*([^\}]*?)\s*\}", "m")
        for $match in $analyzed/fn:match
        let $selectorString := $match/fn:group[@nr = "1"]/string()
        let $selectors := tokenize($selectorString, "\s*,\s*")
        let $styles := map:merge(
            for $match in analyze-string($match/fn:group[@nr = "2"], "\s*(.*?)\s*:\s*['&quot;]?(.*?)['&quot;]?(?:;|$)")/fn:match
            return
                map:entry($match/fn:group[1]/string(), $match/fn:group[2]/string())
        )
        for $selector in $selectors
        let $selector := replace($selector, "^\.?(.*)$", "$1")
        return
            map:entry($selector, $styles)
    )
};

declare function css:generate-css($root as document-node(), $output as xs:string, $path as xs:string) {
    string-join((
        "/* Generated stylesheet. Do not edit. */&#10;",
        if ($output = "web") then (
            "/* Global styles */&#10;",
            css:global-css($root, $path)
        ) else
            (),
        for $rend in $root//tei:rendition[@xml:id]
        return
            "&#10;.simple_" || $rend/@xml:id || " { " ||
            normalize-space($rend/string()) || " }",
        "&#10;&#10;/* Model rendition styles */&#10;",
        for $model in $root//tei:model[tei:outputRendition]
        let $spec := $model/ancestor::tei:elementSpec[1]
        let $count := count($spec//tei:model)
        for $rend in $model/tei:outputRendition
        let $className :=
            if ($count > 1) then
                $spec/@ident || count($spec//tei:model[. << $model]) + 1
            else
                $spec/@ident/string()
        let $class :=
            if ($rend/@scope) then
                translate($className, ":", "_") || ":" || $rend/@scope
            else
                translate($className, ":", "_")
        return
            "&#10;.tei-" || $class || " { " ||
            normalize-space($rend) || " }"
    ))
};

declare function css:global-css($root as document-node(), $oddPath as xs:string) {
    string-join((
            css:global-css-by-selector($root),
            css:global-css-by-rendition($root, $oddPath)
        ),
        "&#10;&#10;"
    )
};

declare %private function css:global-css-by-selector($root as document-node()) {
    for $rendition in $root//tei:teiHeader/tei:encodingDesc/tei:tagsDecl/tei:rendition[@selector]
    return
        $rendition/@selector || " {&#10;" ||
        replace($rendition/text(), "^\s*(.*)$", "&#9;$1", "m") ||
        "}"
};

declare %private function css:global-css-by-rendition($root as document-node(), $oddPath as xs:string) {
    let $cssPath := replace($oddPath, "^(.*?)/[^/]+$", "$1")
    for $source in $root//tei:teiHeader/tei:encodingDesc/tei:tagsDecl/tei:rendition/@source
    let $css := util:binary-doc($cssPath || "/" || $source)
    return
        if (exists($css)) then (
            "&#10;/* external styles loaded from " || $source || " */&#10;",
            util:binary-to-string($css)
        ) else
            "&#10;/* external styles not found: " || util:collection-name($root) || "/" || $source || " */&#10;"
};


declare function css:get-rendition($node as node()*, $class as xs:string+) {
    $class,
    for $rend in tokenize($node/@rendition, "[\s,]+")
    return
        if (starts-with($rend, "#")) then
            'document_' || substring-after($rend,'#')
        else if (starts-with($rend,'simple:')) then
            translate($rend,':','_')
        else
            $rend
};

declare function css:rendition-styles($config as map(*), $node as node()*) as map(*)? {
    let $renditions := $node//@rendition[starts-with(., "#")]
    return
        if ($renditions) then
            map:merge(
                let $doc := ($config?parameters?root, root($node[1]))[1]
                for $renditionDef in $renditions
                for $rendition in tokenize($renditionDef, "\s+")
                let $id := substring-after($rendition, "#")
                for $def in $doc/id($id)
                return
                    map:entry("document_" || $id, $def/string())
            )
        else
            ()
};

declare function css:rendition-styles-html($config as map(*), $node as node()*) {
    let $styles := css:rendition-styles($config, $node)
    return
        if (exists($styles)) then
            map:for-each($styles, function($key, $value) {
                "." || $key || " {&#10;" ||
                "   " || $value || "&#10;" ||
                "}&#10;&#10;"
            })
        else
            ()
};
