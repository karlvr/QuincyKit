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
// Symbolicate a list of crash logs locally
//
// This script symbolicates crash log data on a local machine by
// querying a remote server for a todo list of crash logs and
// using remote script to fetch the crash log data and also update
// the very same on the remote servers
//

include "serverconfig.php";

function doGet($path) {
	global $scheme, $hostname, $webuser, $webpwd;
	
	$url = "$scheme://$hostname$path";

	$curl = curl_init($url);
	curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
	if ($webuser != '') {
		curl_setopt($curl, CURLOPT_USERPWD, "$webuser:$webpwd");
	}
    $response = curl_exec($curl);
	curl_close($curl);
	return $response;
}

function doPost($postdata)
{
	global $updatecrashdataurl, $scheme, $hostname, $webuser, $webpwd;
	
	$url = "$scheme://$hostname$updatecrashdataurl";

	$curl = curl_init($url);
    curl_setopt($curl, CURLOPT_POST, true);
    curl_setopt($curl, CURLOPT_POSTFIELDS, $postdata);
	curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
	if ($webuser != '') {
		curl_setopt($curl, CURLOPT_USERPWD, "$webuser:$webpwd");
	}
    $response = curl_exec($curl);
	curl_close($curl);
	return $response;
}

// get todo list from the server
$content = doGet($downloadtodosurl);

$error = false;

if ($content !== false && strlen($content) > 0)
{
	echo "To do list: ".$content."\n\n";
	$crashids = preg_split('/,/', $content);
	foreach ($crashids as $crashid)
	{
		$filename = $crashid.".crash";
		$resultfilename = "result_".$crashid.".crash";
	
		echo "Processing crash id ".$crashid." ...\n";
	
	
		echo "  Downloading crash data ...\n";
	
		$log = doGet($getcrashdataurl.$crashid);
	
		if ($log !== false && strlen($log) > 0)
		{
			echo "  Writing log data into temporary file ...\n";
				
			$output = fopen($filename, 'w+');
			fwrite($output, $log);
			fclose($output);
		
		
			echo "  Symbolicating ...\n";
			
			exec('DEVELOPER_DIR=$(xcode-select -p) perl ./symbolicatecrash.pl -o '.$resultfilename.' '.$filename);
	
			unlink($filename);
			
			if (file_exists($resultfilename) && filesize($resultfilename) > 0)
			{
				echo "  Sending symbolicated data back to the server ...";
				
				$resultcontent = file_get_contents($resultfilename);

				$post_results = doPost('id='.$crashid.'&log='.urlencode($resultcontent));
				
				if (is_string($post_results))
				{
					if (preg_match("/success$/", $post_results))
						echo "  SUCCESS!\n";
					else
						echo "  FAILURE\n";
			    } else {
					echo "  FAILURE\n";
				}

			}


			echo "  Deleting temporary files ...\n";

			unlink($resultfilename);
		}
	}
	
	echo "\nDone\n\n";
	
} else if ($content !== false) {
	echo "Nothing to do.\n\n";
}


?>