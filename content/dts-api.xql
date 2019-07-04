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
    let $endpoint := request:get-parameter("endpoint", ())
    return
        if (not($endpoint)) then
            dts:base-endpoint($config)
        else
            switch ($endpoint)
                case "documents" return
                    dts:documents()
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
    let $id := request:get-parameter("id", "default")
    let $page := number(request:get-parameter("page", 1))
    let $collectionInfo := $config?dts-collections($id)
    let $resources := $collectionInfo?members()
    let $count := count($resources)
    let $paged := subsequence($resources, ($page - 1) * $config?dts-page-size + 1, $config?dts-page-size)
    let $members := dts:get-members($config, $collectionInfo, $paged)
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
            "member": array { $members }
        }
};

declare function dts:get-members($config as map(*), $collectionInfo as map(*), $resources as node()*) {
    for $resource in $resources
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

declare function dts:documents() {
    let $id := request:get-parameter("id", ())
    return (
        util:declare-option("output:method", "xml"),
        util:declare-option("output:media-type", "application/tei+xml"),
        doc($id)
    )
};
