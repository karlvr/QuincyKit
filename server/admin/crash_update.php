<?php

	/*
	* Author: Andreas Linde <mail@andreaslinde.de>
	*
	* Copyright (c) 2009-2011 Andreas Linde.
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
// Update crash log data for a crash
//
// This script is used by the remote symbolicate process to update
// the database with the symbolicated crash log data for a given
// crash id
//

require_once('../config.php');


$allowed_args = ',id,log,';

$link = mysqli_connect($server, $loginsql, $passsql, $base)
    or die('error');

foreach(array_keys($_POST) as $k) {
    $temp = ",$k,";
    if(strpos($allowed_args,$temp) !== false) { $$k = $_POST[$k]; }
}

if (!isset($id)) $id = "";
if (!isset($log)) $log = "";

echo  $id." ".$log."\n";

if ($id == "" || $log == "") {
	mysqli_close($link);
	die('error');
}

$query = "UPDATE ".$dbcrashtable." SET log = '".mysqli_real_escape_string($link, $log)."' WHERE id = ".$id;
$result = mysqli_query($link, $query) or die('Error in SQL '.$dbcrashtable);

if ($result) {
	$query = "UPDATE ".$dbsymbolicatetable." SET done = 1 WHERE crashid = ".$id;
	$result = mysqli_query($link, $query) or die('Error in SQL '.$dbsymbolicatetable);
	
	if ($result)
		echo "success";
	else
		echo "error";
} else {
	echo "error";
}

mysqli_close($link);


?>