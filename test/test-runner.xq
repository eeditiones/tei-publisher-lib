xquery version "3.1";

(:~ This library runs the XQSuite unit tests for the TEI Publisher: Processing Model Libraries.
 :
 : @author duncdrum
 : @version 1.0.0
 : @see http://www.exist-db.org/exist/apps/doc/xqsuite
 :)
import module namespace test="http://exist-db.org/xquery/xqsuite" at "resource:org/exist/xquery/lib/xqsuite/xqsuite.xql";
import module namespace tsc="http://existsolutions.com/apps/tei-publisher-lib/ts-css" at "ts-css.xqm";
import module namespace tsl="http://existsolutions.com/apps/tei-publisher-lib/ts-latex" at "ts-latex.xqm";
import module namespace tscn="http://existsolutions.com/apps/tei-publisher-lib/ts-counters" at "ts-counters.xqm";
import module namespace th="http://existsolutions.com/apps/tei-publisher-lib/ts-html" at "ts-html.xqm";
import module namespace ttei="http://existsolutions.com/apps/tei-publisher-lib/ts-tei" at "ts-tei.xqm";
import module namespace tfo="http://existsolutions.com/apps/tei-publisher-lib/ts-fo" at "ts-fo.xqm";
import module namespace tu="http://existsolutions.com/apps/tei-publisher-lib/ts-util" at "ts-util.xqm";
import module namespace tdocx="http://existsolutions.com/apps/tei-publisher-lib/ts-docx" at "ts-docx.xqm";
import module namespace ted="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-docx" at "ts-ext-docx.xqm";
import module namespace tep="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-epub" at "ts-ext-epub.xqm";
import module namespace tpc="http://existsolutions.com/apps/tei-publisher-lib/ts-ext-printcss" at "ts-ext-printcss.xqm";
import module namespace tpmc="http://existsolutions.com/apps/tei-publisher-lib/ts-pmc" at "ts-pmc.xqm";
import module namespace tdts="http://existsolutions.com/apps/tei-publisher-lib/ts-dts" at "ts-dts.xqm";
import module namespace tmodel="http://existsolutions.com/apps/tei-publisher-lib/ts-model" at "ts-model.xqm";

test:suite((
  inspect:module-functions(xs:anyURI("ts-css.xqm")),
  inspect:module-functions(xs:anyURI("ts-latex.xqm")),
  inspect:module-functions(xs:anyURI("ts-counters.xqm")),
  inspect:module-functions(xs:anyURI("ts-html.xqm")),
  inspect:module-functions(xs:anyURI("ts-tei.xqm")),
  inspect:module-functions(xs:anyURI("ts-fo.xqm")),
  inspect:module-functions(xs:anyURI("ts-util.xqm")),
  inspect:module-functions(xs:anyURI("ts-docx.xqm")),
  inspect:module-functions(xs:anyURI("ts-ext-docx.xqm")),
  inspect:module-functions(xs:anyURI("ts-ext-epub.xqm")),
  inspect:module-functions(xs:anyURI("ts-ext-printcss.xqm")),
  inspect:module-functions(xs:anyURI("ts-pmc.xqm")),
  inspect:module-functions(xs:anyURI("ts-dts.xqm")),
  inspect:module-functions(xs:anyURI("ts-odd.xqm")),
  inspect:module-functions(xs:anyURI("ts-xqgen.xqm")),
  inspect:module-functions(xs:anyURI("ts-model.xqm"))
))
