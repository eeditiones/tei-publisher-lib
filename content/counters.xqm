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
 : Manage counters for footnotes etc. Since the counter module is rather slow, we use
 : the HTTP request to keep track of counters where possible.
 :)
module namespace counters="http://www.tei-c.org/tei-simple/xquery/counters";

import module namespace counter="http://exist-db.org/xquery/counter" at "java:org.exist.xquery.modules.counter.CounterModule";

declare function counters:create($id as xs:string) {
    if (request:exists()) then
        let $map := counters:get-or-create($id)
        let $newMap := map:merge(($map, map:entry($id, 0)))
        return
            request:set-attribute("pm:counters", $newMap)
    else
        counter:create($id)
};
        
declare function counters:increment($id as xs:string) {
    if (request:exists()) then
        let $map := counters:get-or-create($id)
        let $inc := $map($id) + 1
        let $newMap := map:merge(($map, map:entry($id, $inc)))
        return (
            request:set-attribute("pm:counters", $newMap),
            $inc
        )
    else
        counter:next-value($id)
};

declare function counters:destroy($id as xs:string) {
    if (request:exists()) then
        let $map := request:get-attribute('pm:counters')
        return
            if (exists($map)) then
                request:set-attribute('pm:counters', map:remove($map, $id))
            else
                ()
    else
        counter:destroy($id)
};

declare %private function counters:get-or-create($id as xs:string) {
    (request:get-attribute('pm:counters'), map:entry($id, 0))[1]
};