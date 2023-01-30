xquery version "3.1";

module namespace tmpl="http://www.tei-c.org/xquery/templates";

declare function tmpl:if-start($expression as xs:string) {
    string-join(("{if (model:bool(", $expression, ")) then "))
};

declare function tmpl:if-end() {
    " else ()}"
};

declare function tmpl:else() {
    " else "
};

declare function tmpl:loop-start($expression as xs:string, $useParamsMap as xs:boolean) {
    let $analyzed := analyze-string($expression, "^(.*?)\s+as\s+([\w_-]+)", "s")
    let $loopExpr := $analyzed//fn:group[@nr="1"]
    let $loopVar := $analyzed//fn:group[@nr="2"]
    return
        string-join((
            "for $",
            $loopVar,
            " in ",
            $loopExpr,
            if ($useParamsMap) then (
                ' let $params := map:merge(($params, map {"', $loopVar, '": $', $loopVar, '}))'
            ) else (),
            " return ("
        ))
};

declare function tmpl:loop-end() {
    ")"
};

declare function tmpl:process-tag($tag as xs:string, $expr as xs:string, $useParamsMap as xs:boolean) {
    switch ($tag)
        case "if" return
            tmpl:if-start($expr)
        case "endif" return
            tmpl:if-end()
        case "else" return
            tmpl:else()
        case "loop" return
            tmpl:loop-start($expr, $useParamsMap)
        case "endloop" return
            tmpl:loop-end()
        default return
            ()
};

declare function tmpl:expand($nodes as node()*, $useParamsMap as xs:boolean) {
    for $node in $nodes
    return
        typeswitch($node)
            case element(fn:non-match) return $node/string()
            case element(fn:match) return
                let $tag := $node//fn:group[@nr="1"]/string()
                let $expr := $node//fn:group[@nr="2"]
                let $expanded := tmpl:expand-substitutions($expr, if ($useParamsMap) then "\$params?$1" else "\$$1")
                return
                    tmpl:process-tag($tag, $expanded, $useParamsMap)
            default return
                $node
};

declare function tmpl:expand-substitutions($template as xs:string, $replacement as xs:string) {
    replace($template, "\[\[([^\[\]]*?)\]\]", $replacement)
};

declare function tmpl:parse($template as xs:string, $replacement as xs:string, $useParamsMap as xs:boolean) {
    tmpl:expand-substitutions(
        tmpl:expand(
            analyze-string($template, "\[%\s*(\w+)\s*([^%]*?)\s*%\]", "s")/node(),
            $useParamsMap
        )
        => string-join(), 
        if ($useParamsMap) then "\$params?$1" else "\$$1"
    )
};