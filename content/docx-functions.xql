xquery version "3.1";

(:~
 : Function module to produce DOCX output. Transforms TEI via the TEI Simple
 : Processing Model behaviour protocol into a Microsoft flat OPC <pkg:package>
 : XML document. The caller converts this to a ZIP (.docx) using whatever
 : method is available (temp-collection + compression:zip(), Java streaming, etc.).
 :
 : Footnotes, hyperlinks, and inline images use a sentinel pattern: sentinels
 : emitted during the tree-walk are resolved in pmf:finish(). Images are packed
 : as /word/media/* parts. Binaries load via pmf:builtin-fetch-image-binary (HTTP(S),
 : /db, paths relative to parameters/root). Optional docx-image-fetch overrides that.
 :
 : Word styles: the first class token not starting with tei- becomes the Word
 : w:styleId (paragraph or character) only if that id exists in the DOCX template
 : styles.xml (see pmf:init). Generated tei-* classes are skipped.
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
import module namespace http="http://expath.org/ns/http-client" at "java:org.exist.xquery.modules.httpclient.HTTPClientModule";

declare variable $pmf:FOOTNOTE_COUNTER := "docx-fn-" || util:uuid();
declare variable $pmf:LINK_COUNTER    := "docx-lnk-" || util:uuid();
declare variable $pmf:GRAPHIC_COUNTER   := "docx-gr-" || util:uuid();
declare variable $pmf:DOC_PR_COUNTER    := "docx-dp-" || util:uuid();
declare variable $pmf:LIB_URI         := "http://existsolutions.com/apps/tei-publisher-lib";

(: numId from numbering.xml: 1=ListBullet, 5=ListNumber :)
declare variable $pmf:BULLET_NUM_ID  := "1";
declare variable $pmf:ORDERED_NUM_ID := "5";

declare variable $pmf:FN_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes";
declare variable $pmf:HL_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink";
declare variable $pmf:IMG_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image";

(: ============================================================
   Lifecycle: init / prepare / finish
   ============================================================ :)

declare function pmf:init($config as map(*), $node as node()*) {
    let $styles-doc := pmf:load-template-xml("word/styles.xml")
    let $styles := $styles-doc//w:style
    return
        map:merge((
            $config,
            map {
                "docx-para-style-ids": distinct-values(
                    for $id in $styles[@w:type = "paragraph"]/@w:styleId
                    return string($id)[normalize-space(.) != ""]
                ),
                "docx-char-style-ids": distinct-values(
                    for $id in $styles[@w:type = "character"]/@w:styleId
                    return string($id)[normalize-space(.) != ""]
                ),
                "docx-table-style-ids": distinct-values(
                    for $id in $styles[@w:type = "table"]/@w:styleId
                    return string($id)[normalize-space(.) != ""]
                )
            }
        ), map { "duplicates": "use-last" })
};

declare function pmf:prepare($config as map(*), $node as node()*) {
    counters:create($pmf:FOOTNOTE_COUNTER),
    counters:create($pmf:LINK_COUNTER),
    counters:create($pmf:GRAPHIC_COUNTER),
    counters:create($pmf:DOC_PR_COUNTER),
    ()
};

declare function pmf:finish($config as map(*), $input as node()*) {
    let $_ := counters:destroy($pmf:FOOTNOTE_COUNTER)
    let $_ := counters:destroy($pmf:LINK_COUNTER)
    let $_ := counters:destroy($pmf:GRAPHIC_COUNTER)
    let $_ := counters:destroy($pmf:DOC_PR_COUNTER)
    let $footnotes := $input//docx:footnote
    let $links := $input//docx:hyperlink
    let $images := $input//docx:image
    let $image-build := pmf:build-image-package($config, $images)
    let $cfg2 := map:merge((
        $config,
        map { "docx-image-by-rid": $image-build?by-rid }
    ), map { "duplicates": "use-last" })
    let $body-nodes := pmf:wrap-top-level-runs-in-paragraphs(pmf:clean-body($cfg2, $input))
    return
        pmf:assemble-package(
            $cfg2,
            $body-nodes,
            $footnotes,
            $links,
            exists($footnotes),
            $image-build?items
        )
};

(: ============================================================
   Public behaviour functions
   ============================================================ :)

declare function pmf:document($config as map(*), $node as node(), $class as xs:string+, $content) {
    $config?apply-children($config, $node, $content)
};

declare function pmf:paragraph($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:p>
        <w:pPr><w:pStyle w:val="{pmf:resolve-para-style($config, $class)}"/></w:pPr>
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
            <w:pPr><w:pStyle w:val="{pmf:resolve-heading-style($config, $lvl)}"/></w:pPr>
            { pmf:apply-runs($config, $node, $class, $content) }
        </w:p>
};

declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    <w:p>
        <w:pPr><w:pStyle w:val="{pmf:resolve-para-style($config, $class)}"/></w:pPr>
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
            { $config?apply-children($config, $node, $content) }
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
    let $tbl-style := pmf:resolve-table-style($config)
    return
        <w:tbl>
            {
                if (exists($tbl-style)) then
                    <w:tblPr><w:tblStyle w:val="{$tbl-style}"/></w:tblPr>
                else
                    <w:tblPr/>
            }
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
    let $n := counters:increment($pmf:GRAPHIC_COUNTER)
    let $rId := "rId" || (9 + $n)
    let $docPrId := string(counters:increment($pmf:DOC_PR_COUNTER))
    let $scale-n :=
        if ($scale castable as xs:double) then
            xs:double($scale)
        else
            ()
    let $emu := pmf:graphic-display-emus(string($width), string($height), $scale-n)
    let $title-str := normalize-space(string-join($title, ""))
    return
        <docx:image rId="{$rId}" url="{$url}" cx="{$emu[1]}" cy="{$emu[2]}" docPrId="{$docPrId}"
            title="{$title-str}"/>
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
    let $pstyle :=
        if (pmf:has-para-style($config, "Caption")) then
            "Caption"
        else
            pmf:resolve-para-style($config, $class)
    return
        <w:p>
            <w:pPr><w:pStyle w:val="{$pstyle}"/></w:pPr>
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
   Private: embedded images (docx:image sentinels → media parts + w:drawing)
   ============================================================ :)

declare %private function pmf:image-file-extension($url as xs:string) as xs:string {
    let $path := replace($url, "^.*[/\\]", "")
    let $ext := lower-case(replace($path, "^.*\.([^.]+)$", "$1"))
    return
        if ($ext = lower-case($path) or $ext = "") then
            "png"
        else if ($ext = "jpg") then
            "jpeg"
        else
            $ext
};

declare %private function pmf:image-content-type-from-ext($ext as xs:string) as xs:string {
    switch (lower-case($ext))
        case "jpeg" return "image/jpeg"
        case "jpg" return "image/jpeg"
        case "png" return "image/png"
        case "gif" return "image/gif"
        case "bmp" return "image/bmp"
        case "tif" return "image/tiff"
        case "tiff" return "image/tiff"
        case "webp" return "image/webp"
        default return "image/png"
};

declare %private function pmf:length-to-emu($s as xs:string?) as xs:integer? {
    let $t := normalize-space(string-join($s, ""))
    where string-length($t) gt 0
    return
        if (matches($t, "in\s*$", "i")) then
            xs:integer(round(xs:double(replace($t, "in\s*$", "", "i")) * 914400))
        else if (matches($t, "cm\s*$", "i")) then
            xs:integer(round(xs:double(replace($t, "cm\s*$", "", "i")) * 360000))
        else if (matches($t, "pt\s*$", "i")) then
            xs:integer(round(xs:double(replace($t, "pt\s*$", "", "i")) * 12700))
        else if (matches($t, "px\s*$", "i")) then
            xs:integer(round(xs:double(replace($t, "px\s*$", "", "i")) * 9525))
        else if (matches($t, "^[0-9]+(\.[0-9]+)?$")) then
            xs:integer(round(xs:double($t) * 9525))
        else
            ()
};

declare %private function pmf:graphic-display-emus(
    $width as xs:string?,
    $height as xs:string?,
    $scale as xs:double?
) as xs:integer+ {
    let $factor := if (exists($scale)) then $scale else 1.0e0
    let $w := head((pmf:length-to-emu($width), 3600000))
    let $h := head((pmf:length-to-emu($height), 2743200))
    return
        (
            max((1, xs:integer(round($w * $factor)))),
            max((1, xs:integer(round($h * $factor))))
        )
};

declare %private function pmf:builtin-fetch-image-binary($config as map(*), $url as xs:string) as xs:base64Binary? {
    if (starts-with($url, "http://") or starts-with($url, "https://")) then
        try {
            let $req := <http:request method="GET" href="{$url}"/>
            let $res := http:send-request($req)
            return
                if ($res[1]/@status = 200) then
                    xs:base64Binary($res[2])
                else
                    ()
        } catch * {
            ()
        }
    else if (starts-with($url, "/db")) then
        util:binary-doc($url)
    else
        let $root := head(($config?parameters?root, $config?root))
        let $base := if (exists($root)) then base-uri($root) else ()
        return
            if (exists($base) and not(contains($url, "://"))) then
                let $abs := string(resolve-uri($url, $base))
                return
                    if (starts-with($abs, "/db")) then
                        util:binary-doc($abs)
                    else
                        ()
            else
                ()
};

declare %private function pmf:default-fetch-image-binary($config as map(*), $url as xs:string) as xs:base64Binary? {
    let $fn := head(($config?docx-image-fetch, $config?parameters?docx-image-fetch))
    return
        if (exists($fn) and $fn instance of function(*)) then
            try {
                $fn($config, $url)
            } catch * {
                ()
            }
        else
            pmf:builtin-fetch-image-binary($config, $url)
};

declare %private function pmf:build-image-package(
    $config as map(*),
    $sentinels as element(docx:image)*
) as map(*) {
    let $packed :=
        for $s in $sentinels
        let $binary := pmf:default-fetch-image-binary($config, string($s/@url))
        where exists($binary)
        return map { "sentinel": $s, "binary": $binary }
    let $items :=
        for $p at $idx in $packed
        let $s := $p?sentinel
        let $ext := pmf:image-file-extension(string($s/@url))
        return
            map {
                "rId": string($s/@rId),
                "target": "media/image" || $idx || "." || $ext,
                "part-name": "/word/media/image" || $idx || "." || $ext,
                "binary": $p?binary,
                "content-type": pmf:image-content-type-from-ext($ext)
            }
    return
        map {
            "items": $items,
            "by-rid":
                if (empty($items)) then
                    map {}
                else
                    map:merge(
                        for $i in $items
                        return map:entry($i?rId, true())
                    )
        }
};

(: One w:r only: the PM usually wraps block content in w:p; an extra w:p here would nest
   paragraphs and Word will not display the drawing. Top-level w:r is wrapped in pmf:finish. :)
declare %private function pmf:make-image-run($img as element(docx:image)) as element(w:r) {
    let $embed := string($img/@rId)
    let $cx := string($img/@cx)
    let $cy := string($img/@cy)
    let $raw := string($img/@title)
    let $name :=
        if (normalize-space($raw) != "") then
            substring(translate($raw, codepoints-to-string((10, 13, 9)), "   "), 1, 250)
        else
            "Image"
    return
        <w:r xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <w:drawing>
                <wp:inline distT="0" distB="0" distL="0" distR="0">
                    <wp:extent cx="{$cx}" cy="{$cy}"/>
                    <wp:docPr id="{string($img/@docPrId)}" name="{$name}" descr="{$name}"/>
                    <wp:cNvGraphicFramePr>
                        <a:graphicFrameLocks noChangeAspect="1"/>
                    </wp:cNvGraphicFramePr>
                    <a:graphic>
                        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                            <pic:pic>
                                <pic:nvPicPr>
                                    <pic:cNvPr id="0" name=""/>
                                    <pic:cNvPicPr/>
                                </pic:nvPicPr>
                                <pic:blipFill>
                                    <a:blip r:embed="{$embed}"
                                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
                                    <a:stretch>
                                        <a:fillRect/>
                                    </a:stretch>
                                </pic:blipFill>
                                <pic:spPr>
                                    <a:xfrm>
                                        <a:off x="0" y="0"/>
                                        <a:ext cx="{$cx}" cy="{$cy}"/>
                                    </a:xfrm>
                                    <a:prstGeom prst="rect">
                                        <a:avLst/>
                                    </a:prstGeom>
                                </pic:spPr>
                            </pic:pic>
                        </a:graphicData>
                    </a:graphic>
                </wp:inline>
            </w:drawing>
        </w:r>
};

declare %private function pmf:wrap-top-level-runs-in-paragraphs($nodes as node()*) as node()* {
    for $n in $nodes
    return
        typeswitch($n)
            case element(w:r) return
                <w:p>{ $n }</w:p>
            default return
                $n
};

(: ============================================================
   Private: body cleaning (sentinel replacement)
   ============================================================ :)

declare %private function pmf:clean-body($config as map(*), $nodes as node()*) as node()* {
    for $node in $nodes
    return
        typeswitch($node)
            case element(docx:footnote) return ()
            case element(docx:footnote-ref) return
                <w:r>
                    {
                        if (pmf:has-char-style($config, "FootnoteReference")) then
                            <w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>
                        else
                            ()
                    }
                    <w:footnoteReference w:id="{$node/@id}"/>
                </w:r>
            case element(w:p) return
                pmf:flatten-paragraph($config, $node)
            case element(docx:hyperlink) return
                element { QName("http://schemas.openxmlformats.org/wordprocessingml/2006/main", "w:hyperlink") } {
                    attribute { QName("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "r:id") } { $node/@rId },
                    pmf:clean-body($config, $node/node())
                }
            case element(docx:image) return
                if (
                    map:contains($config, "docx-image-by-rid")
                    and map:contains($config?docx-image-by-rid, string($node/@rId))
                ) then
                    pmf:make-image-run($node)
                else
                    <w:r>{ pmf:make-t("[Image: " || string($node/@url) || "]") }</w:r>
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    pmf:clean-body($config, $node/node())
                }
            default return $node
};

declare %private function pmf:flatten-paragraph($config as map(*), $p as element(w:p)) as element(w:p)* {
    let $content := pmf:clean-body($config, $p/node()[not(self::w:p)])
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
            pmf:flatten-paragraph($config, $nested)
    )
};

(: ============================================================
   Private: package assembly
   ============================================================ :)

declare %private function pmf:assemble-package(
    $config         as map(*),
    $body-nodes     as node()*,
    $footnotes      as element(docx:footnote)*,
    $links          as element(docx:hyperlink)*,
    $has-footnotes  as xs:boolean,
    $image-items    as map(*)*
) as element(pkg:package) {
    let $sectPr        := pmf:load-template-xml("word/document.xml")//w:sectPr
    let $doc-xml       := pmf:make-document-xml($body-nodes, $sectPr)
    let $doc-rels      := pmf:make-document-rels($links, $has-footnotes, $image-items)
    let $content-types := pmf:make-content-types($has-footnotes, $image-items)
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
                for $im in $image-items
                return
                    <pkg:part pkg:name="{$im?part-name}"
                        pkg:contentType="{$im?content-type}" pkg:compression="store">
                        <pkg:binaryData>{ $im?binary }</pkg:binaryData>
                    </pkg:part>
            }
            {
                if ($has-footnotes) then (
                    <pkg:part pkg:name="/word/footnotes.xml"
                        pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml">
                        <pkg:xmlData>{ pmf:make-footnotes-xml($config, $footnotes) }</pkg:xmlData>
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
    $has-footnotes as xs:boolean,
    $image-items   as map(*)*
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
            for $im in $image-items
            return
                <Relationship Id="{$im?rId}" Type="{$pmf:IMG_REL_TYPE}" Target="{$im?target}"/>
        }
        {
            for $link in $links
            return
                <Relationship Id="{$link/@rId}" Type="{$pmf:HL_REL_TYPE}"
                    Target="{$link/@href}" TargetMode="External"/>
        }
    </Relationships>
};

declare %private function pmf:make-content-types($has-footnotes as xs:boolean, $image-items as map(*)*) as element() {
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="xml"  ContentType="application/xml"/>
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="jpeg" ContentType="image/jpeg"/>
        <Default Extension="jpg"  ContentType="image/jpeg"/>
        <Default Extension="png"  ContentType="image/png"/>
        <Default Extension="gif"  ContentType="image/gif"/>
        <Default Extension="bmp"  ContentType="image/bmp"/>
        <Default Extension="tif"  ContentType="image/tiff"/>
        <Default Extension="tiff" ContentType="image/tiff"/>
        <Default Extension="webp" ContentType="image/webp"/>
        <Override PartName="/word/document.xml"         ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        { if ($has-footnotes) then
            <Override PartName="/word/footnotes.xml"    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
          else () }
        {
            for $im in $image-items
            return
                <Override PartName="{$im?part-name}" ContentType="{$im?content-type}"/>
        }
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

(:~
 : Footnote bodies must be a sequence of block elements (w:p, w:tbl, …). A single
 : wrapper w:p must not contain nested w:p, and text may only appear inside w:r/w:t.
 : Note content from the PM often emits multiple paragraphs or loose text runs; this
 : pipeline expands, coalesces, and prepends the footnote marker.
 :)
declare %private function pmf:footnote-normalize-paragraph-inlines($nodes as node()*) as node()* {
    for $n in $nodes
    return
        typeswitch($n)
            case text() return
                let $s := pmf:normalize-text(string($n), false())
                where $s != '' and normalize-space($s) != ''
                return
                    <w:r>{ pmf:make-t($s) }</w:r>
            default return
                $n
};

declare %private function pmf:footnote-expand-paragraph($config as map(*), $p as element(w:p)) as element(w:p)* {
    let $nested := $p/w:p
    let $inline := pmf:footnote-normalize-paragraph-inlines(
        pmf:clean-body($config, $p/node()[not(self::w:pPr) and not(self::w:p)])
    )
    let $has-inline := exists($inline[not(self::text()[normalize-space(.) = ""])])
    return (
        if ($has-inline) then
            element { node-name($p) } {
                $p/@*,
                $p/w:pPr,
                $inline
            }
        else
            (),
        for $np in $nested
        return
            pmf:footnote-expand-paragraph($config, $np)
    )
};

declare %private function pmf:footnote-expand-top($config as map(*), $nodes as node()*) as node()* {
    for $n in $nodes
    return
        typeswitch($n)
            case element(w:p) return
                pmf:footnote-expand-paragraph($config, $n)
            default return
                $n
};

declare %private function pmf:footnote-para-from-buffer($config as map(*), $buf as node()*) as element(w:p)? {
    let $runs := pmf:footnote-normalize-paragraph-inlines($buf)
    let $pstyle := pmf:footnote-text-style($config)
    where exists($runs)
    return
        <w:p>
            <w:pPr><w:pStyle w:val="{$pstyle}"/></w:pPr>
            { $runs }
        </w:p>
};

declare %private function pmf:footnote-coalesce-inlines-rec(
    $config as map(*),
    $nodes as node()*,
    $buf as node()*,
    $out as element()*
) as element()* {
    if (empty($nodes)) then
        (
            $out,
            if (exists($buf)) then pmf:footnote-para-from-buffer($config, $buf) else ()
        )
    else
        let $h := head($nodes)
        let $t := tail($nodes)
        return
            if ($h instance of element(w:p) or $h instance of element(w:tbl)) then
                pmf:footnote-coalesce-inlines-rec(
                    $config,
                    $t,
                    (),
                    (
                        $out,
                        if (exists($buf)) then pmf:footnote-para-from-buffer($config, $buf) else (),
                        $h
                    )
                )
            else
                pmf:footnote-coalesce-inlines-rec($config, $t, ($buf, $h), $out)
};

declare %private function pmf:footnote-coalesce-inlines($config as map(*), $nodes as node()*) as element()* {
    pmf:footnote-coalesce-inlines-rec($config, $nodes, (), ())
};

(: Two runs: marker keeps FootnoteReference; space is normal text so it is not superscript. :)
declare %private function pmf:footnote-marker-run($config as map(*)) as element(w:r)+ {
    (
        <w:r>
            {
                if (pmf:has-char-style($config, "FootnoteReference")) then
                    <w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>
                else
                    ()
            }
            <w:footnoteRef/>
        </w:r>,
        <w:r>{ pmf:make-t(" ") }</w:r>
    )
};

declare %private function pmf:footnote-marker-only-para($config as map(*)) as element(w:p) {
    <w:p>
        <w:pPr><w:pStyle w:val="{pmf:footnote-text-style($config)}"/></w:pPr>
        { pmf:footnote-marker-run($config) }
    </w:p>
};

declare %private function pmf:paragraph-with-footnote-marker($config as map(*), $p as element(w:p)) as element(w:p) {
    let $pstyle := pmf:footnote-text-style($config)
    let $pPr :=
        if ($p/w:pPr) then
            $p/w:pPr
        else
            <w:pPr><w:pStyle w:val="{$pstyle}"/></w:pPr>
    return
        element { node-name($p) } {
            $pPr,
            pmf:footnote-marker-run($config),
            pmf:footnote-normalize-paragraph-inlines($p/node()[not(self::w:pPr)])
        }
};

declare %private function pmf:prepend-footnote-ref-to-first-block($config as map(*), $blocks as element()*) as element()* {
    if (empty($blocks)) then
        pmf:footnote-marker-only-para($config)
    else if (head($blocks) instance of element(w:p)) then
        (pmf:paragraph-with-footnote-marker($config, head($blocks)), tail($blocks))
    else
        (pmf:footnote-marker-only-para($config), $blocks)
};

declare %private function pmf:footnote-body-blocks($config as map(*), $fn as element(docx:footnote)) as element()* {
    let $cleaned := pmf:clean-body($config, $fn/node())
    let $expanded := pmf:footnote-expand-top($config, $cleaned)
    return
        pmf:footnote-coalesce-inlines($config, $expanded)
};

declare %private function pmf:make-footnotes-xml($config as map(*), $footnotes as element(docx:footnote)*) as element(w:footnotes) {
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
                    { pmf:prepend-footnote-ref-to-first-block($config, pmf:footnote-body-blocks($config, $fn)) }
                </w:footnote>
        }
    </w:footnotes>
};

(: ============================================================
   Private: style mapping
   First token in $class order that does not start with "tei-" becomes the Word
   style id (w:val) only if listed in template styles.xml (pmf:init). Paragraph
   styles fall back to Normal; character styles to ().

   If pmf:init was not run, unknown classes are still emitted (backward compatible).
   ============================================================ :)

declare %private function pmf:user-style-classes($class as xs:string*) as xs:string* {
    $class[not(starts-with(., "tei-"))]
};

declare %private function pmf:has-para-style($config as map(*), $id as xs:string) as xs:boolean {
    if (map:contains($config, "docx-para-style-ids")) then
        $id = $config?docx-para-style-ids
    else
        true()
};

declare %private function pmf:has-char-style($config as map(*), $id as xs:string) as xs:boolean {
    if (map:contains($config, "docx-char-style-ids")) then
        $id = $config?docx-char-style-ids
    else
        true()
};

declare %private function pmf:has-table-style($config as map(*), $id as xs:string) as xs:boolean {
    if (map:contains($config, "docx-table-style-ids")) then
        $id = $config?docx-table-style-ids
    else
        true()
};

declare %private function pmf:footnote-text-style($config as map(*)) as xs:string {
    if (pmf:has-para-style($config, "FootnoteText")) then
        "FootnoteText"
    else if (pmf:has-para-style($config, "Normal")) then
        "Normal"
    else
        head(($config?docx-para-style-ids, "Normal"))
};

declare %private function pmf:resolve-heading-style($config as map(*), $lvl as xs:integer) as xs:string {
    let $want := "Heading" || $lvl
    return
        if (pmf:has-para-style($config, $want)) then
            $want
        else if (pmf:has-para-style($config, "Normal")) then
            "Normal"
        else
            head(($config?docx-para-style-ids, "Normal"))
};

declare %private function pmf:resolve-table-style($config as map(*)) as xs:string? {
    if (pmf:has-table-style($config, "TableGrid")) then
        "TableGrid"
    else if (map:contains($config, "docx-table-style-ids") and exists($config?docx-table-style-ids)) then
        head($config?docx-table-style-ids)
    else
        ()
};

declare %private function pmf:resolve-para-style($config as map(*), $class as xs:string+) as xs:string {
    let $user := pmf:user-style-classes($class)
    let $hit := head((
        for $c in $user
        where normalize-space($c) != "" and pmf:has-para-style($config, $c)
        return string($c)
    ))
    return
        if (exists($hit)) then
            $hit
        else if (pmf:has-para-style($config, "Normal")) then
            "Normal"
        else
            head(($config?docx-para-style-ids, "Normal"))
};

declare %private function pmf:resolve-char-style($config as map(*), $class as xs:string+) as xs:string? {
    let $user := pmf:user-style-classes($class)
    return head((
        for $c in $user
        where normalize-space($c) != "" and pmf:has-char-style($config, $c)
        return string($c)
    ))
};

declare %private function pmf:run-props($config as map(*), $class as xs:string+) as element()* {
    let $char-style := pmf:resolve-char-style($config, $class)
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
