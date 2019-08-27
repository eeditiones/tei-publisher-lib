xquery version "3.1";

module namespace docx="http://existsolutions.com/teipublisher/docx";

declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties";
declare namespace rel="http://schemas.openxmlformats.org/package/2006/relationships";
declare namespace r="http://schemas.openxmlformats.org/officeDocument/2006/relationships";

import module namespace compression="http://exist-db.org/xquery/compression" at "java:org.exist.xquery.modules.compression.CompressionModule";

(: Handle different copy functions between eXist 4.x.x and 5.x.x :)
declare variable $docx:copy :=
    let $copy4 := function-lookup(xs:QName("xmldb:copy"), 3)
    return
        if (exists($copy4)) then
            $copy4
        else
            let $copy5 := function-lookup(xs:QName("xmldb:copy-resource"), 4)
            return
                function ($source, $target, $resource) {
                    $copy5($source, $resource, $target, $resource)
                }
;

declare function docx:process($path as xs:string, $dataRoot as xs:string, $transform as function(*),
    $odd as xs:string) {
    docx:process($path, $dataRoot, $transform, ())
};

declare function docx:process($path as xs:string, $dataRoot as xs:string, $transform as function(*),
    $mediaPath as xs:string?) {
    if (util:binary-doc-available($path)) then
        let $tempColl := docx:mkcol-recursive($dataRoot, "temp")
        let $unzipped := docx:unzip($dataRoot || "/temp", $path)
        let $document := doc($unzipped || "/word/document.xml")
        let $styles := docx:extract-styles(util:expand(doc($unzipped || "/word/styles.xml")/w:styles))
        let $numbering := doc($unzipped || "/word/numbering.xml")/w:numbering
        let $endnotes := doc($unzipped || "/word/endnotes.xml")/w:endnotes
        let $footnotes := doc($unzipped || "/word/footnotes.xml")/w:footnotes
        let $properties := doc($unzipped || "/docProps/core.xml")/cp:coreProperties
        let $rels := doc($unzipped || "/word/_rels/document.xml.rels")/rel:Relationships
        let $params := map {
            "filename": replace($path, "^.*?([^/]+)$", "$1"),
            "styles": $styles,
            "pstyle": docx:pstyle($styles, ?),
            "cstyle": docx:cstyle($styles, ?),
            "nstyle": docx:nstyle($numbering, $styles, ?),
            "endnote": docx:endnote($endnotes, ?),
            "footnote": docx:footnote($footnotes, ?),
            "link": docx:external-link($rels, ?),
            "rels": $rels,
            "properties": $properties
        }
        return (
            $transform($document, $params),
            docx:copy-media($rels, $unzipped, $mediaPath),
            xmldb:remove($unzipped)
        )
    else
        ()
};

declare function docx:copy-media($rels as element(), $unzipped as xs:string, $mediaPath as xs:string?) {
    if ($mediaPath) then
        let $pathComponents := tokenize(replace($mediaPath, "^/db/(.*)$", "$1"), "/")
        let $collection := docx:mkcol-recursive("/db", $pathComponents)
        for $image in $rels/rel:Relationship
            [@Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"]
            [not(@TargetMode = "External")]
        let $target := $image/@Target
        let $relPath := replace($target, "^(.*?)/[^/]+$", "$1")
        let $imgName := replace($target, "^.*?([^/]+)$", "$1")
        return
            $docx:copy($unzipped || "/word/" || $relPath, $imgName, $mediaPath)[2]
    else
        ()
};


declare function docx:pstyle($styles as map(*), $node as element()) {
    $styles?($node/w:pPr/w:pStyle/@w:val)
};

declare function docx:cstyle($styles as map(*), $node as element()) {
    $styles?($node/w:rPr/w:rStyle/@w:val)
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

declare function docx:external-link($rels as element()*, $node as element()) {
    $rels/rel:Relationship[@Id=$node/@r:id]
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
    let $target :=
        if (contains($path, "/")) then
            let $relPath := replace($path, "^(.*?)/[^/]+$", "$1")
            let $newPath := docx:mkcol-recursive($targetCol, tokenize($relPath, "/"))
            return
                $targetCol || "/" || $relPath
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
