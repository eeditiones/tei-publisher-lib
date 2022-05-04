(:
 :
 :  Copyright (C) 2019 Wolfgang Meier
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

module namespace dts="https://w3id.org/dts/api#";

declare namespace expath="http://expath.org/ns/pkg";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

declare option output:method "json";
declare option output:media-type "application/ld+json";

declare function dts:process($config as map(*)) {
    response:set-header("Access-Control-Allow-Origin", "*"),
    let $endpoint := request:get-parameter("endpoint", ())
    return
        if (not($endpoint)) then
            dts:base-endpoint($config)
        else
            switch ($endpoint)
                case "documents" return
                    dts:documents($config)
                default return
                    dts:collection($config)
};


declare function dts:base-path($config as map(*)) {
    let $appLink := substring-after($config?app-root, repo:get-root())
    let $path := string-join((request:get-context-path(), request:get-attribute("$exist:prefix"), $appLink, "api", "dts"), "/")
    return
        replace($path, "/+", "/")
};

declare function dts:base-endpoint($config as map(*)) {
    let $base := dts:base-path($config)
    return
        map {
            "@type": "EntryPoint",
            "collections": $base || "/collections",
            "@id": "/api/dts",
            "navigation": $base || "/navigation",
            "@context": "dts/EntryPoint.jsonld",
            "documents": $base || "/documents"
        }
};

declare function dts:collection($config as map(*)) {
    let $id := request:get-parameter("id", ())
    let $page := number(request:get-parameter("page", 1))
    let $collectionInfo :=
        if ($id) then
            dts:collection-by-id($config?dts-collections, $id)
        else
            $config?dts-collections
    return
        if (exists($collectionInfo)) then
            let $resources := if (map:contains($collectionInfo, "members")) then $collectionInfo?members() else ()
            let $count := count($resources)
            let $paged := subsequence($resources, ($page - 1) * $config?dts-page-size + 1, $config?dts-page-size)
            let $memberResources := dts:get-members($config, $collectionInfo, $paged)
            let $memberCollections := dts:get-members($config, $collectionInfo, $collectionInfo?memberCollections)
            return
                map {
                    "@context": map {
                        "@vocab": "https://www.w3.org/ns/hydra/core#",
                        "dc": "http://purl.org/dc/terms/",
                        "dts": "https://w3id.org/dts/api#"
                    },
                    "@type": "Collection",
                    "title": $collectionInfo?title,
                    "totalItems": $count,
                    "member": array { $memberResources, $memberCollections }
                }
        else
            response:set-status-code(404)
};

declare function dts:collection-by-id($collectionInfo as map(*), $id as xs:string) {
    if ($collectionInfo?id = $id) then
        $collectionInfo
    else
        for $member in $collectionInfo?memberCollections
        return
            dts:collection-by-id($member, $id)
};

declare function dts:get-members($config as map(*), $collectionInfo as map(*), $resources as item()*) {
    for $resource in $resources
    return
        typeswitch($resource)
            case map(*) return
                map {
                    "@id": $resource?id,
                    "title": $resource?title,
                    "@type": "Collection"
                }
            default return
                let $id := util:document-name($resource)
                return
                    map:merge((
                        map {
                            "@id": $id,
                            "title": $id,
                            "@type": "Resource",
                            "dts:passage": dts:base-path($config) || "/documents?id=" || $collectionInfo?path || "/" || $id
                        },
                        $collectionInfo?metadata(root($resource))
                    ))
};

declare function dts:documents($config as map(*)) {
    let $id := request:get-parameter("id", ())
    let $doc := doc($id)
    return
        if ($doc) then (
            util:declare-option("output:method", "xml"),
            util:declare-option("output:media-type", "application/tei+xml"),
            dts:check-pi($config, $doc)
        ) else
            response:set-status-code(404)
};

declare function dts:check-pi($config as map(*), $doc as document-node()) {
    let $pi := $doc/processing-instruction("teipublisher")
    return
        if ($pi) then
            $doc
        else
            document {
                processing-instruction teipublisher {
                    ``[odd="`{$config?default-odd}`" view="`{$config?view}`" template="`{$config?template}`"]``
                },
                $doc/node()
            }
};
