xquery version "3.1";

(:~ This library runs the XQSuite unit tests for the TEI Publisher: Processing Model Libraries.
 :
 : @author duncdrum
 : @version 1.0.0
 : @see http://www.exist-db.org/exist/apps/doc/xqsuite
 :)
import module namespace test="http://exist-db.org/xquery/xqsuite" at "resource:org/exist/xquery/lib/xqsuite/xqsuite.xql";
import module namespace ts="http://existsolutions.com/apps/tei-publisher-lib/tests" at "test-suite.xqm";

test:suite(
  inspect:module-functions(xs:anyURI("test-suite.xqm"))
)