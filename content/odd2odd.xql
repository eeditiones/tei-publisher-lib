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
xquery version "3.0";

module namespace odd="http://www.tei-c.org/tei-simple/odd2odd";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace pb="http://teipublisher.com/1.0";

import module namespace console="http://exist-db.org/xquery/console" at "java:org.exist.console.xquery.ConsoleModule";

declare function odd:get-compiled($inputCol as xs:string, $odd as xs:string) as document-node() {
    odd:compile($inputCol, $odd)
};

declare function odd:compile($inputCol as xs:string, $odd as xs:string) as document-node() {
    console:log("Compiling odd: " || $inputCol || "/" || $odd),
    let $compiled := odd:compile($inputCol, $odd)
    return
        $compiled
};

declare function odd:compile($inputCol as xs:string, $odd as xs:string) {
    let $root := doc($inputCol || "/" || $odd)/tei:TEI
    return
        if ($root) then
            if ($root//tei:schemaSpec[@source]) then
                let $import := $root//tei:schemaSpec[@source][1]
                let $name := $import/@source
                let $parent := odd:compile($inputCol, $name)/tei:TEI
                return
                    odd:merge($parent, $root)
            else
                root($root)
        else
            error(xs:QName("odd:not-found"), "ODD not found: " || $inputCol || "/" || $odd)
};

declare %private function odd:merge($parent as element(tei:TEI), $child as element(tei:TEI)) {
    document {
        <TEI xmlns="http://www.tei-c.org/ns/1.0" xml:lang="en"
            source="{document-uri(root($child))}">
            {
                let $prefixesParent := in-scope-prefixes($parent)[not(. = ("", "xml", "xhtml", "css"))]
                let $prefixesChild := in-scope-prefixes($child)[not(. = ("", "xml", "xhtml", "css"))]
                let $prefixes := distinct-values(($prefixesParent, $prefixesChild))
                let $namespaces := $prefixes ! (namespace-uri-for-prefix(., $child), namespace-uri-for-prefix(., $parent))[1]
                return
                    for-each-pair($prefixes, $namespaces, function($prefix, $namespace) {
                        namespace { $prefix } { $namespace }
                    })
            }
            <teiHeader>
                <fileDesc>
                    <titleStmt>
                        <title>Merged TEI PM Spec</title>
                    </titleStmt>
                    <publicationStmt>
                        <p>Automatically generated, do not modify.</p>
                    </publicationStmt>
                    <sourceDesc>
                        <p>Generated from input ODD: {document-uri(root($child))}</p>
                    </sourceDesc>
                </fileDesc>
                <encodingDesc>
                    <tagsDecl>
                    {
                        for $behaviour in $parent/teiHeader/encodingDesc/tagsDecl/pb:behaviour
                        where empty($child/teiHeader/encodingDesc/tagsDecl/pb:behaviour[@xml:id = $behaviour/@xml:id])
                        return
                            $behaviour,
                        $child/teiHeader/encodingDesc/tagsDecl/pb:behaviour
                    }
                    {
                        for $rendition in $parent/teiHeader/encodingDesc/tagsDecl/rendition
                        where empty($child/teiHeader/encodingDesc/tagsDecl/rendition[@xml:id = $rendition/@xml:id])
                        return
                            $rendition,
                        $child/teiHeader/encodingDesc/tagsDecl/rendition
                    }
                    </tagsDecl>
                </encodingDesc>
            </teiHeader>
            <text>
                <body>
                {
                    (: Copy element specs which are not overwritten by child :)
                    for $spec in $parent//elementSpec
                    group by $ident := $spec/@ident
                    let $childSpec := $child//elementSpec[@ident = $spec/@ident][@mode = "change"]
                    return
                        if ($childSpec) then
                            if ($childSpec/(model|modelGrp|modelSequence)) then
                                $childSpec
                            else
                                element { node-name($childSpec) } {
                                    $childSpec/@*,
                                    $spec/(model|modelGrp|modelSequence)
                                }
                        else if ($spec/(model|modelGrp|modelSequence)) then
                            element { node-name($spec[1]) } {
                                $spec[1]/@*,
                                $spec/(model|modelGrp|modelSequence)
                            }
                        else
                            ()
                }
                {
                    (: Copy added element specs :)
                    for $spec in $child//elementSpec[.//model]
                    (: Skip specs which already exist in parent :)
                    where empty($parent//elementSpec[@ident = $spec/@ident])
                    return
                        $spec
                }
                {
                    (: Merge global outputRenditions :)
                    for $rendition in $child//outputRendition[@xml:id][not(ancestor::model)]
                    where exists($parent/id($rendition/@xml:id))
                    return
                        $rendition,
                    for $parentRendition in $parent//outputRendition[@xml:id][not(ancestor::model)]
                    where empty($child/id($parentRendition/@xml:id))
                    return
                        $parentRendition
                }
                </body>
            </text>
        </TEI>
    }
};

(:~ Strip out documentation elements to speed things up :)
declare %private function odd:strip-down($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case processing-instruction() | element(tei:remarks) | element(tei:exemplum) | element(tei:listRef) | element(tei:gloss) return
                ()
            case element(tei:desc) return
                if ($node/parent::tei:model) then
                    $node
                else
                    ()
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    odd:strip-down($node/node())
                }
            default return
                $node
};
