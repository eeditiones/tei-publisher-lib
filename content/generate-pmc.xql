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
xquery version "3.1";

(:~
 : Utility for generating an XQuery module providing a function to call
 : a transformation for each of the available ODDs.
 :
 : @author Wolfgang Meier
 :)
module namespace pmc="http://www.tei-c.org/tei-simple/xquery/config";

declare %private function pmc:parse-pi($doc as document-node()) {
    map:merge(
        for $pi in $doc/processing-instruction("teipublisher")
        let $analyzed := analyze-string($pi, '([^\s]+)\s*=\s*"(.*?)"')
        for $match in $analyzed/fn:match
        let $key := $match/fn:group[@nr="1"]/string()
        let $value := $match/fn:group[@nr="2"]/string()
        return
            map:entry($key, $value)
    )
};

declare %private function pmc:generate-cases($map as map(*), $mode as xs:string) {
    string-join(
        map:for-each($map, function($odd, $modes) {
            if (index-of($modes, $mode)) then
                ``[case "`{$odd}`.odd" return pm-`{$odd}`-`{$mode}`:transform($xml, $parameters)]``
            else
                ()
        }),
        "&#10;"
    )
};

declare %private function pmc:generate-default($map as map(*), $mode as xs:string, $defaultOdd as xs:string) {
    let $modes := $map?($defaultOdd)
    return
        if (exists($modes) and index-of($modes, $mode)) then
            ``[default return pm-`{$defaultOdd}`-`{$mode}`:transform($xml, $parameters)]``
        else
            ``[default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode `{$mode}`")]``
};

declare function pmc:generate-pm-config($odds as xs:string*, $default-odd as xs:string, $odd-root as xs:string) {
    let $map :=
        map:merge(
            for $odd in $odds
            let $source := doc($odd-root || "/" || $odd)
            let $pis := pmc:parse-pi($source)
            let $outputs :=
                if (map:contains($pis, "output")) then
                    tokenize($pis?output)
                else
                    ("web", "print", "latex", "epub")
            return
                map {
                    replace($odd, "^(.*?)\..*$", "$1"): $outputs
                }
        )
    let $imports :=
        map:for-each($map, function($odd, $modes) {
            for $mode in $modes
            let $prefix := if ($mode = "print") then "fo" else $mode
            return
``[import module namespace pm-`{$odd}`-`{$mode}`="http://www.tei-c.org/pm/models/`{$odd}`/`{$prefix}`/module" at "../transform/`{$odd}`-`{$mode}`-module.xql";]``
        })
    let $vars :=
        for $mode in ("web", "print", "latex", "epub", "tei")
        let $cases := pmc:generate-cases($map, $mode)
        return
            ``[
declare variable $pm-config:`{$mode}`-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    `{
        if ($cases != "") then
            ``[switch ($odd)
    `{ $cases }`
    `{ pmc:generate-default($map, $mode, replace($default-odd, "^(.*?)\..*$", "$1")) }`
            ]``
        else
    ``[error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode `{$mode}`")]``
    }`
    
};
            ]``
    return ``[
xquery version "3.1";

module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config";

`{string-join($imports, "&#10;")}`
`{string-join($vars, "&#10;&#10;")}`
    ]``
};