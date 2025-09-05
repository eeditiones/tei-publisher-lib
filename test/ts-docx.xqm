xquery version "3.1";

module namespace tdocx="http://existsolutions.com/apps/tei-publisher-lib/ts-docx";
declare namespace test="http://exist-db.org/xquery/xqsuite";
declare namespace w="http://schemas.openxmlformats.org/wordprocessingml/2006/main";
declare namespace rel="http://schemas.openxmlformats.org/package/2006/relationships";

import module namespace docx="http://existsolutions.com/teipublisher/docx" at "../content/docx.xql";

declare
  %test:assertTrue
function tdocx:extract-styles-maps-by-styleId() as xs:boolean {
  let $styles := <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:style w:styleId="Heading1"/>
    <w:style w:styleId="Normal"/>
  </w:styles>
  let $map := docx:extract-styles($styles)
  return map:contains($map, 'Heading1') and map:contains($map, 'Normal')
};

declare
  %test:assertTrue
function tdocx:pstyle-returns-style() as xs:boolean {
  let $styles := docx:extract-styles(<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:styleId="PStyle"/></w:styles>)
  let $p := <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:pPr><w:pStyle w:val="PStyle"/></w:pPr></w:p>
  return docx:pstyle($styles, $p)/@w:styleId = 'PStyle'
};

declare
  %test:assertTrue
function tdocx:cstyle-returns-style() as xs:boolean {
  let $styles := docx:extract-styles(<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:styleId="CStyle"/></w:styles>)
  let $r := <w:r xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:rPr><w:rStyle w:val="CStyle"/></w:rPr></w:r>
  return docx:cstyle($styles, $r)/@w:styleId = 'CStyle'
};

declare
  %test:assertTrue
function tdocx:nstyle-resolves-lvl() as xs:boolean {
  let $numbering := <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:abstractNum w:abstractNumId="10">
      <w:lvl w:ilvl="0"/>
      <w:lvl w:ilvl="1"/>
    </w:abstractNum>
    <w:num w:numId="5"><w:abstractNumId w:val="10"/></w:num>
  </w:numbering>
  let $styles := map {}
  let $p := <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="5"/></w:numPr></w:pPr></w:p>
  return docx:nstyle($numbering, $styles, $p)/@w:ilvl = '1'
};

declare
  %test:assertTrue
function tdocx:external-link-picks-correct-rels() as xs:boolean {
  let $rels := map {
    'document': <rel:Relationships xmlns:rel="http://schemas.openxmlformats.org/package/2006/relationships"><rel:Relationship Id="r1"/></rel:Relationships>,
    'footnotes': <rel:Relationships xmlns:rel="http://schemas.openxmlformats.org/package/2006/relationships"><rel:Relationship Id="r2"/></rel:Relationships>,
    'endnotes': <rel:Relationships xmlns:rel="http://schemas.openxmlformats.org/package/2006/relationships"><rel:Relationship Id="r3"/></rel:Relationships>
  }
  let $inDoc := <w:t xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="r1"/>
  let $inFn := <w:footnote xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:t xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="r2"/></w:footnote>
  let $inEn := <w:endnote xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:t xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="r3"/></w:endnote>
  return exists(docx:external-link($rels, $inDoc)) and exists(docx:external-link($rels, $inFn//*)) and exists(docx:external-link($rels, $inEn//*))
};

declare
  %test:assertTrue
function tdocx:endnote-returns-content() as xs:boolean {
  let $endnotes := <w:endnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:endnote w:id="2"><w:p/></w:endnote></w:endnotes>
  let $node := <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:endnoteReference w:id="2"/></w:p>
  return exists(docx:endnote($endnotes, $node))
};

declare
  %test:assertTrue
function tdocx:footnote-returns-content() as xs:boolean {
  let $footnotes := <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:id="5"><w:p/></w:footnote></w:footnotes>
  let $node := <w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnoteReference w:id="5"/></w:p>
  return exists(docx:footnote($footnotes, $node))
};

declare
  %test:assertTrue
function tdocx:comment-returns-content() as xs:boolean {
  let $comments := <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:comment w:id="7"><w:p/></w:comment></w:comments>
  let $node := <w:commentRangeStart xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" w:id="7"/>
  return exists(docx:comment($comments, $node))
};
