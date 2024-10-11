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
 : Utility functions for parsing an ODD and running a transformation.
 : This module is the main entry point for transformations based on
 : the TEI Simple ODD extensions.
 :
 : @author Wolfgang Meier
 :)
module namespace pmu="http://www.tei-c.org/tei-simple/xquery/util";

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace odd="http://www.tei-c.org/tei-simple/odd2odd";
import module namespace pm="http://www.tei-c.org/tei-simple/xquery/model";
import module namespace css="http://www.tei-c.org/tei-simple/xquery/css";

declare variable $pmu:ERR_UNKNOWN_MODE := xs:QName("pmu:err-mode-unknown");

declare variable $pmu:MODULES := map {
    "web": map {
        "output": ["web"],
        "modules": [
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions",
                "prefix": "html"
            }
        ]
    },
    "fo": map {
        "output": ["fo"],
        "modules": [
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions/fo",
                "prefix": "fo"
            }
        ]
    },
    "print": map {
        "output": ["print", "web"],
        "modules": [
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions",
                "prefix": "html"
            },
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions/printcss",
                "prefix": "printcss"
            }
        ]
    },
    "epub": map {
        "output": ["epub", "web"],
        "modules": [
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions",
                "prefix": "html"
            },
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions/epub",
                "prefix": "epub"
            }
        ]
    },
    "latex": map {
        "output": ["latex"],
        "modules": [
            map {
                "uri": "http://www.tei-c.org/tei-simple/xquery/functions/latex",
                "prefix": "latex"
            }
        ]
    },
    "tei": map {
        "output": ["tei"],
        "modules": [
            map {
                "uri": "http://existsolutions.com/xquery/functions/tei",
                "prefix": "tei"
            }
        ]
    }
};

declare function pmu:process($odd as xs:string, $xml as node()*, $output-root as xs:string) {
    pmu:process($odd, $xml, $output-root, "web", "", ())
};

declare function pmu:process($odd as xs:string, $xml as node()*, $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string, $config as element(modules)?) {
    pmu:process($odd, $xml, $output-root, $mode, $relPath, $config, ())
};

declare function pmu:process($oddPath as xs:string, $xml as node()*, $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string, $config as element(modules)?, $parameters as map(*)?) {
    let $oddSource := doc($oddPath)
    let $oddFile := replace($oddPath, "^.*?([^/]+)$", "$1")
    let $name := replace($oddPath, "^.*?([^/\.]+)\.[^\.]+$", "$1")
    let $collection := replace($oddPath, "^(.*?)/[^/]+$", "$1")
    let $uri := $output-root || "/" || $name || "-" || $mode || "-main.xql"
    (: let $main :=
        if (pmu:requires-update($oddSource, $output-root, $name || "-" || $mode || "-main.xql")) then
            let $log := util:log('WARN', "Update required: " || $name)
            let $odd := odd:get-compiled($collection, $oddFile)
            let $config := pmu:process-odd($odd, $output-root, $mode, $relPath, $config)
            return
                $config?main
        else
            $uri :)
    return
        util:eval(xs:anyURI($uri), false(), (xs:QName("xml"), $xml, xs:QName("parameters"), $parameters))
};

declare function pmu:process-odd($odd as document-node(), $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string, $config as element(modules)?) as map(*) {
        pmu:process-odd($odd, $output-root, $mode, $relPath, $config, false())
};

(:~
 : Compile the given ODD into an XQuery module.
 :
 : @param $odd the ODD document to compile
 : @param $output-root collection URI into which to write generated files
 : @param $mode the output mode (web, print etc.) for which to generate files
 : @param $relPath path relative to the generated code for loading CSS etc.
 : @param $trackIds if true, elements generated from a model of the ODD will have an @data-tei attribute
 : referencing the TEI XML node which triggered the model. This is used to track elements between HTML and TEI. 
 :)
declare function pmu:process-odd($odd as document-node(), $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string, $config as element(modules)?, $trackIds as xs:boolean?) as map(*) {
    let $oddPath := ($odd/*/@source, document-uri(root($odd)))[1]
    let $name := replace($oddPath, "^.*?([^/\.]+)\.[^\.]+$", "$1")
    let $modulesDefault := pmu:parse-config-properties($mode, $name, $config, $pmu:MODULES?($mode))
    let $ext-modules := pmu:parse-config($name, $mode, $config)
    let $module :=
        if (exists($ext-modules)) then
            map:merge(($modulesDefault, map:entry("modules", array { $modulesDefault?modules?*, $ext-modules })))
        else
            $modulesDefault
    return
        if (empty($module)) then
            error($pmu:ERR_UNKNOWN_MODE, "output mode " || $mode || " is unknown")
        else
            let $generated := pm:parse($odd/*, pmu:fix-module-paths($module?modules, $config/module), $module?output?*, $trackIds)
            let $error := util:compile-query($generated?code, $output-root || "/")
            return
                if ($error/error) then
                    let $xquery := xmldb:store($output-root, $name || "-" || $mode || ".invalid.xql", $generated?code, "application/xquery")
                    return
                        map {
                            "id": $name,
                            "uri": $generated?uri,
                            "module":  $xquery,
                            "error": $error,
                            "code": $generated?code
                        }
                else
                    let $xquery := 
                        xmldb:store($output-root, $name || "-" || $mode || ".xql", $generated?code, "application/xquery")
                        => substring-after(replace($output-root, "/*$", "") || "/")
                    let $style := pmu:extract-styles($odd, $name, $oddPath, $output-root)
                    let $main := pmu:generate-main($name, $generated?uri, $xquery, $ext-modules, $output-root, $mode, $relPath, $style, $config)
                    let $module := pmu:generate-module($name, $generated?uri, $xquery, $ext-modules, $output-root, $mode, $relPath, $style, $config)
                    return
                        map {
                            "id": $name,
                            "uri": $generated?uri,
                            "module": $xquery,
                            "style": $style,
                            "main": $main
                        }
};

declare function pmu:generate-module($name as xs:string, $uri as xs:string,
    $xqueryFile as xs:string, $ext-modules as map(*)*, $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string?, $style as xs:string?,
    $config as element(modules)?) {
    let $mainCode :=
        "module namespace pml='" || $uri || "/module" || "';&#10;&#10;" ||
        "import module namespace m='" || $uri ||
        "' at '" || $xqueryFile || "';&#10;&#10;" ||
        "(: Generated library module to be directly imported into code which&#10;" ||
        " : needs to transform TEI nodes using the ODD this module is based on.&#10;" ||
        " :)&#10;" ||
        "declare function pml:transform($xml as node()*, $parameters as map(*)?) {&#10;&#10;" ||
        "   let $options := map {&#10;" ||
        pmu:properties($name, $mode, $config) ||
        '       "styles": ["' || $relPath || "/" || $style || '"],&#10;' ||
        '       "collection": "' || $output-root || '",&#10;' ||
        '       "parameters": if (exists($parameters)) then $parameters else map {}&#10;' ||
        '   }&#10;' ||
        "   return m:transform($options, $xml)&#10;" ||
        "};"
    return
        xmldb:store($output-root, $name || "-" || $mode || "-module.xql", $mainCode, "application/xquery")
};

declare function pmu:generate-main($name as xs:string, $uri as xs:string, $xqueryFile as xs:string,
    $ext-modules as map(*)*, $output-root as xs:string,
    $mode as xs:string, $relPath as xs:string?, $style as xs:string?,
    $config as element(modules)?) {
    let $mainCode :=
        "import module namespace m='" || $uri ||
        "' at '" || $xqueryFile || "';&#10;&#10;" ||
        "declare variable $xml external;&#10;&#10;" ||
        "declare variable $parameters external;&#10;&#10;" ||
        "let $options := map {&#10;" ||
        pmu:properties($name, $mode, $config) ||
        '    "styles": ["' || $relPath || "/" || $style || '"],&#10;' ||
        '    "collection": "' || $output-root || '",&#10;' ||
        '    "parameters": if (exists($parameters)) then $parameters else map {}&#10;' ||
        '}&#10;' ||
        "return m:transform($options, $xml)"
    let $stored :=
        xmldb:store($output-root, $name || "-" || $mode || "-main.xql", $mainCode, "application/xquery")
    let $chmod := sm:chmod($stored, "rwxrwxr-x")
    return
        $stored
};

declare function pmu:extract-styles($odd as document-node(), $name as xs:string, $oddPath as xs:string, $output-root as xs:string) {
    let $style := css:generate-css($odd, "web", $oddPath)
    let $path :=
        xmldb:store($output-root, $name || ".css", $style, "text/css")
    return
        $name || ".css"
};

declare function pmu:parse-config-properties($odd as xs:string, $mode as xs:string, $config as element(modules)?, $defaultConfig as map(*)) {
    if ($config) then
        let $props := $config/output[@mode = $mode][not(@odd) or @odd = $odd]/property
        return
            map:merge(($defaultConfig, map { "properties": $props }))
    else
        $defaultConfig
};


declare %private function pmu:parse-config($odd as xs:string, $mode as xs:string, $config as element(modules)?) {
    if ($config) then
        for $module in
            $config/output[empty(@mode) or @mode = $mode][empty(@odd) or @odd = $odd]/module
        let $map :=
            map {
                "uri": $module/@uri,
                "prefix": $module/@prefix,
                "properties": $module/property
            }
        return
            if ($module/@at) then
                map:merge(($map, map { "at": $module/@at }))
            else
                $map
    else
        ()
};

declare function pmu:properties($odd as xs:string, $mode as xs:string,
    $config as element(modules)?) {
    let $properties :=
        for $property in $config/output[@mode = $mode][not(@odd) or @odd = $odd]//property
        return
            '    "' || $property/@name || '": ' || normalize-space($property)
    return
        if (exists($properties)) then
            string-join($properties, ",&#10;") || ",&#10;"
        else
            ()
};

declare %private function pmu:requires-update($odd as document-node(), $collection as xs:string, $file as xs:string) {
    let $oddModified := xmldb:last-modified(util:collection-name($odd), util:document-name($odd))
    let $fileModified := xmldb:last-modified($collection, $file)
    return
        empty($fileModified) or $oddModified > $fileModified
};

(:~
 : Normalize module import paths: for inspection we need an absolute path, but the final
 : import should use a relative path. We thus provide both: "at" and "atRel".
 :
 : Additionally config.xqm gets imported into every module by default.
 :)
declare %private function pmu:fix-module-paths($modules as array(*), $globalModules as element(module)*) {
    let $sysPath := system:get-module-load-path()
    return
        array {
            for $module in $modules?*
            return
                if (not(map:contains($module, "at")) or matches($module?at, "^(/|xmldb:).*")) then
                    $module
                else
                    map:merge(($module, map {
                        "at":
                            if (ends-with($sysPath, "/modules/lib/api")) then
                                $sysPath || "/../../" || $module?at
                            else
                                $sysPath || "/modules/" || $module?at,
                        "atRel": "../modules/" || $module?at
                    })),
            for $module in $globalModules
            return
                map {
                    "uri": $module/@uri,
                    "prefix": $module/@prefix,
                    "at": 
                        if (ends-with($sysPath, "/modules/lib/api")) then
                            $sysPath || "/../../" || $module/@at
                        else
                            $sysPath || "/modules/" || $module/@at,
                    "atRel": "../modules/" || $module/@at
                }
        }
};
