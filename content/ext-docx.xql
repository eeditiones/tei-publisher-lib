xquery version "3.1";

(:~
 : Extension functions for docx to TEI.
 :)
module namespace pmf="http://www.tei-c.org/tei-simple/xquery/functions/docx";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $pmf:INLINE_ELEMENTS := (
    "hi", "supplied", "persName", "placeName", "term"
);

declare function pmf:finish($config as map(*), $input as node()*) {
    pmf:create-divisions(pmf:combine($input))
    (: $input :)
};

declare %private function pmf:create-divisions($tei as element(tei:TEI)) {
    let $body := $tei/tei:text/tei:body
    let $firstHead := $body/tei:head[1]
    return
        if ($firstHead) then
            <TEI xmlns="http://www.tei-c.org/ns/1.0">
                { $tei/tei:teiHeader }
                <text>
                    <body>
                    {
                        $body/@*,
                        pmf:wrap-divisions($body/node())
                    }
                    </body>
                </text>
            </TEI>
        else
            $tei
};

(:~
 : Wrap headings and following text into a hierarchy of divisions using a "tumbling window" approach.
 :)
declare %private function pmf:wrap-divisions($body-nodes as node()*) {
    if ($body-nodes) then
        let $this := $body-nodes => head()
        let $rest := $body-nodes => tail()
        return
            if ($this instance of element(tei:head)) then
                let $level := number(head(($this/@pmf:level, 0)))
                let $next-window-start := $this/following-sibling::tei:head[@pmf:level <= $level] => head()
                let $next-window := $body-nodes[. is $next-window-start or . >> $next-window-start]
                let $this-window-rest :=
                    if ($next-window) then
                        $body-nodes[. >> $this and . << $next-window-start]
                    else
                        $body-nodes[. >> $this]
                return
                    (
                        <div xmlns="http://www.tei-c.org/ns/1.0">
                            <head>
                            {
                                $this/@* except $this/@pmf:level,
                                $this/node()
                            }
                            </head>
                            { $this-window-rest => pmf:wrap-divisions() }
                        </div>,
                        $next-window => pmf:wrap-divisions()
                    )

            else
                (
                    $this,
                    $rest => pmf:wrap-divisions()
                )
    else
        ()
};

declare %private function pmf:wrap-list($items as element()*) {
    if ($items) then
        let $item := head($items)
        return
            let $nested :=
                pmf:get-following-nested($item/following-sibling::*, (), $item/@pmf:level)
            return (
                <item xmlns="http://www.tei-c.org/ns/1.0">
                    <p>{ $item/node() }</p>
                    {
                        if ($nested) then
                            <list>
                            { if ($nested[1]/@pmf:type) then attribute type { $nested[1]/@pmf:type } else () }
                            { pmf:wrap-list($nested) }
                            </list>
                        else
                            ()
                    }
                </item>,
                pmf:wrap-list(tail($items) except $nested)
            )
    else
        ()
};

declare %private function pmf:get-following($nodes as node()*, $name as xs:string, $siblings as node()*,
    $level as item()?) {
    let $node := head($nodes)
    return
        if (local-name($node) = $name and (empty($level) or number($node/@pmf:level) >= number($level))) then
            pmf:get-following(tail($nodes), $name, ($siblings, $node), $level)
        else
            $siblings
};

declare %private function pmf:get-following-nested($nodes as node()*, $siblings as node()*,
    $level as item()?) {
    let $node := head($nodes)
    return
        if ($node instance of element(tei:item) and (empty($level) or number($node/@pmf:level) > number($level))) then
            pmf:get-following-nested(tail($nodes), ($siblings, $node), $level)
        else
            $siblings
};

declare %private function pmf:combine($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(tei:item) return
                if ($node/preceding-sibling::node()[1][self::tei:item]) then
                    ()
                else
                    let $sibs := pmf:get-following($node/following-sibling::*, "item", (), $node/@pmf:level)
                    return (
                        <list xmlns="http://www.tei-c.org/ns/1.0">
                        { if ($node/@pmf:type) then attribute type { $node/@pmf:type } else () }
                        { pmf:wrap-list(($node, $sibs)) }
                        </list>
                    )
            case element(tei:code) | element(tei:tag) return
                $node
            case element() return
                if (local-name($node) = $pmf:INLINE_ELEMENTS) then
                    if ($node/preceding-sibling::node()[1][local-name(.) = local-name($node)]) then
                        ()
                    else
                        let $following := pmf:get-following($node/following-sibling::node(), local-name($node), (), ())
                        return
                            if ($following) then
                                element { node-name($node) } {
                                    $node/@*,
                                    pmf:combine($node/node()),
                                    pmf:combine($following/node())
                                }
                            else
                                element { node-name($node) } {
                                    $node/@*,
                                    pmf:combine($node/node())
                                }
                else
                    element { node-name($node) } {
                        $node/@*,
                        pmf:combine($node/node())
                    }
            case text() return
                if (matches($node, '^(.*?)&#60;.*&#62;.*$')) then
                    replace($node, '^(.*?)&#60;.*&#62;(.*)$', '$1$2')
                else
                    $node
            default return $node
};