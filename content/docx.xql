xquery version "3.1";

module namespace docx="http://existsolutions.com/teipublisher/docx";

declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties";
declare namespace rel="http://schemas.openxmlformats.org/package/2006/relationships";
declare namespace r="http://schemas.openxmlformats.org/officeDocument/2006/relationships";

import module namespace compression="http://exist-db.org/xquery/compression" at "java:org.exist.xquery.modules.compression.CompressionModule";

declare function docx:process($path as xs:string, $dataRoot as xs:string, $transform as function(*),
    $odd as xs:string) {
    if (util:binary-doc-available($path)) then
        let $tempColl := docx:mkcol-recursive($dataRoot, "temp")
        let $unzipped := docx:unzip($dataRoot || "/temp", $path)
        let $document := doc($unzipped || "/word/document.xml")
        let $styles := docx:extract-styles(doc($unzipped || "/word/styles.xml")/w:styles)
        let $numbering := doc($unzipped || "/word/numbering.xml")/w:numbering
        let $endnotes := doc($unzipped || "/word/endnotes.xml")/w:endnotes
        let $footnotes := doc($unzipped || "/word/footnotes.xml")/w:footnotes
        let $properties := doc($unzipped || "/docProps/core.xml")/cp:coreProperties
        let $rels := doc($unzipped || "/word/_rels/document.xml.rels")/rel:Relationships
        let $params := map {
            "styles": $styles,
            "pstyle": docx:pstyle($styles, ?),
            "cstyle": docx:cstyle($styles, ?),
            "nstyle": docx:nstyle($numbering, ?),
            "endnote": docx:endnote($endnotes, ?),
            "footnote": docx:footnote($footnotes, ?),
            "link": docx:external-link($rels, ?),
            "rels": $rels,
            "properties": $properties
        }
        return
            $transform($document, $params, $odd)
    else
        ()
};

declare function docx:pstyle($styles as map(*), $node as element()) {
    for $styleId in $node/w:pPr/w:pStyle/@w:val
    return
        $styles($styleId)
};

declare function docx:cstyle($styles as map(*), $node as element()) {
    for $styleId in $node/w:rPr/w:rStyle/@w:val
    return
        $styles($styleId)
};

declare function docx:nstyle($numbering as element()*, $node as element()) {
    let $ref := $node/w:pPr/w:numPr
    let $lvl := $ref/w:ilvl/@w:val
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
