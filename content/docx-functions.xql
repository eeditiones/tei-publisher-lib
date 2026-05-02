xquery version "3.1";

(:~
 : Function module to produce DOCX output. Transforms TEI via the TEI Simple
 : Processing Model behaviour protocol into a Microsoft flat OPC <pkg:package>
 : XML document. The caller converts this to a ZIP (.docx) using whatever
 : method is available (temp-collection + compression:zip(), Java streaming, etc.).
 :
 : Footnotes and hyperlinks use an inline sentinel pattern: sentinels emitted
 : during the tree-walk are collected and replaced in pmf:finish().
 :
 : Word styles: the first class token not starting with tei- becomes the Word
 : w:styleId (paragraph or character). Generated tei-* classes are skipped.
 :
 : @author TEI Publisher Team
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/docx-output";

declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace r="http://schemas.openxmlformats.org/officeDocument/2006/relationships";
declare namespace rel="http://schemas.openxmlformats.org/package/2006/relationships";
declare namespace pkg="http://schemas.microsoft.com/office/2006/xmlPackage";
declare namespace ct="http://schemas.openxmlformats.org/package/2006/content-types";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace docx="http://existsolutions.com/ns/docx";

import module namespace counters="http://www.tei-c.org/tei-simple/xquery/counters";

declare variable $pmf:FOOTNOTE_COUNTER := "docx-fn-" || util:uuid();
declare variable $pmf:LINK_COUNTER    := "docx-lnk-" || util:uuid();
declare variable $pmf:LIB_URI         := "http://existsolutions.com/apps/tei-publisher-lib";

(: numId from numbering.xml: 1=ListBullet, 5=ListNumber :)
declare variable $pmf:BULLET_NUM_ID  := "1";
declare variable $pmf:ORDERED_NUM_ID := "5";

declare variable $pmf:FN_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes";
declare variable $pmf:HL_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink";

(: ============================================================
   Lifecycle: prepare / finish
   ============================================================ :)

declare function pmf:prepare($config as map(*), $node as node()*) {
    counters:create($pmf:FOOTNOTE_COUNTER),
    counters:create($pmf:LINK_COUNTER),
    ()
};

declare function pmf:finish($config as map(*), $input as node()*) {
    let $_ := counters:destroy($pmf:FOOTNOTE_COUNTER)
    let $_ := counters:destroy($pmf:LINK_COUNTER)
    let $footnotes  := $input//docx:footnote
    let $links      := $input//docx:hyperlink
    let $body-nodes := pmf:clean-body($input)
    return
        pmf:assemble-package($body-nodes, $footnotes, $links, exists($footnotes))
};

(: ============================================================
   Public behaviour functions
   ============================================================ :)

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    $config?apply-children($config, $node, $content)
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:p>
        <w:pPr><w:pStyle w:val="{pmf:resolve-para-style($class)}"/></w:pPr>
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:p>
};

declare function pmf:heading($config as map(*), $node as node(), $class as xs:string+, $content, $level) {
    let $lvl :=
        if ($level) then
            $level
        else if ($content instance of node()) then
            max((count($content/ancestor::tei:div), 1))
        else 1
    let $lvl := min((max(($lvl, 1)), 9))
    return
        <w:p>
            <w:pPr><w:pStyle w:val="Heading{$lvl}"/></w:pPr>
            { pmf:apply-runs($config, $node, $class, $content) }
        </w:p>
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:p>
        <w:pPr><w:pStyle w:val="{pmf:resolve-para-style($class)}"/></w:pPr>
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:p>
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content) {
    let $run-props := pmf:run-props($config, $class)
    let $preserve-text := pmf:preserve-whitespace($class)
    for $child in $config?apply-children($config, $node, $content)
    return
        typeswitch($child)
            case element(w:r) return
                <w:r>
                    <w:rPr>{ $run-props, $child/w:rPr/* }</w:rPr>
                    { $child/* except $child/w:rPr }
                </w:r>
            case text() return
                let $text := pmf:normalize-text(string($child), $preserve-text)
                where
                    if ($preserve-text) then $text != ''
                    else normalize-space($text) != ''
                return
                    <w:r>
                        <w:rPr>{ $run-props }</w:rPr>
                        { pmf:make-t($text) }
                    </w:r>
            default return $child
};

declare function pmf:text($config as map(*), $node as node(), $class as xs:string+, $content) {
    let $str := pmf:normalize-text(string($content), pmf:preserve-whitespace($class))
    let $rPr := pmf:run-props($config, $class)
    where
        if (pmf:preserve-whitespace($class)) then $str != ''
        else $str != '' and normalize-space($str) != ''
    return
        if (exists($rPr)) then
            <w:r>
                <w:rPr>{ $rPr }</w:rPr>
                { pmf:make-t($str) }
            </w:r>
        else
            <w:r>{ pmf:make-t($str) }</w:r>
};

(: Compatibility hook expected by generated transformation modules. :)
declare function pmf:escapeChars($text as item()*) {
    typeswitch($text)
        case text() return
            $text
        default return
            text { $text }
};

declare function pmf:note($config as map(*), $node as node(), $class as xs:string+, $content, $place, $label) {
    let $id := counters:increment($pmf:FOOTNOTE_COUNTER)
    return (
        <docx:footnote-ref id="{$id}"/>,
        <docx:footnote id="{$id}">
            { $config?apply($config, $content/node()) }
        </docx:footnote>
    )
};

declare function pmf:list($config as map(*), $node as node(), $class as xs:string+, $content, $type) {
    let $numId := if ($type = "ordered") then $pmf:ORDERED_NUM_ID else $pmf:BULLET_NUM_ID
    let $config := map:merge(($config, map {
        "list-num-id": $numId,
        "list-level":  (($config?list-level, 0)[1] + 1)
    }), map { "duplicates": "use-last" })
    return
        $config?apply-children($config, $node, $content)
};

declare function pmf:listItem($config as map(*), $node as node(), $class as xs:string+, $content, $n) {
    <w:p>
        <w:pPr>
            <w:numPr>
                <w:ilvl w:val="{max((($config?list-level, 1)[1] - 1, 0))}"/>
                <w:numId w:val="{($config?list-num-id, $pmf:BULLET_NUM_ID)[1]}"/>
            </w:numPr>
        </w:pPr>
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:p>
};

declare function pmf:table($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:tbl>
        <w:tblPr><w:tblStyle w:val="TableGrid"/></w:tblPr>
        { $config?apply-children($config, $node, $content) }
    </w:tbl>
};

declare function pmf:row($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:tr>{ $config?apply-children($config, $node, $content) }</w:tr>
};

declare function pmf:cell($config as map(*), $node as node(), $class as xs:string+, $content,
    $type, $col, $row) {
    <w:tc>
        {
            if ($node/@cols castable as xs:integer and xs:integer($node/@cols) > 1) then
                <w:tcPr><w:gridSpan w:val="{$node/@cols}"/></w:tcPr>
            else ()
        }
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:tc>
};

declare function pmf:graphic($config as map(*), $node as node(), $class as xs:string+, $content,
    $url, $width, $height, $scale, $title) {
    <w:p>
        <w:r>{ pmf:make-t("[Image: " || $url || "]") }</w:r>
    </w:p>
};

declare function pmf:weblink($config as map(*), $node as node(), $class as xs:string+, $content,
    $url, $target, $optional) {
    let $rId := "rLnk" || counters:increment($pmf:LINK_COUNTER)
    return
        <docx:hyperlink href="{$url}" rId="{$rId}">
            { $config?apply-children($config, $node, $content) }
        </docx:hyperlink>
};

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $url) {
    <w:hyperlink w:anchor="{$url}">
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:hyperlink>
};

declare function pmf:break($config as map(*), $node as node(), $class as xs:string+, $content,
    $type, $label) {
    if ($type = "page") then
        <w:p><w:pPr><w:pageBreakBefore/></w:pPr></w:p>
    else
        <w:r><w:br/></w:r>
};

declare function pmf:anchor($config as map(*), $node as node(), $class as xs:string+, $content, $id) {
    <w:bookmarkStart w:id="{abs(string-to-codepoints($id)[1])}" w:name="{$id}"/>,
    <w:bookmarkEnd   w:id="{abs(string-to-codepoints($id)[1])}"/>
};

declare function pmf:alternate($config as map(*), $node as node(), $class as xs:string+, $content,
    $default, $alternate) {
    $config?apply-children($config, $node, $default),
    pmf:note($config, $node, $class, $alternate, "footnote", ())
};

declare function pmf:omit($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:skip($config as map(*), $node as node(), $class as xs:string+, $content) {
    ()
};

declare function pmf:caption($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:p>
        <w:pPr><w:pStyle w:val="Caption"/></w:pPr>
        { pmf:apply-runs($config, $node, $class, $content) }
    </w:p>
};

declare function pmf:figure($config as map(*), $node as node(), $class as xs:string+, $content) {
    $config?apply-children($config, $node, $content)
};

declare function pmf:metadata($config as map(*), $node as node(), $class as xs:string+, $content,
    $property) {
    ()
};

declare function pmf:index($config as map(*), $node as node(), $class as xs:string+, $content,
    $sort-key) {
    ()
};

declare function pmf:match($config as map(*), $node as node(), $content) {
    $config?apply-children($config, $node, $content)
};

(: ============================================================
   Helper visible to extension modules
   ============================================================ :)

declare function pmf:apply-children($config as map(*), $node as node(), $content) {
    $config?apply-children($config, $node, $content)
};

(: ============================================================
   Private: body cleaning (sentinel replacement)
   ============================================================ :)

declare %private function pmf:clean-body($nodes as node()*) as node()* {
    for $node in $nodes
    return
        typeswitch($node)
            case element(docx:footnote) return ()
            case element(docx:footnote-ref) return
                <w:r>
                    <w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>
                    <w:footnoteReference w:id="{$node/@id}"/>
                </w:r>
            case element(w:p) return
                pmf:flatten-paragraph($node)
            case element(docx:hyperlink) return
                element { QName("http://schemas.openxmlformats.org/wordprocessingml/2006/main", "w:hyperlink") } {
                    attribute { QName("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "r:id") } { $node/@rId },
                    pmf:clean-body($node/node())
                }
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    pmf:clean-body($node/node())
                }
            default return $node
};

declare %private function pmf:flatten-paragraph($p as element(w:p)) as element(w:p)* {
    let $content := pmf:clean-body($p/node()[not(self::w:p)])
    let $has-content := exists($content[not(self::text()[normalize-space(.) = ""])])
    return (
        if ($has-content) then
            element { node-name($p) } {
                $p/@*,
                $content
            }
        else
            (),
        for $nested in $p/w:p
        return
            pmf:flatten-paragraph($nested)
    )
};

(: ============================================================
   Private: package assembly
   ============================================================ :)

declare %private function pmf:assemble-package(
    $body-nodes     as node()*,
    $footnotes      as element(docx:footnote)*,
    $links          as element(docx:hyperlink)*,
    $has-footnotes  as xs:boolean
) as element(pkg:package) {
    let $sectPr        := pmf:load-template-xml("word/document.xml")//w:sectPr
    let $doc-xml       := pmf:make-document-xml($body-nodes, $sectPr)
    let $doc-rels      := pmf:make-document-rels($links, $has-footnotes)
    let $content-types := pmf:make-content-types($has-footnotes)
    return
        <pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage">
            <pkg:part pkg:name="/[Content_Types].xml" pkg:contentType="application/xml">
                <pkg:xmlData>{ $content-types }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/_rels/.rels"
                pkg:contentType="application/vnd.openxmlformats-package.relationships+xml">
                <pkg:xmlData>{ pmf:load-template-xml("_rels/.rels")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/document.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml">
                <pkg:xmlData>{ $doc-xml }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/_rels/document.xml.rels"
                pkg:contentType="application/vnd.openxmlformats-package.relationships+xml">
                <pkg:xmlData>{ $doc-rels }</pkg:xmlData>
            </pkg:part>
            {
                if ($has-footnotes) then (
                    <pkg:part pkg:name="/word/footnotes.xml"
                        pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml">
                        <pkg:xmlData>{ pmf:make-footnotes-xml($footnotes) }</pkg:xmlData>
                    </pkg:part>,
                    <pkg:part pkg:name="/word/_rels/footnotes.xml.rels"
                        pkg:contentType="application/vnd.openxmlformats-package.relationships+xml">
                        <pkg:xmlData>
                            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
                        </pkg:xmlData>
                    </pkg:part>
                ) else ()
            }
            <pkg:part pkg:name="/word/styles.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/styles.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/stylesWithEffects.xml"
                pkg:contentType="application/vnd.ms-word.stylesWithEffects+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/stylesWithEffects.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/numbering.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/numbering.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/settings.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/settings.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/webSettings.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/webSettings.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/fontTable.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/fontTable.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/theme/theme1.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.theme+xml">
                <pkg:xmlData>{ pmf:load-template-xml("word/theme/theme1.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/core.xml"
                pkg:contentType="application/vnd.openxmlformats-package.core-properties+xml">
                <pkg:xmlData>{ pmf:load-template-xml("docProps/core.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/app.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.extended-properties+xml">
                <pkg:xmlData>{ pmf:load-template-xml("docProps/app.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/thumbnail.jpeg"
                pkg:contentType="image/jpeg" pkg:compression="store">
                <pkg:binaryData>{ repo:get-resource($pmf:LIB_URI, "resources/docx/docProps/thumbnail.jpeg") }</pkg:binaryData>
            </pkg:part>
            <pkg:part pkg:name="/customXml/item1.xml"
                pkg:contentType="application/xml">
                <pkg:xmlData>{ pmf:load-template-xml("customXml/item1.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/customXml/itemProps1.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.customXmlProperties+xml">
                <pkg:xmlData>{ pmf:load-template-xml("customXml/itemProps1.xml")/element() }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/customXml/_rels/item1.xml.rels"
                pkg:contentType="application/vnd.openxmlformats-package.relationships+xml">
                <pkg:xmlData>{ pmf:load-template-xml("customXml/_rels/item1.xml.rels")/element() }</pkg:xmlData>
            </pkg:part>
        </pkg:package>
};

declare %private function pmf:make-document-xml($body-nodes as node()*, $sectPr as element()) {
    <w:document
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
            { $body-nodes }
            { $sectPr }
        </w:body>
    </w:document>
};

declare %private function pmf:make-document-rels(
    $links         as element(docx:hyperlink)*,
    $has-footnotes as xs:boolean
) as element(rel:Relationships) {
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml"   Target="../customXml/item1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"   Target="numbering.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"      Target="styles.xml"/>
        <Relationship Id="rId4" Type="http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects"        Target="stylesWithEffects.xml"/>
        <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"    Target="settings.xml"/>
        <Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings" Target="webSettings.xml"/>
        <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable"   Target="fontTable.xml"/>
        <Relationship Id="rId8" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"       Target="theme/theme1.xml"/>
        {
            if ($has-footnotes) then
                <Relationship Id="rId9" Type="{$pmf:FN_REL_TYPE}" Target="footnotes.xml"/>
            else ()
        }
        {
            for $link in $links
            return
                <Relationship Id="{$link/@rId}" Type="{$pmf:HL_REL_TYPE}"
                    Target="{$link/@href}" TargetMode="External"/>
        }
    </Relationships>
};

declare %private function pmf:make-content-types($has-footnotes as xs:boolean) as element() {
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="xml"  ContentType="application/xml"/>
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="jpeg" ContentType="image/jpeg"/>
        <Override PartName="/word/document.xml"         ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        { if ($has-footnotes) then
            <Override PartName="/word/footnotes.xml"    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
          else () }
        <Override PartName="/customXml/itemProps1.xml"  ContentType="application/vnd.openxmlformats-officedocument.customXmlProperties+xml"/>
        <Override PartName="/word/numbering.xml"        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        <Override PartName="/word/styles.xml"           ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/stylesWithEffects.xml" ContentType="application/vnd.ms-word.stylesWithEffects+xml"/>
        <Override PartName="/word/settings.xml"         ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
        <Override PartName="/word/webSettings.xml"      ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml"/>
        <Override PartName="/word/fontTable.xml"        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
        <Override PartName="/word/theme/theme1.xml"     ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/docProps/core.xml"         ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml"          ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
};

declare %private function pmf:make-footnotes-xml($footnotes as element(docx:footnote)*) as element(w:footnotes) {
    <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:footnote w:type="separator" w:id="-1">
            <w:p><w:r><w:separator/></w:r></w:p>
        </w:footnote>
        <w:footnote w:type="continuationSeparator" w:id="0">
            <w:p><w:r><w:continuationSeparator/></w:r></w:p>
        </w:footnote>
        {
            for $fn in $footnotes
            return
                <w:footnote w:id="{$fn/@id}">
                    <w:p>
                        <w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr>
                        <w:r>
                            <w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>
                            <w:footnoteRef/>
                        </w:r>
                        { pmf:clean-body($fn/node()) }
                    </w:p>
                </w:footnote>
        }
    </w:footnotes>
};

(: ============================================================
   Private: style mapping
   First token in $class order that does not start with "tei-" becomes the Word
   style id (w:val). Paragraph styles fall back to Normal; character styles to ().

   Styles must exist in the template word/styles.xml.
   ============================================================ :)

declare %private function pmf:user-style-classes($class as xs:string*) as xs:string* {
    $class[not(starts-with(., "tei-"))]
};

declare %private function pmf:resolve-para-style($class as xs:string+) as xs:string {
    let $user := pmf:user-style-classes($class)
    return
        head((
            for $c in $user
            where normalize-space($c) != ""
            return string($c)
        ,
            "Normal"
        ))
};

declare %private function pmf:resolve-char-style($class as xs:string+) as xs:string? {
    let $user := pmf:user-style-classes($class)
    return head((
        for $c in $user
        where normalize-space($c) != ""
        return string($c)
    ))
};

declare %private function pmf:run-props($config as map(*), $class as xs:string+) as element()* {
    let $char-style := pmf:resolve-char-style($class)
    let $r-style :=
        if (exists($char-style)) then
            <w:rStyle w:val="{$char-style}"/>
        else
            ()
    let $css-map :=
        if (map:contains($config, "rendition-styles")) then $config?rendition-styles
        else map {}
    let $css := string-join(for $c in $class return ($css-map?($c), ""))
    return (
        $r-style,
        if (contains($css, "font-weight") and contains($css, "bold")) then <w:b/>         else (),
        if (contains($css, "font-style")  and contains($css, "italic")) then <w:i/>       else (),
        if (contains($css, "text-decoration") and contains($css, "underline")) then
            <w:u w:val="single"/>
        else (),
        if (contains($css, "text-decoration") and contains($css, "line-through")) then
            <w:strike/>
        else (),
        if (contains($css, "vertical-align") and contains($css, "super")) then
            <w:vertAlign w:val="superscript"/>
        else (),
        if (contains($css, "vertical-align") and contains($css, "sub")) then
            <w:vertAlign w:val="subscript"/>
        else ()
    )
};

(: ============================================================
   Private: run/text helpers
   ============================================================ :)

declare %private function pmf:apply-runs($config as map(*), $node as node(), $class as xs:string*, $content) as node()* {
    let $preserve-text := pmf:preserve-whitespace($class)
    for $item in $config?apply-children($config, $node, $content)
    return
        typeswitch($item)
            case text() return
                let $s := pmf:normalize-text(string($item), $preserve-text)
                where
                    if ($preserve-text) then $s != ''
                    else normalize-space($s) != ''
                return <w:r>{ pmf:make-t($s) }</w:r>
            default return $item
};

declare %private function pmf:preserve-whitespace($class as xs:string*) as xs:boolean {
    (: tei-code / tei-tag still appear for some TEI element names; otherwise match
       common Word style ids used for preformatted text (see template + cssClass). :)
    exists($class[. = ("tei-code", "tei-tag")])
    or exists(
        pmf:user-style-classes($class)[. = ("Code", "Preformatted", "CodeChar")]
    )
};

declare %private function pmf:normalize-text($text as xs:string?, $preserve as xs:boolean) as xs:string {
    if (empty($text)) then
        ""
    else if ($preserve) then
        $text
    else
        let $step1 := replace($text, "[\r\n\t]+", " ")
        return replace($step1, " {2,}", " ")
};

declare %private function pmf:make-t($text as xs:string) as element(w:t) {
    if (matches($text, "^\s|\s$")) then
        <w:t xml:space="preserve">{ $text }</w:t>
    else
        <w:t>{ $text }</w:t>
};

(: ============================================================
   Private: template loading
   ============================================================ :)

declare %private function pmf:load-template-xml($path as xs:string) as document-node() {
    let $bin := repo:get-resource($pmf:LIB_URI, "resources/docx/" || $path)
    return
        parse-xml(util:binary-to-string($bin, "UTF-8"))
};
