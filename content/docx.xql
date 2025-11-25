xquery version "3.1";

module namespace docx="http://existsolutions.com/teipublisher/docx";

declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties";
declare namespace rel="http://schemas.openxmlformats.org/package/2006/relationships";
declare namespace r="http://schemas.openxmlformats.org/officeDocument/2006/relationships";
declare namespace pkg="http://schemas.microsoft.com/office/2006/xmlPackage";

import module namespace compression="http://exist-db.org/xquery/compression" at "java:org.exist.xquery.modules.compression.CompressionModule";

(: Handle different copy functions between eXist 4.x.x and 5.x.x :)
declare variable $docx:copy :=
    let $copy4 := function-lookup(xs:QName("xmldb:copy"), 3)
    return
        if (exists($copy4)) then
            $copy4
        else
            function ($source, $target, $resource) {
                function-lookup(xs:QName("xmldb:copy-resource"), 4)($source, $resource, $target, $resource)
            }
;

declare function docx:process($path as xs:string, $dataRoot as xs:string, $transform as function(*),
    $mediaPath as xs:string?) {
    if (util:binary-doc-available($path)) then
        let $tempColl := docx:mkcol-recursive($dataRoot, "temp")
        let $unzipped := docx:unzip($dataRoot || "/temp", $path)
        let $document := docx:normalize-ranges(doc($unzipped || "/word/document.xml"))
        let $styles := docx:extract-styles(util:expand(doc($unzipped || "/word/styles.xml")/w:styles))
        let $numbering := doc($unzipped || "/word/numbering.xml")/w:numbering
        let $endnotes := docx:normalize-ranges(doc($unzipped || "/word/endnotes.xml")/w:endnotes)
        let $footnotes := docx:normalize-ranges(doc($unzipped || "/word/footnotes.xml")/w:footnotes)
        let $comments := docx:normalize-ranges(doc($unzipped || "/word/comments.xml")/w:comments)
        let $properties := doc($unzipped || "/docProps/core.xml")/cp:coreProperties
        let $rels := doc($unzipped || "/word/_rels/document.xml.rels")/rel:Relationships
        let $linkRels := map {
            "document": $rels,
            "footnotes": doc($unzipped || "/word/_rels/footnotes.xml.rels")/rel:Relationships,
            "endnotes": doc($unzipped || "/word/_rels/endnotes.xml.rels")/rel:Relationships
        }
        let $params := map {
            "filename": replace($path, "^.*?([^/]+)$", "$1"),
            "rstyles": doc($unzipped || "/word/styles.xml")/w:styles,
            "styles": $styles,
            "pstyle": docx:pstyle($styles, ?),
            "cstyle": docx:cstyle($styles, ?),
            "nstyle": docx:nstyle($numbering, $styles, ?),
            "endnote": docx:endnote($endnotes, ?),
            "footnote": docx:footnote($footnotes, ?),
            "comment": docx:comment($comments, ?),
            "link": docx:external-link($linkRels, ?),
            "rels": $rels,
            "document": $document,
            "properties": $properties
        }
        return (
            $transform($document, $params),
            if (exists($mediaPath)) then
                docx:copy-media($rels, $unzipped, $mediaPath)
            else
                (),
            xmldb:remove($unzipped)
        )
    else
        ()
};

declare function docx:process-pkg($package as document-node(), $transform as function(*)) {
    let $document := docx:normalize-ranges($package//pkg:part[@pkg:name = "/word/document.xml"]/pkg:xmlData/w:document)
    let $styles := docx:extract-styles(util:expand($package//pkg:part[@pkg:name = "/word/styles.xml"])/pkg:xmlData/w:styles)
    let $numbering := $package//pkg:part[@pkg:name = "/word/numbering.xml"]/pkg:xmlData/w:numbering
    let $endnotes := docx:normalize-ranges($package//pkg:part[@pkg:name = "/word/endnotes.xml"]/pkg:xmlData/w:endnotes)
    let $footnotes := docx:normalize-ranges($package//pkg:part[@pkg:name = "/word/footnotes.xml"]/pkg:xmlData/w:footnotes)
    let $comments := docx:normalize-ranges($package//pkg:part[@pkg:name = "/word/comments.xml"]/pkg:xmlData/w:comments)
    let $properties := $package//pkg:part[@pkg:name = "/docProps/core.xml"]/pkg:xmlData/cp:coreProperties
    let $rels := $package//pkg:part[@pkg:name = "/word/_rels/document.xml.rels"]/pkg:xmlData/rel:Relationships
    let $params := map {
        "filename": "test.docx",
        "rstyles": $package//pkg:part[@pkg:name = "/word/styles.xml"]/pkg:xmlData/w:styles,
        "styles": $styles,
        "pstyle": docx:pstyle($styles, ?),
        "cstyle": docx:cstyle($styles, ?),
        "nstyle": docx:nstyle($numbering, $styles, ?),
        "endnote": docx:endnote($endnotes, ?),
        "footnote": docx:footnote($footnotes, ?),
        "comment": docx:comment($comments, ?),
        "link": docx:external-link($rels, ?),
        "rels": $rels,
        "document": $document,
        "properties": $properties
    }
    return
        $transform($document, $params)
};

(:~ Copy any images from an unzipped docx archive into a separate collection so they can be referenced from the transformed TEI document
 :
 : @param $rels                  a rel:Relationships element from a docx archive's word/_rels/document.xml.rels file
 : @param $unzipped-archive-col  the absolute "/db/..." path to the source collection containing the contents of the unzipped archive
 : @param $destination-media-col the absolute "/db/..." path to the desination collection where the media files should be copied to
 :)
declare function docx:copy-media($rels as element(rel:Relationships), $unzipped-archive-col as xs:string, $destination-media-col as xs:string) as empty-sequence() {
    let $pathComponents := tokenize(replace($destination-media-col, "^/db/(.*)$", "$1"), "/")
    let $collection := docx:mkcol-recursive("/db", $pathComponents)
    (: When processing a rel:Relationship/@Target value, remember that:
     :
     : 1. An **absolute** path (with a leading slash;  i.e., "^/.+$"   ) implicitly starts from the unzipped archive's "/"      root directory;
     : 2. A  **relative** path (with no leading slash; i.e., "^[^/].+$") implicitly starts from the unzipped archive's "/word/" subdirectory 
     :    that contains the "rels" folder whose "document.xml.rels" contains the <rel:Relationship> element being processed.
     :
     : In order to successfully copy the resource from the unzipped archive into the destination media folder, 
     : we need to identify the image's path, relative to the unzipped archive's root directory.
     :
     : Here are examples of the two types of @Target and the actual location relative to the unzipped archive's root directory:
     : 
     :   | Path Type | @Target            | Actual Location                             |
     :   | --------- | ------------------ | ------------------------------------------- |
     :   | Absolute  | "/media/image.png" | [unzipped-archive-dir]/media/image.png      |
     :                  ^                                         ^
     :   | Relative  | "media/image.png"  | [unzipped-archive-dir]/word/media/image.png |
     :                  ^                                         ^^^^^^
     : 
     : Both absolute and relative forms have been observed and tested in real MS Word OpenXML files.
     :)
    for $image in $rels/rel:Relationship
        [@Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"]
        [not(@TargetMode = "External")]
    let $image-path := $image/@Target
    (: Split @Target path into the image's directory and filename components :)
    let $analyze-path := analyze-string($image-path, "^(.*?)([^/]+)$")
    let $image-dir :=      $analyze-path//fn:group[@nr eq "1"]/string()
    let $image-filename := $analyze-path//fn:group[@nr eq "2"]/string()
    let $dir-from-archive-root := 
        (: Case 1: @Target is already **absolute** from the unzipped archive's root directory :)
        if (starts-with($image-dir, "/")) then
            (: Take just the directory portion of @Target, discarding the filename :)
            $image-dir
        (: Cast 2: @Target is **relative** to the "word" subdirectory inside the unzipped archive's root directory :)
        else
            (: Prepend "/word/" to the directory portion of @Target :)
            "/word/" || $image-dir
    let $source-media-col:= $unzipped-archive-col || $dir-from-archive-root
    let $copy := $docx:copy($source-media-col, $destination-media-col, $image-filename)
    return
        ()
};


declare function docx:pstyle($styles as map(*), $node as element()) {
    $styles?($node/w:pPr/w:pStyle/@w:val)
};

declare function docx:cstyle($styles as map(*), $node as element()) {
    let $style := $node//w:rStyle/@w:val
    return
        if ($style) then
            $styles($style)
        else
            ()
};

declare function docx:nstyle($numbering as element()*, $styles as map(*), $node as element()) {
    let $ref := $node/w:pPr/w:numPr
    let $ref := if ($ref) then $ref else docx:pstyle($styles, $node)/w:pPr/w:numPr
    where $ref
    let $lvl := head(($ref/w:ilvl/@w:val, 0))
    let $num := $numbering/w:num[@w:numId = $ref/w:numId/@w:val]
    let $abstractNumRef := $num/w:abstractNumId/@w:val
    let $abstractNum := $numbering/w:abstractNum[@w:abstractNumId = $abstractNumRef]
    return
        $abstractNum/w:lvl[@w:ilvl = $lvl]
};

declare function docx:endnote($endnotes as element()*, $node as element()) {
    let $id := $node/w:endnoteReference/@w:id
    let $endnote := $endnotes/w:endnote[@w:id = $id]
    return
        $endnote/*
};

declare function docx:footnote($footnotes as element()*, $node as element()) {
    let $id := $node/w:footnoteReference/@w:id
    let $footnote := $footnotes/w:footnote[@w:id = $id]
    return
        $footnote/*
};

declare function docx:comment($comments as element()*, $node as element()) {
    let $id := $node/@w:id
    return
        $comments/w:comment[@w:id = $id]/*
};

declare function docx:external-link($rels as map(*), $node as element()) {
    if ($node/ancestor::w:footnote) then
        $rels?footnotes/rel:Relationship[@Id=$node/@r:id]
    else if ($node/ancestor::w:endnote) then
        $rels?endnotes/rel:Relationship[@Id=$node/@r:id]
    else
        $rels?document/rel:Relationship[@Id=$node/@r:id]
};

declare function docx:extract-styles($doc as element()?) {
    map:merge(
        for $style in $doc/w:style
        return
            map:entry($style/@w:styleId/string(), $style)
    )
};

declare %private function docx:unzip($collection as xs:string, $docx as xs:string) {
    let $fileName := replace($docx, "^.*?/([^/]+)$", "$1")
    let $name := xmldb:encode-uri(replace($fileName, "^([^\.]+)\..*$", "$1"))
    let $targetCol := $collection || "/" || $name
    let $createCol :=
        if (not(xmldb:collection-available($targetCol))) then
            xmldb:create-collection($collection, $name)
        else
            ()
    let $unzipped :=
        compression:unzip(util:binary-doc($docx),
            function($path as xs:anyURI, $type as xs:string, $param as item()*) { true() },
            (),
            docx:unzip-file($targetCol, ?, ?, ?, ?),
            ()
        )
    return
        $targetCol
};

declare %private function docx:unzip-file($targetCol as xs:string, $path as xs:anyURI, $type as xs:string,
    $data as item()?, $param as item()*) {
    let $fileName := replace($path, "^.*?/?([^/]+)$", "$1")
    let $trash := fn:starts-with($path,'[trash]')
    let $target :=
        if (contains($path, "/")) then
            let $relPath := replace($path, "^(.*?)/[^/]+$", "$1")
(: skip [trash] folder in some docx files :)
            let $newPath := if ($trash) then () else docx:mkcol-recursive($targetCol, tokenize($relPath, "/"))
            return
                if ($trash) then $targetCol else $targetCol || "/" || $relPath
        else
            $targetCol
    return
        xmldb:store($target, xmldb:encode-uri($fileName), $data)
};

declare %private function docx:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            xmldb:create-collection($collection, $components[1]),
            docx:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        $collection
};

(:~
 : Normalize ranges of w:r using same style. Word tends to split ranges at
 : random points, so to simplify processing we're trying to collect all ranges referencing the same
 : character style into a single w:r element.
 :)
declare %private function docx:normalize-ranges($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case document-node() return
                document {
                    docx:normalize-ranges($node/node())
                }
            case element(w:r) return
                let $style := $node/w:rPr/w:rStyle/@w:val
                return
                    if (exists($style)) then
                        (: preceding ranges with same style are nested, but style is stripped :)
                        if ($node/preceding-sibling::w:r[1]/w:rPr/w:rStyle/@w:val = $style) then
                            ()
                        else
                            (: nest subsequent ranges with same style into current one :)
                            let $siblings := docx:get-range-siblings($node, $style)
                            return
                                if (count($siblings) = 1) then
                                    $node
                                else
                                    <w:r>
                                    {
                                        $node/w:rPr,
                                        for $sibling in $siblings
                                        return
                                            <w:r>
                                                <w:rPr>
                                                { $sibling/w:rPr/* except $sibling/w:rPr/w:rStyle }
                                                </w:rPr>
                                                { $sibling/* except $sibling/w:rPr }
                                            </w:r>
                                    }
                                    </w:r>
                    else
                        $node
            case element(w:p) return
                (: remove empty paragraphs :)
                if (empty($node/w:r)) then
                    ()
                else
                    <w:p>
                    { docx:normalize-ranges($node/node()) }
                    </w:p>
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    docx:normalize-ranges($node/node())
                }
            default return
                $node
};

declare %private function docx:get-range-siblings($node as node()?, $style as xs:string?) {
    if (exists($node) and exists($style) and $node/w:rPr/w:rStyle/@w:val = $style) then
        ($node, docx:get-range-siblings($node/following-sibling::w:r[1], $style))
    else
        ()
};
