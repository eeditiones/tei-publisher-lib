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
import module namespace css="http://www.tei-c.org/tei-simple/xquery/css";
import module namespace http="http://expath.org/ns/http-client" at "java:org.exist.xquery.modules.httpclient.HTTPClientModule";
import module namespace compression="http://exist-db.org/xquery/compression" at "java:org.exist.xquery.modules.compression.CompressionModule";

declare variable $pmf:FOOTNOTE_COUNTER := "docx-fn-" || util:uuid();
declare variable $pmf:LINK_COUNTER    := "docx-lnk-" || util:uuid();
declare variable $pmf:GRAPHIC_COUNTER   := "docx-gr-" || util:uuid();
declare variable $pmf:DOC_PR_COUNTER    := "docx-dp-" || util:uuid();
declare variable $pmf:LIB_URI         := "http://existsolutions.com/apps/tei-publisher-lib";

(: Template numIds (numbering.xml): 1=ListBullet, 5=ListNumber — used only as listItem fallback. :)
declare variable $pmf:BULLET_NUM_ID  := "1";
declare variable $pmf:ORDERED_NUM_ID := "5";
(: Each list() allocates a new w:num (numId ≥ LIST_NUM_MIN). Use abstract 9/10 (not 7/8):
   7 and 8 bind w:pStyle ListNumber/ListBullet; those styles hard-code template numIds 5/1,
   so Word kept one global counter. 9/10 match layout but omit pStyle so instances stay separate. :)
declare variable $pmf:LIST_NUM_MIN            := 100;
declare variable $pmf:ORDERED_LIST_ABSTRACT := "9";
declare variable $pmf:BULLET_LIST_ABSTRACT  := "10";
declare variable $pmf:LIST_NUM_COUNTER        := "docx-lst-" || util:uuid();

declare variable $pmf:FN_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes";
declare variable $pmf:HL_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink";
declare variable $pmf:IMG_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image";
declare variable $pmf:THUMB_REL_TYPE := "http://schemas.openxmlformats.org/officeDocument/2006/relationships/metadata/thumbnail";
declare variable $pmf:NS_MC := "http://schemas.openxmlformats.org/markup-compatibility/2006";
declare variable $pmf:NS_PKG_RELS := "http://schemas.openxmlformats.org/package/2006/relationships";
(: Only these OPC root relationships are emitted; anything else (customXml, signatures, …)
   would point at parts we do not assemble and Word will offer recovery. :)
declare variable $pmf:ROOT_REL_TYPES_ALLOWED := (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument",
    "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties",
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties",
    $pmf:THUMB_REL_TYPE
);

(: ============================================================
   Lifecycle: init / prepare / finish
   ============================================================ :)

declare function pmf:init($config as map(*), $node as node()*) {
    let $styles-doc := pmf:load-template-xml($config, "word/styles.xml")
    let $styles := $styles-doc//w:style
    let $odd-doc := if ($config?odd) then doc($config?odd) else ()
    let $odd-css := if (exists($odd-doc)) then css:generate-css($odd-doc, "docx", $config?odd) else ""
    let $odd-styles := if ($odd-css != "") then css:parse-css($odd-css) else map {}
    let $rendition-css := string-join(css:rendition-styles-html($config, $node))
    let $rendition-styles := if ($rendition-css != "") then css:parse-css($rendition-css) else map {}
    let $all-styles := map:merge(($odd-styles, $rendition-styles), map { "duplicates": "use-last" })
    return
        map:merge((
            $config,
            map {
                "rendition-styles": $all-styles,
                "docx-para-style-ids": distinct-values((
                    for $id in $styles[@w:type = "paragraph"]/@w:styleId
                    return string($id)[normalize-space(.) != ""],
                    "Figure", "Caption", "FootnoteText"
                )),
                "docx-char-style-ids": distinct-values((
                    for $id in $styles[@w:type = "character"]/@w:styleId
                    return string($id)[normalize-space(.) != ""],
                    "Hyperlink", "FootnoteReference"
                )),
                "docx-table-style-ids": distinct-values(
                    for $id in $styles[@w:type = "table"]/@w:styleId
                    return string($id)[normalize-space(.) != ""]
                ),
                "docx-para-style-id-by-name": map:merge(
                    for $s in $styles[@w:type = "paragraph"]
                    let $id := string($s/@w:styleId)
                    let $name := lower-case(normalize-space(string($s/w:name/@w:val)))
                    where $id != "" and $name != ""
                    return map:entry($name, $id)
                ),
                "docx-table-style-id-by-name": map:merge(
                    for $s in $styles[@w:type = "table"]
                    let $id := string($s/@w:styleId)
                    let $name := lower-case(normalize-space(string($s/w:name/@w:val)))
                    where $id != "" and $name != ""
                    return map:entry($name, $id)
                )
            }
        ), map { "duplicates": "use-last" })
};

declare function pmf:prepare($config as map(*), $node as node()*) {
    counters:create($pmf:FOOTNOTE_COUNTER),
    counters:create($pmf:LINK_COUNTER),
    counters:create($pmf:GRAPHIC_COUNTER),
    counters:create($pmf:DOC_PR_COUNTER),
    counters:create($pmf:LIST_NUM_COUNTER),
    ()
};

declare function pmf:finish($config as map(*), $input as node()*) {
    let $_ := counters:destroy($pmf:FOOTNOTE_COUNTER)
    let $_ := counters:destroy($pmf:LINK_COUNTER)
    let $_ := counters:destroy($pmf:GRAPHIC_COUNTER)
    let $_ := counters:destroy($pmf:DOC_PR_COUNTER)
    let $_ := counters:destroy($pmf:LIST_NUM_COUNTER)
    let $footnotes := $input//docx:footnote
    let $body-links := $input//docx:hyperlink[not(ancestor::docx:footnote)]
    let $fn-links   := $input//docx:footnote//docx:hyperlink
    let $images := $input//docx:image
    let $image-build := pmf:build-image-package($config, $images)
    let $cfg2 := map:merge((
        $config,
        map { "docx-image-by-rid": $image-build?by-rid }
    ), map { "duplicates": "use-last" })
    let $list-nums := $input//docx:list-instance
    let $body-nodes := pmf:wrap-top-level-runs-in-paragraphs(pmf:clean-body($cfg2, $input))
    return
        pmf:assemble-package(
            $cfg2,
            $body-nodes,
            $footnotes,
            $body-links,
            $fn-links,
            exists($footnotes),
            $image-build?items,
            $list-nums
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

(: Do not wrap the whole block in one w:p: nested w:p (heading, paragraph, figure caption)
   must stay real paragraphs. A single outer w:p with nested w:p caused flatten-paragraph to
   merge all loose w:r (e.g. figure drawings) into the first slice, so images jumped before
   headings and captions drifted away from figures. :)
declare function pmf:block($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:block-children($config, $node, $class, $config?apply-children($config, $node, $content))
};

declare %private function pmf:block-item-is-structural($item as item()) as xs:boolean {
    $item instance of element(w:p) or $item instance of element(w:tbl)
};

declare %private function pmf:block-take-leading-inlines($items as item()*) as item()* {
    if (empty($items)) then
        ()
    else if (pmf:block-item-is-structural(head($items))) then
        ()
    else
        (head($items), pmf:block-take-leading-inlines(tail($items)))
};

(: Whitespace-only text between block children used to live inside one outer w:p and was dropped
   when flatten-paragraph removed an empty shell. block-children must not emit a w:p for that. :)
declare %private function pmf:block-item-has-visible-content($i as item()) as xs:boolean {
    typeswitch ($i)
        case text() return
            normalize-space(string($i)) != ""
        case element(w:r) return
            exists($i/descendant::w:t[normalize-space(string(.)) != ""])
            or exists($i/descendant::w:drawing)
            or exists($i/descendant::w:footnoteReference)
            or exists($i/descendant::w:tab)
            or exists($i/descendant::w:br)
            or exists($i/descendant::w:object)
        case element() return
            true()
        default return
            true()
};

declare %private function pmf:block-run-has-visible-content($run as item()*) as xs:boolean {
    some $i in $run satisfies pmf:block-item-has-visible-content($i)
};

declare %private function pmf:block-children($config as map(*), $node as node(), $class as xs:string+, $items as item()*) as node()* {
    if (empty($items)) then
        ()
    else
        let $h := head($items)
        let $t := tail($items)
        return
            typeswitch ($h)
                case element(w:p) return
                    ($h, pmf:block-children($config, $node, $class, $t))
                case element(w:tbl) return
                    ($h, pmf:block-children($config, $node, $class, $t))
                default return
                    let $run := ($h, pmf:block-take-leading-inlines($t))
                    let $rest := subsequence($items, 1 + count($run))
                    return
                        if (pmf:block-run-has-visible-content($run)) then
                            (
                                <w:p>
                                    <w:pPr><w:pStyle w:val="{pmf:resolve-para-style($config, $class)}"/></w:pPr>
                                    { pmf:block-normalize-run($class, $run) }
                                </w:p>,
                                pmf:block-children($config, $node, $class, $rest)
                            )
                        else
                            pmf:block-children($config, $node, $class, $rest)
};

declare %private function pmf:block-normalize-run($class as xs:string+, $run as item()*) as node()* {
    let $preserve := pmf:preserve-whitespace($class)
    for $item in $run
    return
        typeswitch($item)
            case text() return
                let $s := pmf:normalize-text(string($item), $preserve)
                where $s != ''
                return
                    if ($preserve) then
                        pmf:text-to-runs($s, ())
                    else if (normalize-space($s) != '') then
                        <w:r>{ pmf:make-t($s) }</w:r>
                    else ()
            default return $item
};

declare function pmf:inline($config as map(*), $node as node(), $class as xs:string+, $content) {
    let $run-props := pmf:run-props($config, $class)
    let $preserve-text := pmf:preserve-whitespace($class)
    let $all :=
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
                    where $text != ''
                    return
                        if ($preserve-text) then
                            pmf:text-to-runs($text, $run-props)
                        else if (normalize-space($text) != '') then
                            <w:r>
                                <w:rPr>{ $run-props }</w:rPr>
                                { pmf:make-t($text) }
                            </w:r>
                        else
                            <docx:ws/>
                default return $child
    return pmf:keep-interior-whitespace($all)
};

declare function pmf:text($config as map(*), $node as node(), $class as xs:string+, $content) {
    let $preserve := pmf:preserve-whitespace($class)
    let $str := pmf:normalize-text(string($content), $preserve)
    let $rPr := pmf:run-props($config, $class)
    where
        if ($preserve) then $str != ''
        else $str != '' and normalize-space($str) != ''
    return
        if ($preserve) then
            pmf:text-to-runs($str, $rPr)
        else if (exists($rPr)) then
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
    let $abstract :=
        if ($type = "ordered") then
            $pmf:ORDERED_LIST_ABSTRACT
        else
            $pmf:BULLET_LIST_ABSTRACT
    let $seq := counters:increment($pmf:LIST_NUM_COUNTER)
    let $numId := xs:integer($pmf:LIST_NUM_MIN) + $seq - 1
    let $config := map:merge(($config, map {
        "list-num-id": string($numId),
        "list-level": (($config?list-level, 0)[1] + 1)
    }), map { "duplicates": "use-last" })
    return
        (
            <docx:list-instance numId="{string($numId)}" abstractNumId="{$abstract}"/>,
            $config?apply-children($config, $node, $content)
        )
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
    let $items := $config?apply-children($config, $node, $content)
    let $body  := pmf:block-children($config, $node, $class, $items)
    return
        <w:tc>
            {
                if ($node/@cols castable as xs:integer and xs:integer($node/@cols) > 1) then
                    <w:tcPr><w:gridSpan w:val="{$node/@cols}"/></w:tcPr>
                else ()
            }
            { if (empty($body)) then <w:p/> else $body }
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

declare function pmf:link($config as map(*), $node as node(), $class as xs:string+, $content, $uri, $target, $optional as map(*)) {
    let $raw := normalize-space(string($uri))
    return
        if ($raw = "") then
            pmf:apply-runs($config, $node, $class, $content)
        else if (starts-with($raw, "#")) then
            let $anchor := normalize-space(substring($raw, 2))
            return
                if ($anchor = "") then
                    pmf:apply-runs($config, $node, $class, $content)
                else
                    <w:hyperlink w:anchor="{$anchor}">
                        { pmf:link-runs($config, $node, $class, $content) }
                    </w:hyperlink>
        else
            let $rId := "rLnk" || counters:increment($pmf:LINK_COUNTER)
            return
                <docx:hyperlink href="{$raw}" rId="{$rId}">
                    { pmf:link-runs($config, $node, $class, $content) }
                </docx:hyperlink>
};

declare %private function pmf:link-runs($config as map(*), $node as node(), $class as xs:string+, $content) as node()* {
    for $r in pmf:apply-runs($config, $node, $class, $content)
    return
        if ($r instance of element(w:r)) then
            <w:r>
                <w:rPr>
                    <w:rStyle w:val="Hyperlink"/>
                    { $r/w:rPr/node() }
                </w:rPr>
                { $r/node()[not(self::w:rPr)] }
            </w:r>
        else
            $r
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

declare function pmf:pass-through($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:apply-runs($config, $node, $class, $content)
};

declare function pmf:caption($config as map(*), $node as node(), $class as xs:string+, $content) {
    pmf:caption($config, $node, $class, $content, ())
};

declare function pmf:caption($config as map(*), $node as node(), $class as xs:string+, $content,
    $prefix as xs:string?) {
    let $pstyle :=
        if (pmf:has-para-style($config, "Caption")) then
            "Caption"
        else
            pmf:resolve-para-style($config, $class)
    return
        <w:p>
            <w:pPr><w:pStyle w:val="{$pstyle}"/></w:pPr>
            {
                if (exists($prefix) and normalize-space($prefix) != "") then
                    <w:r>{ pmf:make-t($prefix) }</w:r>
                else
                    ()
            }
            { pmf:apply-runs($config, $node, $class, $content) }
        </w:p>
};

declare function pmf:figure($config as map(*), $node as node(), $class as xs:string+, $content, $title) {
    let $items := $config?apply-children($config, $node, $content)
    let $fig-class := ("Figure", $class)
    let $paras := pmf:block-children($config, $node, $fig-class, $items)
    let $has-caption := exists($title) and normalize-space(string-join($title, "")) != ""
    return (
        if ($has-caption) then
            for $p in $paras
            return
                if ($p instance of element(w:p)) then pmf:p-add-keep-next($p) else $p
        else
            $paras,
        if ($has-caption) then
            pmf:caption($config, $node, ("tei-caption"), $title)
        else
            ()
    )
};

declare %private function pmf:p-add-keep-next($p as element(w:p)) as element(w:p) {
    <w:p>
        {
            if ($p/w:pPr) then
                <w:pPr>
                    { $p/w:pPr/@*, $p/w:pPr/node() }
                    { if (not($p/w:pPr/w:keepNext)) then <w:keepNext/> else () }
                </w:pPr>
            else
                <w:pPr><w:keepNext/></w:pPr>
        }
        { $p/node()[not(self::w:pPr)] }
    </w:p>
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
    (: Name each media part from the drawing relationship id (rId10 → media/image10.*), not
       from the pack sequence index. Otherwise document-order packing can assign image1.png to
       rId11 etc., which mis-binds binaries and can make Word reject the package. :)
    let $packed :=
        for $s in $sentinels
        let $binary := pmf:default-fetch-image-binary($config, string($s/@url))
        where exists($binary)
        return map { "sentinel": $s, "binary": $binary }
    let $items :=
        for $p in $packed
        let $s := $p?sentinel
        let $ext := pmf:image-file-extension(string($s/@url))
        let $rid-suffix := replace(normalize-space(string($s/@rId)), "^rId", "")
        let $base :=
            if ($rid-suffix != "") then
                "image" || $rid-suffix
            else
                "image-unknown"
        return
            map {
                "rId": string($s/@rId),
                "target": "media/" || $base || "." || $ext,
                "part-name": "/word/media/" || $base || "." || $ext,
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
    let $doc-pr := xs:integer(string($img/@docPrId))
    (: Word may reject many drawings that all use pic:cNvPr id="0"; keep wp:docPr id as-is and
       assign a disjoint high-range id for cNvPr (must not equal wp:docPr/@id in the same shape). :)
    let $c-nv-id := 32768 + $doc-pr
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
                                    <pic:cNvPr id="{$c-nv-id}" name=""/>
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
            case element(docx:list-instance) return ()
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
                if (normalize-space(string($node/@href)) = "") then
                    pmf:clean-body($config, $node/node())
                else
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
                if (namespace-uri($node) = "http://schemas.openxmlformats.org/wordprocessingml/2006/main") then
                    element { node-name($node) } {
                        $node/@*,
                        pmf:clean-body($config, $node/node())
                    }
                else
                    pmf:clean-body($config, $node/node())
            default return $node
};

declare %private function pmf:flatten-paragraph($config as map(*), $p as element(w:p)) as element(w:p)* {
    let $raw := pmf:clean-body($config, $p/node()[not(self::w:p)])
    let $content :=
        for $item in $raw
        return
            if ($item instance of text() and normalize-space(string($item)) != "") then
                <w:r>{ pmf:make-t(string($item)) }</w:r>
            else
                $item
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

(: Minimal templates (e.g. python-docx) often omit abstractNum 9/10; list() still emits w:num
   referencing $pmf:ORDERED_LIST_ABSTRACT / $pmf:BULLET_LIST_ABSTRACT. Without these definitions
   Word treats numbering.xml as corrupt. :)
declare %private function pmf:fallback-abstract-num-ordered() as element(w:abstractNum) {
    <w:abstractNum w:abstractNumId="{$pmf:ORDERED_LIST_ABSTRACT}">
        <w:nsid w:val="FFFFFF90"/>
        <w:multiLevelType w:val="singleLevel"/>
        <w:tmpl w:val="E1A62B41"/>
        <w:lvl w:ilvl="0">
            <w:start w:val="1"/>
            <w:numFmt w:val="decimal"/>
            <w:lvlText w:val="%1."/>
            <w:lvlJc w:val="left"/>
            <w:pPr>
                <w:tabs>
                    <w:tab w:val="num" w:pos="360"/>
                </w:tabs>
                <w:ind w:left="360" w:hanging="360"/>
            </w:pPr>
        </w:lvl>
    </w:abstractNum>
};

declare %private function pmf:fallback-abstract-num-bullet() as element(w:abstractNum) {
    <w:abstractNum w:abstractNumId="{$pmf:BULLET_LIST_ABSTRACT}">
        <w:nsid w:val="FFFFFF91"/>
        <w:multiLevelType w:val="singleLevel"/>
        <w:tmpl w:val="F29761A6"/>
        <w:lvl w:ilvl="0">
            <w:start w:val="1"/>
            <w:numFmt w:val="bullet"/>
            <w:lvlText w:val=""/>
            <w:lvlJc w:val="left"/>
            <w:pPr>
                <w:tabs>
                    <w:tab w:val="num" w:pos="360"/>
                </w:tabs>
                <w:ind w:left="360" w:hanging="360"/>
            </w:pPr>
            <w:rPr>
                <w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/>
            </w:rPr>
        </w:lvl>
    </w:abstractNum>
};

declare %private function pmf:make-numbering-xml($config as map(*), $extra as element(docx:list-instance)*) as element() {
    let $root := pmf:load-template-xml($config, "word/numbering.xml")/*
    let $abstracts := $root/w:abstractNum
    let $nums := $root/w:num
    let $abstract-ids := $abstracts ! xs:string(@w:abstractNumId)
    let $inject-abstracts := (
        if ($pmf:ORDERED_LIST_ABSTRACT = $abstract-ids) then
            ()
        else
            pmf:fallback-abstract-num-ordered(),
        if ($pmf:BULLET_LIST_ABSTRACT = $abstract-ids) then
            ()
        else
            pmf:fallback-abstract-num-bullet()
    )
    return
        element { node-name($root) } {
            (: Rebuilding the root drops most xmlns:* from the template; mc:Ignorable then names
               prefixes (w14, wp14) that are no longer declared and Word refuses the package. :)
            $root/@*[
                not(namespace-uri(.) = $pmf:NS_MC and local-name(.) = "Ignorable")
            ],
            $abstracts,
            $inject-abstracts,
            $nums,
            for $x in $extra
            return
                <w:num w:numId="{string($x/@numId)}">
                    <w:abstractNumId w:val="{string($x/@abstractNumId)}"/>
                    <w:lvlOverride w:ilvl="0">
                        <w:startOverride w:val="1"/>
                    </w:lvlOverride>
                </w:num>
        }
};

(: eXist strips namespace declarations that are only referenced as text inside mc:Ignorable.
   Rebuilding the root element without mc:Ignorable avoids Word rejecting the part. :)
declare %private function pmf:strip-mc-ignorable($el as element()) as element() {
    element { node-name($el) } {
        $el/@*[
            not(namespace-uri(.) = $pmf:NS_MC and local-name(.) = "Ignorable")
        ],
        $el/node()
    }
};

declare %private function pmf:ensure-builtin-styles($styles-root as element()) as element() {
    let $need-hyperlink  := empty($styles-root/w:style[@w:styleId = "Hyperlink"])
    let $need-figure     := empty($styles-root/w:style[@w:styleId = "Figure"])
    let $need-caption    := empty($styles-root/w:style[@w:styleId = "Caption"])
    let $need-fn-text    := empty($styles-root/w:style[@w:styleId = "FootnoteText"])
    let $need-fn-ref     := empty($styles-root/w:style[@w:styleId = "FootnoteReference"])
    return
        if (not($need-hyperlink or $need-figure or $need-caption or $need-fn-text or $need-fn-ref)) then
            $styles-root
        else
            let $default-para := string(($styles-root/w:style[@w:type="paragraph"][@w:default="1"]/@w:styleId, "Normal")[1])
            let $default-char := string(($styles-root/w:style[@w:type="character"][@w:default="1"]/@w:styleId, "DefaultParagraphFont")[1])
            return
                element { node-name($styles-root) } {
                    $styles-root/@*,
                    $styles-root/node(),
                    if ($need-figure) then
                        <w:style w:type="paragraph" w:styleId="Figure">
                            <w:name w:val="Figure"/>
                            <w:basedOn w:val="{$default-para}"/>
                            <w:next w:val="Caption"/>
                            <w:uiPriority w:val="99"/>
                            <w:pPr>
                                <w:jc w:val="center"/>
                                <w:spacing w:before="120" w:after="0"/>
                            </w:pPr>
                        </w:style>
                    else (),
                    if ($need-caption) then
                        <w:style w:type="paragraph" w:styleId="Caption">
                            <w:name w:val="caption"/>
                            <w:basedOn w:val="{$default-para}"/>
                            <w:next w:val="{$default-para}"/>
                            <w:uiPriority w:val="35"/>
                            <w:qFormat/>
                            <w:rPr>
                                <w:i/>
                                <w:iCs/>
                            </w:rPr>
                        </w:style>
                    else (),
                    if ($need-fn-text) then
                        <w:style w:type="paragraph" w:styleId="FootnoteText">
                            <w:name w:val="footnote text"/>
                            <w:basedOn w:val="{$default-para}"/>
                            <w:link w:val="FootnoteTextChar"/>
                            <w:uiPriority w:val="99"/>
                            <w:semiHidden/>
                            <w:unhideWhenUsed/>
                            <w:pPr>
                                <w:spacing w:after="0" w:line="240" w:lineRule="auto"/>
                            </w:pPr>
                            <w:rPr>
                                <w:sz w:val="20"/>
                                <w:szCs w:val="20"/>
                            </w:rPr>
                        </w:style>
                    else (),
                    if ($need-fn-ref) then
                        <w:style w:type="character" w:styleId="FootnoteReference">
                            <w:name w:val="footnote reference"/>
                            <w:basedOn w:val="{$default-char}"/>
                            <w:uiPriority w:val="99"/>
                            <w:semiHidden/>
                            <w:unhideWhenUsed/>
                            <w:rPr>
                                <w:vertAlign w:val="superscript"/>
                            </w:rPr>
                        </w:style>
                    else (),
                    if ($need-hyperlink) then
                        <w:style w:type="character" w:styleId="Hyperlink">
                            <w:name w:val="Hyperlink"/>
                            <w:basedOn w:val="{$default-char}"/>
                            <w:uiPriority w:val="99"/>
                            <w:unhideWhenUsed/>
                            <w:rPr>
                                <w:color w:val="0563C1" w:themeColor="hyperlink"/>
                                <w:u w:val="single"/>
                            </w:rPr>
                        </w:style>
                    else ()
                }
};

(: One OPC Relationship row with stable namespace (avoids eXist xmlns="" on children). :)
declare %private function pmf:opc-rel(
    $id as xs:string,
    $type as xs:string,
    $target as xs:string,
    $target-mode as xs:string?
) as element() {
    element { QName($pmf:NS_PKG_RELS, "Relationship") } {
        attribute Id { $id },
        attribute Type { $type },
        attribute Target { $target },
        if (exists($target-mode) and normalize-space($target-mode) != "") then
            attribute TargetMode { $target-mode }
        else
            ()
    }
};

(: Normalize a stored *.rels part away from rel:Relationship / duplicate xmlns. :)
declare %private function pmf:canonical-opc-rels($root as node()) as element() {
    let $base :=
        if ($root instance of document-node()) then
            $root/*
        else
            $root
    let $rels := $base/*[local-name(.) = "Relationship"]
    return
        element { QName($pmf:NS_PKG_RELS, "Relationships") } {
            for $r in $rels
            return
                pmf:opc-rel(
                    string($r/@Id),
                    string($r/@Type),
                    string($r/@Target),
                    if ($r/@TargetMode) then
                        string($r/@TargetMode)
                    else
                        ()
                )
        }
};

(: Section properties from a real Word template may reference headers/footers via r:id; we replace
   word/_rels/document.xml.rels and do not ship header/footer parts — drop those references. :)
declare %private function pmf:sect-pr-for-output($sectPr as element(w:sectPr)?) as element(w:sectPr)? {
    if (empty($sectPr)) then
        ()
    else
        let $out :=
            element { node-name($sectPr) } {
                $sectPr/@*,
                for $c in $sectPr/*
                return
                    typeswitch ($c)
                        case element(w:headerReference) return ()
                        case element(w:footerReference) return ()
                        default return $c
            }
        return
            if (exists($out/w:pgSz)) then
                $out
            else
                pmf:default-sect-pr()
};

(: Package root: canonical template rels + thumbnail row when missing. :)
declare %private function pmf:root-rels-for-package($config as map(*)) as element() {
    let $core := pmf:canonical-opc-rels(pmf:load-template-xml($config, "_rels/.rels"))
    let $rels := $core/*[string(./@Type) = $pmf:ROOT_REL_TYPES_ALLOWED]
    let $has-thumb := exists($rels[string(@Type) = $pmf:THUMB_REL_TYPE])
    let $next-rid :=
        if ($has-thumb) then
            ()
        else
            let $nums :=
                for $r in $rels
                let $id := replace(string($r/@Id), "^rId", "", "i")
                where $id castable as xs:integer
                return xs:integer($id)
            return
                max(($nums, 0)) + 1
    let $thumb :=
        if ($has-thumb) then
            ()
        else
            pmf:opc-rel("rId" || $next-rid, $pmf:THUMB_REL_TYPE, "docProps/thumbnail.jpeg", ())
    return
        element { QName($pmf:NS_PKG_RELS, "Relationships") } {
            $rels,
            $thumb
        }
};

declare %private function pmf:assemble-package(
    $config         as map(*),
    $body-nodes     as node()*,
    $footnotes      as element(docx:footnote)*,
    $body-links     as element(docx:hyperlink)*,
    $fn-links       as element(docx:hyperlink)*,
    $has-footnotes  as xs:boolean,
    $image-items    as map(*)*,
    $list-nums      as element(docx:list-instance)*
) as element(pkg:package) {
    let $sectPr        := pmf:sect-pr-for-output(pmf:load-template-xml($config, "word/document.xml")//w:sectPr)
    let $doc-xml       := pmf:make-document-xml($body-nodes, $sectPr)
    let $doc-rels      := pmf:make-document-rels($body-links, $has-footnotes, $image-items)
    let $content-types := pmf:make-content-types($has-footnotes, $image-items)
    return
        <pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage">
            <pkg:part pkg:name="/[Content_Types].xml" pkg:contentType="application/xml">
                <pkg:xmlData>{ $content-types }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/_rels/.rels"
                pkg:contentType="application/vnd.openxmlformats-package.relationships+xml">
                <pkg:xmlData>{ pmf:root-rels-for-package($config) }</pkg:xmlData>
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
                            {
                                element { QName($pmf:NS_PKG_RELS, "Relationships") } {
                                    for $link in $fn-links
                                    let $href := normalize-space(string($link/@href))
                                    where $href != ""
                                    return
                                        pmf:opc-rel(string($link/@rId), $pmf:HL_REL_TYPE, $href, "External")
                                }
                            }
                        </pkg:xmlData>
                    </pkg:part>
                ) else ()
            }
            <pkg:part pkg:name="/word/styles.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml">
                <pkg:xmlData>{ pmf:ensure-builtin-styles(pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/styles.xml")/element())) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/stylesWithEffects.xml"
                pkg:contentType="application/vnd.ms-word.stylesWithEffects+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/stylesWithEffects.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/numbering.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml">
                <pkg:xmlData>{ pmf:make-numbering-xml($config, $list-nums) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/settings.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/settings.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/webSettings.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/webSettings.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/fontTable.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/fontTable.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/word/theme/theme1.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.theme+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "word/theme/theme1.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/core.xml"
                pkg:contentType="application/vnd.openxmlformats-package.core-properties+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "docProps/core.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/app.xml"
                pkg:contentType="application/vnd.openxmlformats-officedocument.extended-properties+xml">
                <pkg:xmlData>{ pmf:strip-mc-ignorable(pmf:load-template-xml($config, "docProps/app.xml")/element()) }</pkg:xmlData>
            </pkg:part>
            <pkg:part pkg:name="/docProps/thumbnail.jpeg"
                pkg:contentType="image/jpeg" pkg:compression="store">
                <pkg:binaryData>{ pmf:load-template-binary($config, "docProps/thumbnail.jpeg") }</pkg:binaryData>
            </pkg:part>
        </pkg:package>
};

declare %private function pmf:default-sect-pr() as element(w:sectPr) {
    <w:sectPr>
        <w:pgSz w:w="12240" w:h="15840"/>
        <w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="720" w:footer="720"
            w:gutter="0"/>
        <w:cols w:space="720"/>
        <w:docGrid w:linePitch="360"/>
    </w:sectPr>
};

declare %private function pmf:make-document-xml($body-nodes as node()*, $sectPr as element(w:sectPr)?) {
    <w:document
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
            { $body-nodes }
            { head(($sectPr, pmf:default-sect-pr())) }
        </w:body>
    </w:document>
};

declare %private function pmf:make-document-rels(
    $links         as element(docx:hyperlink)*,
    $has-footnotes as xs:boolean,
    $image-items   as map(*)*
) as element() {
    element { QName($pmf:NS_PKG_RELS, "Relationships") } {
        (: No customXml parts: template/bibliography custom XML is a frequent source of Word
           “unreadable content” when merged with generated body; TEI → DOCX does not need it. :)
        pmf:opc-rel("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering", "numbering.xml", ()),
        pmf:opc-rel("rId3", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml", ()),
        pmf:opc-rel("rId4", "http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects", "stylesWithEffects.xml", ()),
        pmf:opc-rel("rId5", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings", "settings.xml", ()),
        pmf:opc-rel("rId6", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings", "webSettings.xml", ()),
        pmf:opc-rel("rId7", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable", "fontTable.xml", ()),
        pmf:opc-rel("rId8", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", "theme/theme1.xml", ()),
        if ($has-footnotes) then
            pmf:opc-rel("rId9", $pmf:FN_REL_TYPE, "footnotes.xml", ())
        else
            (),
        for $im in $image-items
        return
            pmf:opc-rel(string($im?rId), $pmf:IMG_REL_TYPE, string($im?target), ()),
        for $link in $links
        let $href := normalize-space(string($link/@href))
        where $href != ""
        return
            pmf:opc-rel(string($link/@rId), $pmf:HL_REL_TYPE, $href, "External")
    }
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
        <Override PartName="/word/numbering.xml"        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        <Override PartName="/word/styles.xml"           ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        <Override PartName="/word/stylesWithEffects.xml" ContentType="application/vnd.ms-word.stylesWithEffects+xml"/>
        <Override PartName="/word/settings.xml"         ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
        <Override PartName="/word/webSettings.xml"      ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml"/>
        <Override PartName="/word/fontTable.xml"        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
        <Override PartName="/word/theme/theme1.xml"     ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/docProps/core.xml"         ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml"          ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        <Override PartName="/docProps/thumbnail.jpeg"   ContentType="image/jpeg"/>
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
    let $by-name :=
        if (map:contains($config, "docx-para-style-id-by-name")) then
            $config?docx-para-style-id-by-name?("heading " || $lvl)
        else
            ()
    return
        if (pmf:has-para-style($config, $want)) then
            $want
        else if (exists($by-name)) then
            $by-name
        else
            head((
                $config?docx-para-style-id-by-name?("normal"),
                if (pmf:has-para-style($config, "Normal")) then "Normal" else (),
                head($config?docx-para-style-ids),
                "Normal"
            ))
};

declare %private function pmf:resolve-table-style($config as map(*)) as xs:string? {
    let $by-name := $config?docx-table-style-id-by-name
    return
        if (pmf:has-table-style($config, "TableGrid")) then
            "TableGrid"
        else if (map:contains($config, "docx-table-style-id-by-name") and map:contains($by-name, "table grid")) then
            $by-name?("table grid")
        else if (map:contains($config, "docx-table-style-ids") and exists($config?docx-table-style-ids)) then
            head($config?docx-table-style-ids)
        else
            ()
};

declare %private function pmf:resolve-para-style($config as map(*), $class as xs:string+) as xs:string {
    let $user := pmf:user-style-classes($class)
    let $by-name := $config?docx-para-style-id-by-name
    let $hit := head((
        for $c in $user
        where normalize-space($c) != ""
        return
            if (pmf:has-para-style($config, $c)) then
                string($c)
            else if (map:contains($config, "docx-para-style-id-by-name") and map:contains($by-name, lower-case($c))) then
                $by-name?(lower-case($c))
            else
                ()
    ))
    let $normal := head((
        $by-name?("normal"),
        if (pmf:has-para-style($config, "Normal")) then "Normal" else (),
        head($config?docx-para-style-ids),
        "Normal"
    ))
    return
        if (exists($hit)) then $hit else $normal
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
    let $props := map:merge(
        for $c in $class
        let $m := $css-map?($c)
        where $m instance of map(*)
        return $m,
        map { "duplicates": "use-last" }
    )
    return (
        $r-style,
        if ($props?("font-weight") = "bold")                  then <w:b/>              else (),
        if ($props?("font-style")  = "italic")                then <w:i/>              else (),
        if ($props?("text-decoration") = "underline")         then <w:u w:val="single"/> else (),
        if ($props?("text-decoration") = "line-through")      then <w:strike/>         else (),
        if ($props?("vertical-align") = "super")              then <w:vertAlign w:val="superscript"/> else (),
        if ($props?("vertical-align") = "sub")                then <w:vertAlign w:val="subscript"/>   else ()
    )
};

(: ============================================================
   Private: run/text helpers
   ============================================================ :)

declare %private function pmf:apply-runs($config as map(*), $node as node(), $class as xs:string*, $content) as node()* {
    let $preserve-text := pmf:preserve-whitespace($class)
    let $all :=
        for $item in $config?apply-children($config, $node, $content)
        return
            typeswitch($item)
                case text() return
                    let $s := pmf:normalize-text(string($item), $preserve-text)
                    where $s != ''
                    return
                        if ($preserve-text) then
                            pmf:text-to-runs($s, ())
                        else if (normalize-space($s) != '') then
                            <w:r>{ pmf:make-t($s) }</w:r>
                        else
                            <docx:ws/>
                case xs:anyAtomicType return
                    let $s := pmf:normalize-text(string($item), $preserve-text)
                    where $s != ''
                    return
                        if ($preserve-text) then
                            pmf:text-to-runs($s, ())
                        else if (normalize-space($s) != '') then
                            <w:r>{ pmf:make-t($s) }</w:r>
                        else
                            <docx:ws/>
                default return $item
    return pmf:keep-interior-whitespace($all)
};

declare %private function pmf:preserve-whitespace($class as xs:string*) as xs:boolean {
    (: tei-code / tei-tag still appear for some TEI element names; otherwise match
       common Word style ids used for preformatted text (see template + cssClass). :)
    exists($class[. = ("tei-code", "tei-tag")])
    or exists(
        pmf:user-style-classes($class)[. = ("Code", "Preformatted", "CodeChar")]
    )
};

(: Kept for ODD compatibility; interior-whitespace preservation is now always on. :)
declare %private function pmf:normalize-whitespace($class as xs:string*) as xs:boolean {
    exists(pmf:user-style-classes($class)[. = "Normalize"])
};

(: Keep whitespace-only placeholder runs that fall between real content, drop leading/trailing.
   This mirrors CSS white-space collapsing for inline elements: inter-element spaces become one space. :)
declare %private function pmf:keep-interior-whitespace($items as node()*) as node()* {
    let $non-ws :=
        for $i in (1 to count($items))
        where not($items[$i] instance of element(docx:ws))
        return $i
    return
        if (empty($non-ws)) then ()
        else
            let $first := head($non-ws)
            let $last  := $non-ws[last()]
            for $i in (1 to count($items))
            let $item := $items[$i]
            return
                if ($item instance of element(docx:ws)) then
                    if ($i > $first and $i < $last) then
                        <w:r>{ pmf:make-t(" ") }</w:r>
                    else ()
                else
                    $item
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

(: Split text on newlines, emitting w:br between lines — for preserve-whitespace (Code) contexts. :)
declare %private function pmf:text-to-runs($text as xs:string, $rPr-content as node()*) as node()* {
    let $rPr := if (exists($rPr-content)) then <w:rPr>{ $rPr-content }</w:rPr> else ()
    for $line at $i in tokenize($text, "\r?\n")
    return (
        if ($i > 1) then <w:r>{ $rPr }<w:br/></w:r> else (),
        if ($line != '') then <w:r>{ $rPr }{ pmf:make-t($line) }</w:r> else ()
    )
};

(: ============================================================
   Private: template loading
   ============================================================ :)

declare %private function pmf:template-docx-path($config as map(*)) as xs:string? {
    let $raw := head(($config?docx-template, $config?parameters?docx-template))
    let $norm := normalize-space(string($raw))
    return if ($norm = "") then () else $norm
};

declare %private function pmf:extract-from-docx($docx-path as xs:string, $entry-path as xs:string) as item()? {
    let $zip := util:binary-doc($docx-path)
    return
        if (empty($zip)) then ()
        else
            let $result := head(
                compression:unzip(
                    $zip,
                    function($p as xs:anyURI, $type as xs:string, $param as item()*) as xs:boolean {
                        string($p) = $entry-path or string($p) = "./" || $entry-path
                    },
                    (),
                    function($p as xs:anyURI, $type as xs:string, $data as item()?, $param as item()*) as item()* {
                        $data
                    },
                    ()
                )
            )
            return
                if (exists($result)) then $result else ()
};

declare %private function pmf:load-template-binary($config as map(*), $path as xs:string) as xs:base64Binary {
    let $docx-path := pmf:template-docx-path($config)
    let $from-docx :=
        if (exists($docx-path)) then
            pmf:extract-from-docx($docx-path, $path)
        else
            ()
    return
        if ($from-docx instance of xs:base64Binary) then
            $from-docx
        else
            repo:get-resource($pmf:LIB_URI, "resources/docx/" || $path)
};

declare %private function pmf:load-template-xml($config as map(*), $path as xs:string) as document-node() {
    let $docx-path := pmf:template-docx-path($config)
    let $from-docx :=
        if (exists($docx-path)) then
            pmf:extract-from-docx($docx-path, $path)
        else
            ()
    return
        if (exists($from-docx)) then
            if ($from-docx instance of document-node()) then
                $from-docx
            else if ($from-docx instance of xs:base64Binary) then
                parse-xml(util:binary-to-string($from-docx, "UTF-8"))
            else
                parse-xml(string($from-docx))
        else
            parse-xml(util:binary-to-string(repo:get-resource($pmf:LIB_URI, "resources/docx/" || $path), "UTF-8"))
};
