<?php

	/*
	 * Author: Andreas Linde <mail@andreaslinde.de>
	 *
	 * Copyright (c) 2009-2014 Andreas Linde & Kent Sutherland.
	 * All rights reserved.
	 *
	 * Permission is hereby granted, free of charge, to any person
	 * obtaining a copy of this software and associated documentation
	 * files (the "Software"), to deal in the Software without
	 * restriction, including without limitation the rights to use,
	 * copy, modify, merge, publish, distribute, sublicense, and/or sell
	 * copies of the Software, and to permit persons to whom the
	 * Software is furnished to do so, subject to the following
	 * conditions:
	 *
	 * The above copyright notice and this permission notice shall be
	 * included in all copies or substantial portions of the Software.
	 *
	 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	 * OTHER DEALINGS IN THE SOFTWARE.
	 */

//
// Regroup crashes
//
// This script takes parameters that specify which crashes to regroup.
// It then regroups them.
//

require_once('../config.php');
require_once('common.inc');

$allowed_args = ',bundleidentifier,version,groupid,';

$link = mysqli_connect($server, $loginsql, $passsql, $base)
    or die(end_with_result('No database connection'));

foreach(array_keys($_GET) as $k) {
    $temp = ",$k,";
    if(strpos($allowed_args,$temp) !== false) { $$k = $_GET[$k]; }
}

if (!isset($bundleidentifier)) $bundleidentifier = "";
if (!isset($version)) $version = "";

if ($bundleidentifier == "" || $version == "") die(end_with_result('Wrong parameters'));

$query1 = "SELECT id, applicationname FROM ".$dbcrashtable." WHERE ";
if (isset($groupid)) {
	$query1 .= "groupid = '".$groupid."' and ";
}
$query1 .= "version = '".$version."' and bundleidentifier = '".$bundleidentifier."'";
$result1 = mysqli_query($link, $query1) or die(end_with_result('Error in SQL '.$query1));

$numrows1 = mysqli_num_rows($result1);
if ($numrows1 > 0) {
    // get the status
    while ($row1 = mysqli_fetch_row($result1)) {
        $crashid = $row1[0];
        $applicationname = $row1[1];
	    
	    // get the log data
        $logdata = "";

   	    $query = "SELECT log FROM ".$dbcrashtable." WHERE id = '".$crashid."' ORDER BY systemversion desc, timestamp desc LIMIT 1";
        $result = mysqli_query($link, $query) or die(end_with_result('Error in SQL '.$query));

        $numrows = mysqli_num_rows($result);
        if ($numrows > 0) {
            // get the status
            $row = mysqli_fetch_row($result);
            $logdata = $row[0];
	
            mysqli_free_result($result);
        }
        
        $crash["bundleidentifier"] = $bundleidentifier;
        $crash["version"] = $version;
        $crash["logdata"] = $logdata;
        $crash["id"] = $crashid;
        $error = groupCrashReport($crash, $link, NOTIFY_OFF);
        if ($error != "") {
            die(end_with_result($error));
        }        
    }
	    
    mysqli_free_result($result1);
}

mysqli_close($link);
?>
<html>
<head>
    <META http-equiv="refresh" content="0;URL=groups.php?&bundleidentifier=<?php echo $bundleidentifier ?>&version=<?php echo $version ?>">
</head>
<body>
Redirecting...
</body>
</html>
